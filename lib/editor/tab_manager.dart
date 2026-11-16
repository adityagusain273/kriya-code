import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'highlighting/bcode_controller.dart';
import 'highlighting/highlight_engine.dart';
import 'highlighting/highlight_service.dart';
import 'recent_files_service.dart';
import '../../settings/settings_store.dart';
import '../../workspace/fs_service.dart';
import '../../core/di.dart';
import '../lsp/diagnostics.dart';
import 'find_replace.dart';

class EditorTab {
  String filePath;
  bool dirty = false;
  String? languageId;
  BCodeController? _controller;
  FindReplaceController? _findController;
  String _savedContent = '';
  Timer? autoSaveTimer;
  List<Diagnostic> runtimeDiagnostics = const [];
  String? _textAtLastRun;

  /// Monotonic load order, used to evict the least recently used tab.
  int lastUsedAt = 0;

  /// Whether the text buffer and controller exist. Session restore creates
  /// placeholders with only a path; the buffer loads on first selection.
  bool get isLoaded => _controller != null;

  BCodeController get controller => _controller!;
  FindReplaceController get findController => _findController!;

  void setRuntimeDiagnostics(List<Diagnostic> diags) {
    if (!isLoaded) return;
    runtimeDiagnostics = diags;
    _textAtLastRun = controller.text;
  }

  void clearRuntimeDiagnosticsIfModified() {
    if (!isLoaded) return;
    if (_textAtLastRun != null && controller.text != _textAtLastRun) {
      runtimeDiagnostics = const [];
      _textAtLastRun = null;
    }
  }

  /// Offset the editor should scroll to and select once this tab is on screen.
  ///
  /// Global search opens the file that matched, but opening it is not the same as
  /// showing the match: the user used search to find a line, and landing at the top
  /// of a long file means scrolling to find it again by hand. The offset is held
  /// here because the search result is produced on one screen and consumed on
  /// another.
  int? pendingRevealOffset;

  /// Selects [offset] and requests the editor bring it into view.
  void revealAt(int offset) {
    pendingRevealOffset = offset;
    if (!isLoaded) return;
    controller.selection = TextSelection(
      baseOffset: offset,
      extentOffset: offset,
    );
  }

  /// Consumes a pending reveal, so it only happens once.
  int? takePendingReveal() {
    final offset = pendingRevealOffset;
    pendingRevealOffset = null;
    return offset;
  }

  EditorTab({
    required this.filePath,
    required String content,
    this.languageId,
    Mode? language,
  }) {
    _attach(content, language);
  }

  /// Placeholder for a tab restored from the previous session. Holds the path
  /// only: no file read and no tokenization until [load] is called.
  EditorTab.lazy({required this.filePath, this.languageId});

  void _attach(String content, Mode? language) {
    final store = sl<SettingsStore>();
    _controller = BCodeController(
      text: content,
      language: language,
      params: EditorParams(tabSpaces: store.tabSize),
    );
    _findController = FindReplaceController(_controller!);
    _savedContent = content;
    dirty = false;
  }

  void load({
    required String content,
    String? languageId,
    Mode? language,
  }) {
    if (isLoaded) return;
    this.languageId = languageId ?? this.languageId;
    _attach(content, language);
  }

  /// Drops the text buffer of a clean background tab. The path and tab-strip
  /// metadata survive; selecting the tab reloads it from disk.
  void unload() {
    if (!isLoaded) return;
    autoSaveTimer?.cancel();
    autoSaveTimer = null;
    runtimeDiagnostics = const [];
    _textAtLastRun = null;
    pendingRevealOffset = null;
    _findController?.dispose();
    _controller?.dispose();
    _findController = null;
    _controller = null;
    _savedContent = '';
    dirty = false;
  }

  String get name => filePath.split('/').last;

  void checkDirty() {
    if (!isLoaded) return;
    // Length first: comparing a 100 KB buffer on every keystroke, for every
    // open tab, adds up. Only a same-length edit needs the content compare.
    final text = controller.text;
    final isDirty = text.length != _savedContent.length || text != _savedContent;
    if (isDirty != dirty) {
      dirty = isDirty;
    }
  }

  void markSaved() {
    if (!isLoaded) return;
    _savedContent = controller.text;
    dirty = false;
  }

  void dispose() {
    unload();
  }
}

class TabManager extends ChangeNotifier {
  final FsService fs;
  final HighlightService highlight;
  final HighlightEngine engine;
  SettingsStore? _settings;

  final List<EditorTab> tabs = [];
  int activeIndex = -1;
  SharedPreferences? _prefs;

  /// Maximum number of live [BCodeController]s. Clean background tabs beyond
  /// this are unloaded and reload from disk when selected.
  final int maxLoadedTabs;

  int _useClock = 0;
  Timer? _persistTimer;

  static const _sessionSaveDelay = Duration(milliseconds: 300);

  TabManager({
    required this.fs,
    required this.highlight,
    required this.engine,
    this.maxLoadedTabs = 5,
  });

  void attachSettings(SettingsStore settings) {
    _settings = settings;
  }

  /// Debounced autosave for the tab that was actually edited.
  ///
  /// This used to call a bare `save()`, which resolves to the *active* tab. Typing
  /// in a background tab therefore saved whatever happened to be in front instead,
  /// and the edit stayed dirty on disk indefinitely. The tab is also re-checked for
  /// membership at fire time: the debounce can outlive the tab, and writing through
  /// a disposed controller would throw.
  ///
  /// The timer lives on the tab, not on the manager: one shared timer meant
  /// typing in A, switching to B and typing within the debounce cancelled A's
  /// save entirely, leaving A dirty with no pending write.
  void _scheduleAutoSave(EditorTab tab) {
    tab.autoSaveTimer?.cancel();
    if (_settings == null || !_settings!.autoSave) return;
    tab.autoSaveTimer = Timer(Duration(milliseconds: _settings!.autoSaveDelayMs), () {
      if (tabs.contains(tab)) save(tab);
    });
  }

  EditorTab? get active => (activeIndex >= 0 && activeIndex < tabs.length) ? tabs[activeIndex] : null;

  Future<void> restoreSession() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = (_prefs?.getStringList('open_tabs') ?? const <String>[])
          .where(fs.exists)
          .toSet()
          .toList();
      if (saved.isEmpty) return;

      final activePath = _prefs?.getString('active_tab');
      final loadPath = (activePath != null && saved.contains(activePath))
          ? activePath
          : saved.first;

      // Only the tab that was in front gets its file read and tokenized. The
      // rest stay as path placeholders; restoring ten tabs used to mean ten
      // full reads and ten synchronous parses before the first keystroke.
      // If the active file cannot be read, fall back to the next saved path
      // instead of opening the editor with no tab at all.
      EditorTab? loaded;
      String? loadedPath;
      for (final path in [loadPath, ...saved.where((p) => p != loadPath)]) {
        try {
          loaded = await _createTab(path);
          loadedPath = path;
          break;
        } catch (e) {
          debugPrint('TabManager: skipped restoring tab "$path": $e');
        }
      }

      for (final path in saved) {
        final tab = loaded;
        if (tab != null && path == loadedPath) {
          tabs.add(tab);
        } else {
          tabs.add(EditorTab.lazy(filePath: path));
        }
      }

      if (loaded != null) {
        loaded.lastUsedAt = ++_useClock;
        activeIndex = tabs.indexOf(loaded);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('TabManager: failed to restore session: $e');
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_sessionSaveDelay, _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setStringList(
        'open_tabs',
        tabs.map((t) => t.filePath).toList(),
      );
      final current = active;
      if (current != null) await prefs.setString('active_tab', current.filePath);
    } catch (e) {
      debugPrint('TabManager: failed to persist session: $e');
    }
  }

  /// Writes a pending session immediately. The editor calls this when the app
  /// backgrounds, so the 300 ms debounce cannot outlive the process.
  Future<void> flushSession() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistNow();
  }

  void dropLanguages(Iterable<String> languageIds) {
    final removed = languageIds.toSet();
    if (removed.isEmpty) return;
    var changed = false;
    for (final tab in tabs) {
      if (!removed.contains(tab.languageId)) continue;
      tab.languageId = null;
      if (tab.isLoaded) tab.controller.language = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<String> _readContent(String path) async {
    if (!fs.exists(path)) return '';
    // A multi-hundred-MB file would be decoded, highlighted in full, and then
    // duplicated in memory by EditorTab. Refuse rather than OOM.
    try {
      final length = await File(path).length();
      if (length > 5 * 1024 * 1024) {
        throw StateError(
            'File is too large to edit (${length ~/ (1024 * 1024)} MB).');
      }
    } catch (e) {
      if (e is StateError) rethrow;
    }
    return fs.readFile(path);
  }

  Future<EditorTab> _createTab(String path) async {
    final languageId = await highlight.languageIdFor(path);
    final grammar = await engine.grammarFor(languageId);
    final content = await _readContent(path);
    // Syntax highlighting runs synchronously on the UI isolate on every edit and
    // re-tokenizes the entire document (~4-6 ms/KB on a mid-range phone). The old
    // 256k cutoff allowed a 50 KB file to spend ~300 ms per keystroke. 40k keeps
    // typing interactive at the cost of colour in large files; several bundled
    // grammars are also pathological on adversarial input.
    final effectiveGrammar = content.length > 40000 ? null : grammar;
    final tab = EditorTab(
      filePath: path,
      content: content,
      languageId: languageId,
      language: effectiveGrammar,
    );
    tab.controller.addListener(_makeTabListener(tab));
    return tab;
  }

  Future<void> _loadTab(EditorTab tab) async {
    if (tab.isLoaded) return;
    final languageId = tab.languageId ?? await highlight.languageIdFor(tab.filePath);
    final grammar = await engine.grammarFor(languageId);
    final content = await _readContent(tab.filePath);
    final effectiveGrammar = content.length > 40000 ? null : grammar;
    tab.load(
      content: content,
      languageId: languageId,
      language: effectiveGrammar,
    );
    tab.controller.addListener(_makeTabListener(tab));
  }

  /// Unloads clean background tabs beyond [maxLoadedTabs], least recently used
  /// first. Dirty tabs are never evicted: their buffer is the only copy.
  void _enforceBudget() {
    final limit = maxLoadedTabs < 1 ? 1 : maxLoadedTabs;
    var loaded = tabs.where((t) => t.isLoaded).length;
    if (loaded <= limit) return;
    final keep = (activeIndex >= 0 && activeIndex < tabs.length)
        ? tabs[activeIndex]
        : null;
    final candidates = tabs
        .where((t) => t.isLoaded && !t.dirty && !identical(t, keep))
        .toList()
      ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
    for (final tab in candidates) {
      if (loaded <= limit) break;
      tab.unload();
      loaded--;
    }
  }

  Future<EditorTab> open(String path) async {
    final existing = tabs.indexWhere((t) => t.filePath == path);
    if (existing != -1) {
      final tab = tabs[existing];
      await _loadTab(tab);
      activeIndex = existing;
      tab.lastUsedAt = ++_useClock;
      _enforceBudget();
      notifyListeners();
      _schedulePersist();
      return tab;
    }

    final tab = await _createTab(path);
    tabs.add(tab);
    activeIndex = tabs.length - 1;
    tab.lastUsedAt = ++_useClock;
    _enforceBudget();
    notifyListeners();
    _schedulePersist();
    await RecentFilesService.instance.add(path);
    return tab;
  }

  Future<void> save([EditorTab? tab]) async {
    final target = tab ?? active;
    if (target == null || !target.isLoaded) return;
    await fs.writeFile(target.filePath, target.controller.text);
    target.markSaved();
    notifyListeners();
  }

  Future<void> saveAll() async {
    for (final tab in tabs) {
      if (tab.dirty && tab.isLoaded) {
        await fs.writeFile(tab.filePath, tab.controller.text);
        tab.markSaved();
      }
    }
    notifyListeners();
  }

  bool get hasUnsavedChanges => tabs.any((t) => t.dirty);

  Future<bool> close(int index) async {
    if (index < 0 || index >= tabs.length) return false;
    final closingActive = index == activeIndex;
    final closing = tabs[index];

    // Load the tab that will take over *before* disposing the active one. The
    // old buffer stays alive across this await, so a rebuild triggered while
    // the file is read cannot reach a disposed controller.
    EditorTab? replacement;
    if (closingActive && tabs.length > 1) {
      final replacementIndex = index < tabs.length - 1 ? index + 1 : index - 1;
      replacement = tabs[replacementIndex];
      if (!replacement.isLoaded) {
        try {
          await _loadTab(replacement);
        } catch (e) {
          debugPrint('TabManager: could not load tab "${replacement.filePath}": $e');
          replacement = null;
        }
      }
    }

    closing.dispose();
    tabs.removeAt(index);

    if (tabs.isEmpty) {
      activeIndex = -1;
    } else if (closingActive) {
      if (replacement != null && replacement.isLoaded) {
        activeIndex = tabs.indexOf(replacement);
        replacement.lastUsedAt = ++_useClock;
      } else {
        activeIndex = -1;
      }
    } else if (index < activeIndex) {
      activeIndex--;
    }

    _enforceBudget();
    notifyListeners();
    _schedulePersist();
    return true;
  }

  Future<void> closeAll() async {
    for (final tab in tabs) {
      tab.dispose();
    }
    tabs.clear();
    activeIndex = -1;
    notifyListeners();
    _schedulePersist();
  }

  Future<void> activate(int index) async {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    if (!tab.isLoaded) {
      try {
        await _loadTab(tab);
      } catch (e) {
        debugPrint('TabManager: could not load tab "${tab.filePath}": $e');
        return;
      }
    }
    activeIndex = index;
    tab.lastUsedAt = ++_useClock;
    _enforceBudget();
    notifyListeners();
    _schedulePersist();
  }

  void handleFileRenamed(String oldPath, String newPath) {
    // A rename can target a directory: every tab inside it must follow, or its
    // next save silently recreates the file at the stale path.
    var changed = false;
    for (final tab in tabs) {
      if (tab.filePath == oldPath) {
        tab.filePath = newPath;
        changed = true;
      } else if (p.isWithin(oldPath, tab.filePath)) {
        tab.filePath = p.join(newPath, p.relative(tab.filePath, from: oldPath));
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _schedulePersist();
    }
  }

  Future<void> handleFileDeleted(String path) async {
    for (var i = tabs.length - 1; i >= 0; i--) {
      if (tabs[i].filePath == path || p.isWithin(path, tabs[i].filePath)) {
        await close(i);
      }
    }
  }

  String exportActiveText() {
    final tab = active;
    return tab != null && tab.isLoaded ? tab.controller.text : '';
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    for (final tab in tabs) {
      tab.autoSaveTimer?.cancel();
    }
    super.dispose();
  }

  VoidCallback _makeTabListener(EditorTab tab) {
    return () {
      final wasDirty = tab.dirty;
      tab.checkDirty();
      if (tab.dirty != wasDirty) {
        notifyListeners();
      }
      _scheduleAutoSave(tab);
    };
  }
}

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
  late final BCodeController controller;
  bool dirty = false;
  String? languageId;
  String _savedContent;
  late final FindReplaceController findController;
  Timer? autoSaveTimer;
  List<Diagnostic> runtimeDiagnostics = const [];
  String? _textAtLastRun;

  void setRuntimeDiagnostics(List<Diagnostic> diags) {
    runtimeDiagnostics = diags;
    _textAtLastRun = controller.text;
  }

  void clearRuntimeDiagnosticsIfModified() {
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
  }) : _savedContent = content {
    final store = sl<SettingsStore>();
    controller = BCodeController(
      text: content, 
      language: language,
      params: EditorParams(tabSpaces: store.tabSize),
    );
    findController = FindReplaceController(controller);
  }

  String get name => filePath.split('/').last;

  void checkDirty() {
    // Length first: comparing a 100 KB buffer on every keystroke, for every
    // open tab, adds up. Only a same-length edit needs the content compare.
    final text = controller.text;
    final isDirty = text.length != _savedContent.length || text != _savedContent;
    if (isDirty != dirty) {
      dirty = isDirty;
    }
  }

  void markSaved() {
    _savedContent = controller.text;
    dirty = false;
  }

  void dispose() {
    autoSaveTimer?.cancel();
    findController.dispose();
    controller.dispose();
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

  TabManager({
    required this.fs,
    required this.highlight,
    required this.engine,
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
      final saved = _prefs?.getStringList('open_tabs') ?? const [];
      for (final path in saved) {
        try {
          if (fs.exists(path)) await open(path);
        } catch (e) {
          debugPrint('TabManager: skipped restoring tab "$path": $e');
        }
      }
      final activePath = _prefs?.getString('active_tab');
      if (activePath != null) {
        final i = tabs.indexWhere((t) => t.filePath == activePath);
        if (i >= 0) activeIndex = i;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('TabManager: failed to restore session: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs?.setStringList('open_tabs', tabs.map((t) => t.filePath).toList());
      if (active != null) await _prefs?.setString('active_tab', active!.filePath);
    } catch (e) {
      debugPrint('TabManager: failed to persist session: $e');
    }
  }

  void dropLanguages(Iterable<String> languageIds) {
    final removed = languageIds.toSet();
    if (removed.isEmpty) return;
    var changed = false;
    for (final tab in tabs) {
      if (!removed.contains(tab.languageId)) continue;
      tab.languageId = null;
      tab.controller.language = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<EditorTab> open(String path) async {
    final existing = tabs.indexWhere((t) => t.filePath == path);
    if (existing != -1) {
      activeIndex = existing;
      notifyListeners();
      await _persist();
      return tabs[existing];
    }
    final languageId = await highlight.languageIdFor(path);
    final grammar = await engine.grammarFor(languageId);

    // A multi-hundred-MB file would be decoded, highlighted in full, and then
    // duplicated in memory by EditorTab. Refuse rather than OOM.
    var content = '';
    if (fs.exists(path)) {
      try {
        final entity = File(path);
        final length = await entity.length();
        if (length > 5 * 1024 * 1024) {
          throw StateError(
              'File is too large to edit (${length ~/ (1024 * 1024)} MB).');
        }
      } catch (e) {
        if (e is StateError) rethrow;
      }
      content = await fs.readFile(path);
    }
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
    tabs.add(tab);
    activeIndex = tabs.length - 1;
    notifyListeners();
    await _persist();
    await RecentFilesService.instance.add(path);
    return tab;
  }

  Future<void> save([EditorTab? tab]) async {
    final target = tab ?? active;
    if (target == null) return;
    await fs.writeFile(target.filePath, target.controller.text);
    target.markSaved();
    notifyListeners();
  }

  Future<void> saveAll() async {
    for (final tab in tabs) {
      if (tab.dirty) {
        await fs.writeFile(tab.filePath, tab.controller.text);
        tab.markSaved();
      }
    }
    notifyListeners();
  }

  bool get hasUnsavedChanges => tabs.any((t) => t.dirty);

  Future<bool> close(int index) async {
    if (index < 0 || index >= tabs.length) return false;
    tabs[index].dispose();
    tabs.removeAt(index);
    if (activeIndex >= tabs.length) {
      activeIndex = tabs.length - 1;
    } else if (index < activeIndex) {
      activeIndex--;
    }
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> closeAll() async {
    for (final tab in tabs) {
      tab.dispose();
    }
    tabs.clear();
    activeIndex = -1;
    notifyListeners();
    await _persist();
  }

  void activate(int index) {
    activeIndex = index;
    notifyListeners();
    _persist();
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
      _persist();
    }
  }

  Future<void> handleFileDeleted(String path) async {
    for (var i = tabs.length - 1; i >= 0; i--) {
      if (tabs[i].filePath == path || p.isWithin(path, tabs[i].filePath)) {
        await close(i);
      }
    }
  }

  String exportActiveText() => active?.controller.text ?? '';

  @override
  void dispose() {
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

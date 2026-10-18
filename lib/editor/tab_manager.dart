import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'highlighting/bcode_controller.dart';
import 'highlighting/highlight_engine.dart';
import 'highlighting/highlight_service.dart';
import 'recent_files_service.dart';
import '../../settings/settings_store.dart';
import '../../workspace/fs_service.dart';
import '../../core/di.dart';
import 'find_replace.dart';

class EditorTab {
  String filePath;
  late final BCodeController controller;
  bool dirty = false;
  String? languageId;
  String _savedContent;
  late final FindReplaceController findController;

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
    final isDirty = controller.text != _savedContent;
    if (isDirty != dirty) {
      dirty = isDirty;
    }
  }

  void markSaved() {
    _savedContent = controller.text;
    dirty = false;
  }

  void updateSavedContent() {
    _savedContent = controller.text;
  }

  void dispose() {
    controller.dispose();
    findController.dispose();
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
  Timer? _autoSaveTimer;

  TabManager({
    required this.fs,
    required this.highlight,
    required this.engine,
  });

  void attachSettings(SettingsStore settings) {
    _settings = settings;
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (_settings == null || !_settings!.autoSave) return;
    _autoSaveTimer = Timer(Duration(milliseconds: _settings!.autoSaveDelayMs), () {
      save();
    });
  }

  EditorTab? get active => (activeIndex >= 0 && activeIndex < tabs.length) ? tabs[activeIndex] : null;

  Future<void> restoreSession() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs?.getStringList('open_tabs') ?? const [];
      for (final path in saved) {
        if (fs.exists(path)) await open(path);
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
    final content = fs.exists(path) ? await fs.readFile(path) : '';
    final tab = EditorTab(
      filePath: path,
      content: content,
      languageId: languageId,
      language: grammar,
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
    target.updateSavedContent();
    notifyListeners();
    await _persist();
  }

  Future<void> saveAll() async {
    for (final tab in tabs) {
      if (tab.dirty) {
        await fs.writeFile(tab.filePath, tab.controller.text);
        tab.markSaved();
        tab.updateSavedContent();
      }
    }
    notifyListeners();
    await _persist();
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
    final index = tabs.indexWhere((t) => t.filePath == oldPath);
    if (index != -1) {
      tabs[index].filePath = newPath;
      notifyListeners();
      _persist();
    }
  }

  Future<void> handleFileDeleted(String path) async {
    final index = tabs.indexWhere((t) => t.filePath == path);
    if (index != -1) {
      await close(index);
    }
  }

  String exportActiveText() => active?.controller.text ?? '';

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  VoidCallback _makeTabListener(EditorTab tab) {
    return () {
      final wasDirty = tab.dirty;
      tab.checkDirty();
      if (tab.dirty != wasDirty) {
        notifyListeners();
      }
      _scheduleAutoSave();
    };
  }
}

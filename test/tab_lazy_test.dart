import 'dart:io';

import 'package:b_code/core/di.dart';
import 'package:b_code/editor/highlighting/highlight_engine.dart';
import 'package:b_code/editor/highlighting/highlight_service.dart';
import 'package:b_code/editor/tab_manager.dart';
import 'package:b_code/plugins/host/language_registry.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late FsService fs;
  late TabManager tabs;
  late SharedPreferences prefs;
  late List<File> files;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('bcode_lazy_tabs_');
    fs = FsService(root.path);
    files = [
      for (var i = 0; i < 3; i++)
        File('${root.path}/f$i.dart')..writeAsStringSync('void main() {}\n'),
    ];
    SharedPreferences.setMockInitialValues({
      'open_tabs': files.map((f) => f.path).toList(),
      'active_tab': files[1].path,
    });
    prefs = await SharedPreferences.getInstance();
    final engine = HighlightEngine();
    tabs = TabManager(
      fs: fs,
      highlight: HighlightService(registry: LanguageRegistry(), engine: engine),
      engine: engine,
      maxLoadedTabs: 1,
    );
    tabs.attachSettings(SettingsStore(prefs));
    sl.registerSingleton<SettingsStore>(SettingsStore(prefs));
  });

  tearDown(() {
    tabs.dispose();
    sl.reset();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('restore loads only the active tab buffer', () async {
    await tabs.restoreSession();

    expect(tabs.tabs, hasLength(3));
    expect(tabs.activeIndex, 1);
    expect(tabs.tabs[1].isLoaded, isTrue);
    expect(tabs.tabs[1].controller.text, contains('void main'));
    expect(tabs.tabs[0].isLoaded, isFalse);
    expect(tabs.tabs[2].isLoaded, isFalse);
  });

  test('falls back when the active tab cannot be read', () async {
    files[1].writeAsBytesSync([0, 1, 2]);

    await tabs.restoreSession();

    expect(tabs.tabs, hasLength(3));
    expect(tabs.activeIndex, 0);
    expect(tabs.tabs[0].isLoaded, isTrue);
    expect(tabs.tabs[1].isLoaded, isFalse);
  });

  test('selecting a placeholder evicts the least recently used clean tab',
      () async {
    await tabs.restoreSession();
    await tabs.activate(0);

    expect(tabs.activeIndex, 0);
    expect(tabs.tabs[0].isLoaded, isTrue);
    expect(tabs.tabs[1].isLoaded, isFalse);
  });

  test('dirty background tabs are never evicted', () async {
    await tabs.restoreSession();
    final dirty = tabs.tabs[1];
    dirty.controller.text = 'void main() { print(1); }\n';
    expect(dirty.dirty, isTrue);

    await tabs.activate(0);

    expect(dirty.isLoaded, isTrue);
    expect(tabs.tabs[0].isLoaded, isTrue);
  });

  test('closing the active tab loads its replacement', () async {
    await tabs.restoreSession();

    await tabs.close(1);

    expect(tabs.tabs, hasLength(2));
    expect(tabs.activeIndex, 1);
    expect(tabs.tabs[1].isLoaded, isTrue);
  });

  test('flushSession writes the tab list and active path', () async {
    await tabs.restoreSession();
    await tabs.flushSession();

    expect(prefs.getStringList('open_tabs'), files.map((f) => f.path).toList());
    expect(prefs.getString('active_tab'), files[1].path);
  });
}

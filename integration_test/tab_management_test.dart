import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:b_code/main.dart' as app;
import 'package:b_code/core/di.dart';
import 'package:b_code/editor/tab_manager.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:b_code/editor/highlighting/highlight_service.dart';
import 'package:b_code/editor/highlighting/highlight_engine.dart';
import 'package:b_code/plugins/host/language_registry.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Tab Management', () {
    late Directory tempDir;
    late FsService fsService;
    late TabManager tabManager;
    late SharedPreferences prefs;
    late LanguageRegistry languageRegistry;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      
      tempDir = Directory.systemTemp.createTempSync('bcode_integration_test');
      fsService = FsService(tempDir.path);
      
      final engine = HighlightEngine();
      languageRegistry = LanguageRegistry();
      final highlight = HighlightService(registry: languageRegistry, engine: engine);
      
      tabManager = TabManager(fs: fsService, highlight: highlight, engine: engine);
      tabManager.attachSettings(SettingsStore(prefs));
      
      sl.registerSingleton<FsService>(fsService);
      sl.registerSingleton<TabManager>(tabManager);
      sl.registerSingleton<SettingsStore>(SettingsStore(prefs));
      sl.registerSingleton<LanguageRegistry>(languageRegistry);
    });

    tearDownAll(() {
      tempDir.deleteSync(recursive: true);
      sl.reset();
    });

    testWidgets('open, edit, save, close tab', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Create a test file
      final testFile = File('${tempDir.path}/test.dart');
      await testFile.create(recursive: true);
      await testFile.writeAsString('void main() {\n  print("hello");\n}');

      // Open the file via tab manager
      final tab = await tabManager.open(testFile.path);
      expect(tab, isNotNull);
      expect(tab.filePath, testFile.path);
      expect(tab.controller.text, contains('void main()'));

      // Modify the file
      tab.controller.text = 'void main() {\n  print("modified");\n}';
      tab.checkDirty();
      expect(tab.dirty, isTrue);

      // Save the file
      await tabManager.save(tab);
      expect(tab.dirty, isFalse);
      
      // Verify file content
      final savedContent = await testFile.readAsString();
      expect(savedContent, contains('modified'));

      // Close the tab
      await tabManager.close(0);
      expect(tabManager.tabs.length, 0);
    });

    testWidgets('dirty tracking across multiple edits', (WidgetTester tester) async {
      final testFile = File('${tempDir.path}/test2.dart');
      await testFile.create(recursive: true);
      await testFile.writeAsString('print("v1");');

      final tab = await tabManager.open(testFile.path);
      
      // First edit
      tab.controller.text = 'print("v2");';
      tab.checkDirty();
      expect(tab.dirty, isTrue);
      
      // Save
      await tabManager.save(tab);
      expect(tab.dirty, isFalse);
      
      // Second edit
      tab.controller.text = 'print("v3");';
      tab.checkDirty();
      expect(tab.dirty, isTrue);
      
      // Save again
      await tabManager.save(tab);
      expect(tab.dirty, isFalse);
      
      await tabManager.close(0);
    });
  });
}
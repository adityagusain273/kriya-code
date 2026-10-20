import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:b_code/main.dart' as app;
import 'package:b_code/core/di.dart';
import 'package:b_code/execution/local/local_runner.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Code Execution', () {
    late Directory tempDir;
    late FsService fsService;
    late LocalRunner localRunner;
    late SharedPreferences prefs;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      
      tempDir = Directory.systemTemp.createTempSync('bcode_exec_test');
      fsService = FsService(tempDir.path);
      localRunner = LocalRunner();
      
      sl.registerSingleton<FsService>(fsService);
      sl.registerSingleton<LocalRunner>(localRunner);
      sl.registerSingleton<SettingsStore>(SettingsStore(prefs));
    });

    tearDownAll(() {
      tempDir.deleteSync(recursive: true);
      sl.reset();
    });

    testWidgets('runtime directory accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      final runtimeDir = await localRunner.runtimeRoot();
      expect(runtimeDir, isNotNull);
      expect(Directory(runtimeDir!).existsSync(), isTrue);
    });

    testWidgets('hasRuntime returns false for non-existent runtime', (WidgetTester tester) async {
      final hasRuntime = await localRunner.hasRuntime('nonexistent_runtime');
      expect(hasRuntime, isFalse);
    });
  });
}
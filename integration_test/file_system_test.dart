import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:b_code/main.dart' as app;
import 'package:b_code/core/di.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('File System Operations', () {
    late Directory tempDir;
    late FsService fsService;
    late SharedPreferences prefs;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      
      tempDir = Directory.systemTemp.createTempSync('bcode_fs_test');
      fsService = FsService(tempDir.path);
      
      sl.registerSingleton<FsService>(fsService);
      sl.registerSingleton<SettingsStore>(SettingsStore(prefs));
    });

    tearDownAll(() {
      tempDir.deleteSync(recursive: true);
      sl.reset();
    });

    testWidgets('create, read, write, delete file', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Create file
      await fsService.createFile('test.txt');
      expect(fsService.exists('test.txt'), isTrue);

      // Write file
      await fsService.writeFile('test.txt', 'Hello, World!');
      
      // Read file
      final content = await fsService.readFile('test.txt');
      expect(content, 'Hello, World!');

      // Delete file
      await fsService.delete('test.txt');
      expect(fsService.exists('test.txt'), isFalse);
    });

    testWidgets('create directory and nested files', (WidgetTester tester) async {
      await fsService.createDirectory('src/utils');
      expect(fsService.exists('src'), isTrue);
      expect(fsService.exists('src/utils'), isTrue);
      expect(fsService.isDirectory('src'), isTrue);

      await fsService.createFile('src/utils/helper.dart');
      await fsService.writeFile('src/utils/helper.dart', 'void helper() {}');
      
      final content = await fsService.readFile('src/utils/helper.dart');
      expect(content, 'void helper() {}');
    });

    testWidgets('rename file', (WidgetTester tester) async {
      await fsService.createFile('old_name.txt');
      await fsService.writeFile('old_name.txt', 'content');
      
      await fsService.rename('old_name.txt', 'new_name.txt');
      
      expect(fsService.exists('old_name.txt'), isFalse);
      expect(fsService.exists('new_name.txt'), isTrue);
      expect(await fsService.readFile('new_name.txt'), 'content');
    });

    testWidgets('move file to directory', (WidgetTester tester) async {
      await fsService.createDirectory('target_dir');
      await fsService.createFile('file_to_move.txt');
      await fsService.writeFile('file_to_move.txt', 'moved content');
      
      await fsService.move('file_to_move.txt', 'target_dir');
      
      expect(fsService.exists('file_to_move.txt'), isFalse);
      expect(fsService.exists('target_dir/file_to_move.txt'), isTrue);
    });

    testWidgets('rejects relative path escape', (WidgetTester tester) async {
      expect(() => fsService.resolve('../outside'), throwsArgumentError);
      expect(() => fsService.resolve('../../etc/passwd'), throwsArgumentError);
    });

    testWidgets('allows absolute paths for SAF access', (WidgetTester tester) async {
      final result = fsService.resolve('/etc/passwd');
      expect(result, '/etc/passwd');
    });
  });
}
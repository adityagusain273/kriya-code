import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/plugins/host/extension_install_store.dart';
import 'package:b_code/workspace/explorer_prefs.dart';
import 'package:b_code/workspace/file_explorer.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps several frames to flush chained futures without requiring
/// animation quiescence (the loading spinner never stops animating).
///
/// `FsService.list` reads the directory asynchronously now, and widget tests
/// run in fake-async time, where real file I/O never completes. `runAsync`
/// gives it a slice of real time before each frame.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('ExplorerPrefs', () {
    test('round-trips expanded folders', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ExplorerPrefs(prefs);

      expect(store.loadExpanded(), isEmpty);

      store.saveExpanded({'src', 'lib/core'});
      expect(store.loadExpanded(), {'src', 'lib/core'});
    });
  });

  group('FileExplorer expansion persistence', () {
    late Directory tempDir;
    late FsService fs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('bcode_explorer_test');
      fs = FsService(tempDir.path);
      await fs.createDirectory('src');
      await fs.writeFile('src/main.py', 'print("x")');

      // FileExplorer resolves ExtensionInstallStore while building (to gate the
      // "install this extension to run" hint), so the container needs one.
      sl.registerSingleton<ExtensionInstallStore>(
        ExtensionInstallStore(await SharedPreferences.getInstance()),
      );
    });

    tearDown(() async {
      sl.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget buildExplorer(ExplorerPrefs prefs) => MaterialApp(
          home: Scaffold(
            body: FileExplorer(
              fs: fs,
              prefs: prefs,
              onFileTap: (_) {},
              onChanged: () {},
            ),
          ),
        );

    testWidgets('expanding a folder persists it and survives a remount',
        (tester) async {
      final prefs = ExplorerPrefs(await SharedPreferences.getInstance());

      await tester.pumpWidget(buildExplorer(prefs));
      await settleFrames(tester);
      expect(find.text('main.py'), findsNothing);

      await tester.tap(find.text('src'));
      await settleFrames(tester);
      expect(find.text('main.py'), findsOneWidget);
      expect(prefs.loadExpanded(), contains('src'),
          reason: 'toggle should persist immediately');

      await tester.pumpWidget(const SizedBox.shrink());
      await settleFrames(tester);
      await tester.pumpWidget(buildExplorer(prefs));
      await settleFrames(tester);
      expect(find.text('main.py'), findsOneWidget,
          reason: 'src should still be expanded after remount');

      await tester.tap(find.text('src'));
      await settleFrames(tester);
      expect(prefs.loadExpanded(), isNot(contains('src')));
    });

    testWidgets('prunes deleted folders from persisted state on load',
        (tester) async {
      final prefs = ExplorerPrefs(await SharedPreferences.getInstance());

      await tester.pumpWidget(buildExplorer(prefs));
      await settleFrames(tester);
      await tester.tap(find.text('src'));
      await settleFrames(tester);
      expect(prefs.loadExpanded(), contains('src'));

      await tester.runAsync(() => fs.delete('src'));

      await tester.pumpWidget(const SizedBox.shrink());
      await settleFrames(tester);
      await tester.pumpWidget(buildExplorer(prefs));
      await settleFrames(tester);

      expect(prefs.loadExpanded(), isNot(contains('src')),
          reason: 'deleted folders should be pruned on mount');
      expect(find.text('main.py'), findsNothing);
    });
  });
}

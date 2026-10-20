import 'package:b_code/core/archive_extractor.dart';
import 'package:b_code/core/constants.dart';
import 'package:b_code/workspace/device_import_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the SAF channel from the test side.
///
/// An unhandled `MethodChannel` never completes in the test harness, so every case that
/// touches the import service has to install a mock rather than rely on there being no
/// plugin.
void mockSaf(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(AppConstants.safChannel),
    handler,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(AppConstants.safChannel),
      null,
    );
  });

  group('formatBytes', () {
    test('scales to a readable unit', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('DeviceImport', () {
    test('a single-file import is one file and is never truncated', () {
      const import = DeviceImport(path: '/a/b.py', files: 1, bytes: 0);
      expect(import.files, 1);
      expect(import.truncated, isFalse);
    });

    test('a capped folder import says so', () {
      const import =
          DeviceImport(path: '/a/b', files: 20000, bytes: 1, truncated: true);
      expect(import.truncated, isTrue);
    });
  });

  group('picking a file', () {
    test('returns the imported path', () async {
      mockSaf((call) async {
        expect(call.method, 'importFile');
        return '/workspace/notes.py';
      });

      final result = await DeviceImportService.instance.pickFile();

      expect(result?.path, '/workspace/notes.py');
      expect(result?.files, 1);
    });

    test('returns null when the user backs out', () async {
      mockSaf((call) async => null);
      expect(await DeviceImportService.instance.pickFile(), isNull);
    });
  });

  group('picking a folder', () {
    test('returns the folder with its file and byte counts', () async {
      mockSaf((call) async {
        expect(call.method, 'importFolder');
        return <String, Object?>{
          'path': '/workspace/my-project',
          'files': 412,
          'bytes': 1048576,
          'truncated': false,
        };
      });

      final result = await DeviceImportService.instance.pickFolder();

      expect(result?.path, '/workspace/my-project');
      expect(result?.files, 412);
      expect(result?.bytes, 1048576);
      expect(result?.truncated, isFalse);
    });

    test('reports a capped import rather than claiming it is complete', () async {
      mockSaf((call) async => <String, Object?>{
            'path': '/workspace/huge',
            'files': 20000,
            'bytes': 536870912,
            'truncated': true,
          });

      final result = await DeviceImportService.instance.pickFolder();

      expect(result?.truncated, isTrue);
    });

    test('returns null when the user backs out', () async {
      mockSaf((call) async => null);
      expect(await DeviceImportService.instance.pickFolder(), isNull);
    });

    test('returns null when the device has no folder picker', () async {
      mockSaf((call) async =>
          throw PlatformException(code: 'NO_PICKER', message: 'no picker'));
      expect(await DeviceImportService.instance.pickFolder(), isNull);
    });

    test('surfaces a real failure instead of swallowing it', () async {
      mockSaf((call) async => throw PlatformException(
          code: 'IMPORT_FAILED', message: 'permission denied'));
      await expectLater(
        DeviceImportService.instance.pickFolder(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('import progress', () {
    test('is broadcast and reaches a listener', () async {
      expect(DeviceImportService.instance.progress.isBroadcast, isTrue);

      final seen = <DeviceImportProgress>[];
      final sub = DeviceImportService.instance.progress.listen(seen.add);
      addTearDown(sub.cancel);

      // The native side pushes these over the same channel. Replaying one through the
      // mock proves the Dart side is listening on the right method name and reads the
      // right fields, which is the part that can silently rot.
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        AppConstants.safChannel,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('importProgress', {'name': 'proj', 'files': 12, 'bytes': 34}),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(seen.single.name, 'proj');
      expect(seen.single.files, 12);
      expect(seen.single.bytes, 34);
    });
  });

  group('what the explorer offers to unpack', () {
    test('archives are offered', () {
      for (final name in [
        'a.zip',
        'a.jar',
        'a.tar',
        'a.tar.gz',
        'a.tgz',
        'a.tar.bz2',
        'A.ZIP',
      ]) {
        expect(ArchiveExtractor.isArchiveName(name), isTrue,
            reason: '$name should be unpackable');
      }
    });

    test('everything else is hidden', () {
      // The action used to sit on every row, so choosing it on a source file produced
      // a decoder error instead of a sensible "that is not an archive".
      for (final name in ['main.dart', 'notes.txt', 'README', 'archive', 'zip']) {
        expect(ArchiveExtractor.isArchiveName(name), isFalse,
            reason: '$name is not an archive');
      }
    });
  });
}

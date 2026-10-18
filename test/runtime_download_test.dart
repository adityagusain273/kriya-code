import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/execution/runtime_catalog.dart';
import 'package:b_code/execution/runtime_download_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient extends http.BaseClient {
  final http.Response Function(Uri url) onGet;
  Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  FakeClient({required this.onGet, required this.onSend});

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      onGet(url);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => onSend(request);
}

void main() {
  group('parsePackagesIndex', () {
    const sample = '''
Package: python
Version: 3.12.7
Architecture: aarch64
Size: 8200000
Filename: pool/main/p/python/python_3.12.7_aarch64.deb

Package: libandroid-support
Version: 28
Architecture: aarch64
Size: 12000
Filename: pool/main/liba/libandroid-support/libandroid-support_28_aarch64.deb

Package: ncurses-ui-libs-static
Version: 6.4
Architecture: all
Size: 5000
Filename: pool/main/n/ncurses/ncurses-ui-libs-static_6.4_all.deb

Package: golang-x86-only
Version: 1.0
Architecture: x86_64
Size: 9000
Filename: pool/main/g/golang/golang_1.0_x86_64.deb
''';

    test('parses package name, filename and size', () {
      final index = parsePackagesIndex(sample, 'aarch64');
      expect(index, containsPair('python', isA<TermuxPackageRef>()));
      final py = index['python']!;
      expect(py.fileName, 'pool/main/p/python/python_3.12.7_aarch64.deb');
      expect(py.sizeBytes, 8200000);
    });

    test('skips foreign-arch packages but keeps arch:all', () {
      final index = parsePackagesIndex(sample, 'aarch64');
      expect(index.containsKey('ncurses-ui-libs-static'), isTrue,
          reason: 'arch: all applies to every architecture');
      expect(index.containsKey('golang-x86-only'), isFalse,
          reason: 'x86_64 packages must be skipped on aarch64');
    });

    test('parsePackageBlock returns null for incomplete blocks', () {
      expect(parsePackageBlock('Package: x\nSize: 1\n', 'aarch64'), isNull);
    });
  });

  group('RuntimeDownloadService', () {
    late FakeClient client;
    late RuntimeDownloadService service;

    const indexBody = '''
Package: python
Architecture: aarch64
Size: 8000000
Filename: pool/main/p/python/python_1.0_aarch64.deb

Package: libandroid-support
Architecture: aarch64
Size: 12000
Filename: pool/main/liba/libandroid-support/libandroid-support_1_aarch64.deb

Package: ncurses
Architecture: aarch64
Size: 300000
Filename: pool/main/n/ncurses/ncurses_1_aarch64.deb

Package: openssl
Architecture: aarch64
Size: 1000000
Filename: pool/main/o/openssl/openssl_1_aarch64.deb

Package: libffi
Architecture: aarch64
Size: 40000
Filename: pool/main/l/libffi/libffi_1_aarch64.deb
''';

    late Directory testDir;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bcode_runtimes_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      client = FakeClient(
        onGet: (_) => http.Response(indexBody, 200),
        onSend: (_) async => http.StreamedResponse(
          Stream.value(List.filled(1000, 65)),
          200,
          contentLength: 1000,
        ),
      );
      service = RuntimeDownloadService(
        client: client,
        prefs: prefs,
        repoBase: 'https://repo.test/apt/termux-main',
        runtimesRootResolver: () async => testDir.path,
        extractor: (_) async => true,
      );
    });

    tearDown(() async {
      if (testDir.existsSync()) await testDir.delete(recursive: true);
    });

    test('download flows resolving→downloading→installed and persists', () async {
      final phases = <RuntimeDownloadPhase>[];
      service.addListener(() {
        final phase = service.stateFor('cpython').phase;
        if (phases.isEmpty || phases.last != phase) phases.add(phase);
      });

      await service.download('cpython');

      expect(phases, contains(RuntimeDownloadPhase.resolving));
      expect(phases, contains(RuntimeDownloadPhase.downloading));
      expect(phases.last, RuntimeDownloadPhase.installed);
      expect(service.isInstalled('cpython'), isTrue);
      expect(
        Directory('${testDir.path}/cpython/pkgs').existsSync(),
        isTrue,
      );
    });

    test('download reports byte progress across all packages', () async {
      RuntimeDownloadState last = const RuntimeDownloadState();
      service.addListener(() => last = service.stateFor('cpython'));

      await service.download('cpython');

      expect(last.totalBytes, 8000000 + 12000 + 300000 + 1000000 + 40000);
      expect(last.receivedBytes, last.totalBytes);
      expect(last.progress, 1.0);
    });

    test('failed package fetch marks runtime failed with error', () async {
      client.onSend = (_) async =>
          http.StreamedResponse(Stream.value([1, 2, 3]), 404);

      await service.download('cpython');

      final state = service.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.failed);
      expect(state.error, isNotNull);
      expect(service.isInstalled('cpython'), isFalse);
    });

    test('remove clears installed marker and state', () async {
      await service.download('cpython');
      await service.remove('cpython');

      expect(service.isInstalled('cpython'), isFalse);
      expect(service.stateFor('cpython').phase, RuntimeDownloadPhase.idle);
    });

    test('catalog covers all local runtime ids used by language packs', () {
      expect(runtimeCatalog.keys, containsAll(['cpython', 'clang', 'openjdk']));
      for (final spec in runtimeCatalog.values) {
        expect(spec.packages, isNotEmpty);
        expect(spec.extensionId, startsWith('bcode.'));
      }
    });
  });
}

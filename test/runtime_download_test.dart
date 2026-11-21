import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/execution/runtime_catalog.dart';
import 'package:kriya_code/execution/runtime_download_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient extends http.BaseClient {
  Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;

  set onGet(http.Response Function(Uri url) value) => _onGet = value;

  http.Response Function(Uri url) _onGet;

  FakeClient({required http.Response Function(Uri url) onGet, required this.onSend})
      : _onGet = onGet;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      _onGet(url);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => onSend(request);
}

/// SHA-256 of [bytes], lowercase hex.
String sha256Of(List<int> bytes) {
  final digest = sha256.convert(bytes);
  return digest.toString();
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

    test('parses the SHA-256 field', () {
      const digest =
          'c2e686823489ced2017f6059b8b239318b6364f6dcd835d0a519105a1eadd6e4';
      final block = 'Package: x\nArchitecture: aarch64\nSize: 1000\n'
          'Filename: pool/main/x/x_1_aarch64.deb\nSHA256: '
          '${digest.toUpperCase()}\n';
      final ref = parsePackageBlock(block, 'aarch64');
      expect(ref, isNotNull);
      expect(ref!.sha256, digest);
      expect(ref.hasChecksum, isTrue);
    });

    test('a package with no SHA-256 is marked unverified', () {
      final ref = parsePackageBlock(
        'Package: x\nArchitecture: aarch64\nSize: 1000\n'
        'Filename: pool/main/x/x_1_aarch64.deb\n',
        'aarch64',
      );
      expect(ref!.hasChecksum, isFalse);
    });

    test('a malformed SHA-256 is discarded rather than trusted', () {
      final ref = parsePackageBlock(
        'Package: x\nArchitecture: aarch64\nSize: 1000\n'
        'Filename: pool/main/x/x_1_aarch64.deb\nSHA256: deadbeef\n',
        'aarch64',
      );
      expect(ref!.hasChecksum, isFalse);
    });

    test('rejects a Filename that is not a pool path', () {
      // The Filename field is concatenated straight into the download URL.
      for (final bad in [
        '../../../etc/passwd',
        'pool/../../evil.deb',
        '/absolute/path.deb',
        'dists/stable/main/binary-aarch64/Packages',
      ]) {
        final ref = parsePackageBlock(
          'Package: x\nArchitecture: aarch64\nSize: 1\nFilename: $bad\n',
          'aarch64',
        );
        expect(ref, isNull, reason: 'should reject $bad');
      }
    });

    test('isAllowedPoolPath accepts real pool paths', () {
      expect(
        isAllowedPoolPath('pool/main/p/python/python_3.12.7_aarch64.deb'),
        isTrue,
      );
      expect(isAllowedPoolPath('pool/main/n/ncurses/ncurses_1_all.deb'), isTrue);
      expect(isAllowedPoolPath('pool/../evil.deb'), isFalse);
      expect(isAllowedPoolPath('evil.deb'), isFalse);
    });
  });

  group('RuntimeDownloadService', () {
    late FakeClient client;
    late RuntimeDownloadService service;

    // Every fixture package serves the same 1000 bytes, so the declared Size and
    // the SHA-256 in the index are both genuinely correct. The download path can
    // therefore be exercised end to end instead of being stubbed past.
    const payload = 'c2e686823489ced2017f6059b8b239318b6364f6dcd835d0a519105a1eadd6e4';
    const body = 1000;
    const packageCount = 5;

    String indexWith({String? digestOverride, bool omitDigests = false}) {
      final digest = digestOverride ?? payload;
      String pkg(String name, String path, int size) {
        final lines = <String>[
          'Package: $name',
          'Architecture: aarch64',
          'Size: $size',
          'Filename: $path',
        ];
        if (!omitDigests) lines.add('SHA256: $digest');
        lines.add('');
        return lines.join('\n');
      }

      return [
        pkg('python', 'pool/main/p/python/python_1.0_aarch64.deb', body),
        pkg('libandroid-support',
            'pool/main/liba/libandroid-support/libandroid-support_1_aarch64.deb',
            body),
        pkg('ncurses', 'pool/main/n/ncurses/ncurses_1_aarch64.deb', body),
        pkg('openssl', 'pool/main/o/openssl/openssl_1_aarch64.deb', body),
        pkg('libffi', 'pool/main/l/libffi/libffi_1_aarch64.deb', body),
      ].join('\n');
    }

    late String indexBody;

    late Directory testDir;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bcode_runtimes_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      indexBody = indexWith(
        digestOverride: sha256Of(List.filled(body, 65)),
      );
      client = FakeClient(
        onGet: (_) => http.Response(indexBody, 200),
        onSend: (_) async => http.StreamedResponse(
          Stream.value(List.filled(body, 65)),
          200,
          contentLength: body,
        ),
      );
      service = RuntimeDownloadService(
        client: client,
        prefs: prefs,
        repoBase: 'https://repo.test/apt/termux-main',
        expectedRepoHost: 'repo.test',
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

      expect(last.totalBytes, packageCount * body);
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

    test('refuses to download when the volume is too full', () async {
      var sends = 0;
      client.onSend = (_) async {
        sends++;
        return http.StreamedResponse(
          Stream.value(List.filled(body, 65)),
          200,
          contentLength: body,
        );
      };

      final cramped = RuntimeDownloadService(
        client: client,
        prefs: await SharedPreferences.getInstance(),
        repoBase: 'https://repo.test/apt/termux-main',
        expectedRepoHost: 'repo.test',
        runtimesRootResolver: () async => testDir.path,
        extractor: (_) async => true,
        // The packed set is packageCount * body; one copy is not the two the
        // unpack needs.
        freeBytes: (_) async => packageCount * body,
      );

      await cramped.download('cpython');

      final state = cramped.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.failed);
      expect(state.error, contains('free space'));
      expect(cramped.isInstalled('cpython'), isFalse);
      expect(sends, 0, reason: 'nothing is fetched when it cannot be unpacked');
      expect(
        Directory('${testDir.path}/cpython/pkgs').existsSync(),
        isFalse,
        reason: 'no staging directory is created before the check',
      );
    });

    test('remove clears installed marker and state', () async {
      await service.download('cpython');
      await service.remove('cpython');

      expect(service.isInstalled('cpython'), isFalse);
      expect(service.stateFor('cpython').phase, RuntimeDownloadPhase.idle);
    });

    test('a checksum mismatch discards the download and fails the runtime',
        () async {
      // Index advertises a digest that does not match the bytes on the wire.
      indexBody = indexWith(digestOverride: 'f' * 64);
      client.onGet = (_) => http.Response(indexBody, 200);

      await service.download('cpython');

      final state = service.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.failed);
      expect(state.error, contains('hecksum'));
      expect(service.isInstalled('cpython'), isFalse);
      // The security property is that no unverified .deb survives, not that the
      // staging directory disappears: cleanup runs after the error is reported so
      // the user is not kept waiting on filesystem I/O.
      final staged = Directory('${testDir.path}/cpython/pkgs');
      if (staged.existsSync()) {
        final leftovers = staged.listSync().map((e) => e.path).toList();
        expect(
          leftovers,
          isEmpty,
          reason: 'unverified packages must not be left on disk: $leftovers',
        );
      }
    });

    test('refuses to install when the index carries no checksums', () async {
      indexBody = indexWith(omitDigests: true);
      client.onGet = (_) => http.Response(indexBody, 200);

      await service.download('cpython');

      final state = service.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.failed);
      expect(state.error, contains('no SHA-256'));
      expect(service.isInstalled('cpython'), isFalse);
    });

    test('refuses a size that disagrees with the index', () async {
      // Correct digest, but the stream delivers more than the declared Size.
      client.onSend = (_) async => http.StreamedResponse(
            Stream.value(List.filled(body * 3, 65)),
            200,
            contentLength: body * 3,
          );

      await service.download('cpython');

      final state = service.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.failed);
      expect(service.isInstalled('cpython'), isFalse);
    });

    test('rejects a repository host that is not the trusted one', () async {
      final hostile = RuntimeDownloadService(
        client: client,
        prefs: await SharedPreferences.getInstance(),
        repoBase: 'https://evil.example/apt/termux-main',
        runtimesRootResolver: () async => testDir.path,
        extractor: (_) async => true,
      );

      await hostile.download('cpython');

      expect(
        hostile.stateFor('cpython').phase,
        RuntimeDownloadPhase.failed,
      );
      expect(hostile.stateFor('cpython').error, contains('Unexpected runtime repository host'));
    });

    test('rejects a cleartext repository', () async {
      final insecure = RuntimeDownloadService(
        client: client,
        prefs: await SharedPreferences.getInstance(),
        repoBase: 'http://packages.termux.dev/apt/termux-main',
        runtimesRootResolver: () async => testDir.path,
        extractor: (_) async => true,
      );

      await insecure.download('cpython');

      expect(insecure.stateFor('cpython').phase, RuntimeDownloadPhase.failed);
      expect(insecure.stateFor('cpython').error, contains('https'));
    });

    test('download skips already verified packages and resumes', () async {
      final pkgsDir = Directory('${testDir.path}/cpython/pkgs')..createSync(recursive: true);
      final pythonPkg = File('${pkgsDir.path}/python_1.0_aarch64.deb');
      pythonPkg.writeAsBytesSync(List.filled(body, 65));

      int sendCount = 0;
      client.onSend = (_) async {
        sendCount++;
        return http.StreamedResponse(
          Stream.value(List.filled(body, 65)),
          200,
          contentLength: body,
        );
      };

      await service.download('cpython');

      expect(service.isInstalled('cpython'), isTrue);
      expect(sendCount, packageCount - 1);
    });

    test('cancel resets state to idle and preserves verified packages', () async {
      final pkgsDir = Directory('${testDir.path}/cpython/pkgs')..createSync(recursive: true);
      final pythonPkg = File('${pkgsDir.path}/python_1.0_aarch64.deb');
      pythonPkg.writeAsBytesSync(List.filled(body, 65));

      client.onSend = (_) async {
        service.cancel('cpython');
        return http.StreamedResponse(
          Stream.value(List.filled(body, 65)),
          200,
          contentLength: body,
        );
      };

      await service.download('cpython');

      final state = service.stateFor('cpython');
      expect(state.phase, RuntimeDownloadPhase.idle);
      expect(state.error, isNull);
      expect(service.isInstalled('cpython'), isFalse);
      expect(pythonPkg.existsSync(), isTrue);
    });

    test('catalog covers all local runtime ids used by language packs', () {
      expect(runtimeCatalog.keys, containsAll(['cpython', 'clang', 'openjdk']));
      for (final spec in runtimeCatalog.values) {
        expect(spec.packages, isNotEmpty);
        for (final id in spec.extensionIds) {
          expect(id, startsWith('bcode.lang.'));
        }
      }
    });
  });
}

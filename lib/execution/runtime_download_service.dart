import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import 'runtime_catalog.dart';

class TermuxPackageRef {
  final String name;
  final String fileName; // relative URL path from repo root
  final int sizeBytes;
  final List<String> depends;

  /// Version exactly as the repository publishes it, shown to the user before they
  /// install so a runtime is a choice rather than a surprise.
  final String? version;

  /// Lowercase hex SHA-256 of the .deb, as published in the apt index.
  ///
  /// Termux `Packages` files always carry this field. The previous parser threw
  /// it away, which is why nothing downstream could verify a download before it
  /// was unpacked and marked executable.
  final String? sha256;

  const TermuxPackageRef({
    required this.name,
    required this.fileName,
    required this.sizeBytes,
    this.depends = const [],
    this.sha256,
    this.version,
  });

  bool get hasChecksum => sha256 != null && sha256!.isNotEmpty;
}

/// Parses a Debian/Termux `Packages` index into package references.
TermuxPackageRef? parsePackageBlock(String block, String arch) {
  String? name;
  String? filename;
  String? size;
  String? architecture;
  String? sha256;
  String? version;
  var depends = const <String>[];
  for (final line in block.split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    switch (key) {
      case 'Package':
        name = value;
      case 'Filename':
        filename = value;
      case 'Size':
        size = value;
      case 'Architecture':
        architecture = value;
      case 'SHA256':
        sha256 = value.toLowerCase();
      case 'Version':
        version = value;
      case 'Depends':
        depends = value
            .split(',')
            .map((d) => d.split('(').first.trim())
            .where((d) => d.isNotEmpty)
            .toList();
    }
  }
  if (name == null || filename == null) return null;
  if (architecture != null && architecture != arch && architecture != 'all') {
    return null;
  }

  // The Filename field is concatenated straight into the download URL, so a
  // hostile index could otherwise point the client at a path on another host or
  // at a traversal sequence. Only real pool paths are accepted.
  if (!isAllowedPoolPath(filename)) return null;

  return TermuxPackageRef(
    name: name,
    fileName: filename,
    sizeBytes: int.tryParse(size ?? '') ?? 0,
    depends: depends,
    sha256: RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256 ?? '')
        ? sha256
        : null,
    version: version,
  );
}

/// A `Filename` from an apt index must be a plain `pool/...deb` path.
final _poolPathPattern = RegExp(r'^pool/[A-Za-z0-9._/+:\-]+\.deb$');

bool isAllowedPoolPath(String value) =>
    !value.contains('..') && _poolPathPattern.hasMatch(value);

Map<String, TermuxPackageRef> parsePackagesIndex(String text, String arch) {
  final out = <String, TermuxPackageRef>{};
  for (final block in text.split('\n\n')) {
    final ref = parsePackageBlock(block, arch);
    if (ref != null) out[ref.name] = ref;
  }
  return out;
}

enum RuntimeDownloadPhase { idle, resolving, downloading, installing, installed, failed }

class RuntimeDownloadState {
  final RuntimeDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final String currentPackage;

  const RuntimeDownloadState({
    this.phase = RuntimeDownloadPhase.idle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.currentPackage = '',
  });

  RuntimeDownloadState copyWith({
    RuntimeDownloadPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    String? currentPackage,
  }) =>
      RuntimeDownloadState(
        phase: phase ?? this.phase,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        error: error ?? this.error,
        currentPackage: currentPackage ?? this.currentPackage,
      );

  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Downloads runtime packages from the Termux apt repository into the app's
/// runtimes directory so code can be executed on-device (offline) once wired
/// to the local exec bridge.
/// A runtime as the repository currently offers it, for display before installing.
class RuntimePreview {
  final String runtimeId;

  /// Version string of the primary package(s), e.g. `3.14.6`.
  final String? version;
  final int packageCount;
  final int sizeBytes;

  const RuntimePreview({
    required this.runtimeId,
    required this.packageCount,
    required this.sizeBytes,
    this.version,
  });
}

class RuntimeDownloadService extends ChangeNotifier {
  final http.Client client;
  final SharedPreferences prefs;
  final String repoBase;
  final String arch;
  final Future<String> Function() runtimesRootResolver;
  final Future<bool> Function(String runtimeId) extractor;

  final _states = <String, RuntimeDownloadState>{};
  final _active = <String>{};
  final _cancelled = <String>{};


  RuntimeDownloadService({
    required this.client,
    required this.prefs,
    this.repoBase = _defaultRepoBase,
    this.expectedRepoHost = 'packages.termux.dev',
    String? arch,
    required this.runtimesRootResolver,
    required this.extractor,
  }) : arch = arch ?? detectRuntimeArch() ?? _fallbackArch;

  /// Falls back to the only ABI Termux still ships a full tree for, so a device
  /// whose ABI cannot be read gets a clear failure at install time rather than a
  /// silent mismatch.
  static const _fallbackArch = 'aarch64';

  /// Repository architecture directory for the device CPU.
  ///
  /// Termux publishes one `binary-<arch>` tree per ABI, and the package names
  /// inside each index are architecture specific, so asking for the wrong one
  /// either resolves nothing or, worse, unpacks binaries the device cannot run.
  /// Hardcoding `aarch64` shipped an editor that worked on modern phones and
  /// failed everywhere else, so the ABI is read from the platform instead.
  ///
  /// Returns null off Android, where there is no repository to talk to.
  static String? detectRuntimeArch() {
    if (!Platform.isAndroid) return null;
    try {
      final abi = Abi.current().toString();
      if (abi.contains('arm64')) return 'aarch64';
      if (abi.contains('arm')) return 'arm';
      if (abi.contains('x86_64')) return 'x86_64';
      if (abi.contains('riscv64')) return 'riscv64';
    } catch (_) {
      // Abi.current() is unavailable on some hosts; fall through to the version
      // string, which embeds the same information.
    }
    final version = Platform.version.toLowerCase();
    if (version.contains('arm64')) return 'aarch64';
    if (version.contains('armv7') || version.contains('armv8l')) return 'arm';
    if (version.contains('x86_64') || version.contains('x64')) return 'x86_64';
    if (version.contains('riscv64')) return 'riscv64';
    return null;
  }

  static const _installedKey = 'runtimes_installed';

  static const _defaultRepoBase = 'https://packages.termux.dev/apt/termux-main';

  /// The repository is the root of trust for arbitrary native code, so a
  /// cleartext or unexpected host must not be silently accepted.
  /// The only repository host this app will fetch runtimes from.
  ///
  /// Exists as a constructor parameter purely so tests can point at a local
  /// fixture server. Production code never overrides it.
  final String expectedRepoHost;

  void _assertTrustedRepo(String repoBase) {
    final uri = Uri.tryParse(repoBase);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('Runtime repository must be an https URL: $repoBase');
    }
    if (uri.host != expectedRepoHost) {
      throw ArgumentError('Unexpected runtime repository host: ${uri.host}');
    }
  }

  RuntimeDownloadState stateFor(String runtimeId) =>
      _states[runtimeId] ??
      RuntimeDownloadState(
        phase: isInstalled(runtimeId)
            ? RuntimeDownloadPhase.installed
            : RuntimeDownloadPhase.idle,
      );

  /// What installing this runtime would fetch, without installing it.
  ///
  /// Shown on the downloads screen so the choice is informed: which version, how
  /// many packages, how much data. The repository index is fetched once and shared
  /// by every runtime on screen rather than per tile.
  Future<RuntimePreview?> inspect(String runtimeId) async {
    final spec = specForRuntime(runtimeId);
    if (spec == null) return null;
    try {
      final refs = await resolvePackages(spec);
      if (refs.isEmpty) return null;
      final versions = <String, String>{};
      for (final ref in refs) {
        final v = ref.version;
        if (v != null && v.isNotEmpty) versions[ref.name] = v;
      }
      // Only the first entry of a spec is the language itself; the rest are its
      // dependencies, and listing their versions reads as noise rather than
      // information ("3.14.6 + 29-1 + 6.6.20260307..." says nothing useful).
      return RuntimePreview(
        runtimeId: runtimeId,
        version: versions[spec.packages.first],
        packageCount: refs.length,
        sizeBytes: refs.fold<int>(0, (sum, r) => sum + r.sizeBytes),
      );
    } catch (_) {
      return null;
    }
  }

  bool isInstalled(String runtimeId) =>
      (prefs.getStringList(_installedKey) ?? const []).contains(runtimeId);

  void _markInstalled(String runtimeId) {
    final list = (prefs.getStringList(_installedKey) ?? const []).toList();
    if (!list.contains(runtimeId)) list.add(runtimeId);
    prefs.setStringList(_installedKey, list);
  }

  void _update(String runtimeId, RuntimeDownloadState state) {
    _states[runtimeId] = state;
    notifyListeners();
  }

  void _fail(String runtimeId, String message) {
    _active.remove(runtimeId);
    _cancelled.remove(runtimeId);
    _update(runtimeId, stateFor(runtimeId).copyWith(
      phase: RuntimeDownloadPhase.failed,
      error: message,
    ));
  }

  /// Resolves the package list from the apt index, expanding transitive
  /// dependencies (Depends fields) breadth-first.
  /// The repository index, fetched once and kept for the life of the process.
  ///
  /// Every runtime on the downloads screen needs it, and it is a few hundred
  /// kilobytes; one request per tile would be both slower and heavier on the
  /// user's data than a single shared copy.
  Map<String, TermuxPackageRef>? _indexCache;

  Future<Map<String, TermuxPackageRef>> _repositoryIndex() async {
    final cached = _indexCache;
    if (cached != null) return cached;
    _assertTrustedRepo(repoBase);
    final uri = Uri.parse('$repoBase/dists/stable/main/binary-$arch/Packages');
    final resp = await client.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw StateError('Package index fetch failed (${resp.statusCode})');
    }
    final index = parsePackagesIndex(resp.body, arch);
    _indexCache = index;
    return index;
  }

  Future<List<TermuxPackageRef>> resolvePackages(RuntimeSpec spec) async {
    final index = await _repositoryIndex();
    final refs = <TermuxPackageRef>[];
    final seen = <String>{};
    final queue = List<String>.from(spec.packages);
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!seen.add(name)) continue;
      final ref = index[name];
      if (ref == null) {
        if (spec.packages.contains(name)) {
          throw StateError('Package "$name" not found in repository index');
        }
        continue;
      }
      refs.add(ref);
      queue.addAll(ref.depends);
    }
    return refs;
  }

  Future<void> download(String runtimeId) async {
    final spec = specForRuntime(runtimeId);
    if (spec == null) {
      _fail(runtimeId, 'Unknown runtime "$runtimeId"');
      return;
    }
    if (_active.contains(runtimeId)) return;
    _active.add(runtimeId);
    try {
      _update(runtimeId, const RuntimeDownloadState(
          phase: RuntimeDownloadPhase.resolving));
      final refs = await resolvePackages(spec);

      // Refuse to install anything we cannot verify. A .deb that reaches the
      // extractor is unpacked into filesDir/runtimes/<id>/bin and marked
      // executable, and the next Run execve's it as the app UID. Without this
      // gate, anyone able to influence bytes on the path -- a hostile mirror, a
      // DNS/CA problem, a hostile Wi-Fi with an installed root CA -- supplies
      // native code that runs with no user-visible prompt.
      final unverifiable =
          refs.where((r) => !r.hasChecksum).map((r) => r.name).toList();
      if (unverifiable.isNotEmpty) {
        throw StateError(
          'Refusing to install: the repository index has no SHA-256 for '
          '${unverifiable.join(", ")}.',
        );
      }

      final total = refs.fold<int>(0, (sum, r) => sum + r.sizeBytes);
      var received = 0;

      final rootDir = Directory(await runtimesRootResolver());
      final pkgsDir = Directory('${rootDir.path}/${spec.runtimeId}/pkgs');
      await pkgsDir.create(recursive: true);

      for (final ref in refs) {
        if (_cancelled.contains(runtimeId)) throw StateError('Cancelled');

        _update(runtimeId, stateFor(runtimeId).copyWith(
          phase: RuntimeDownloadPhase.downloading,
          totalBytes: total,
          receivedBytes: received,
          currentPackage: ref.name,
        ));

        final fileName = ref.fileName.split('/').last;
        final file = File('${pkgsDir.path}/$fileName');
        final requestUri = Uri.parse('$repoBase/${ref.fileName}');
        if (requestUri.host != expectedRepoHost) {
          throw StateError('Refusing cross-host download for ${ref.name}');
        }

        final streamed = http.Request('GET', requestUri);
        final response = await client.send(streamed).timeout(const Duration(minutes: 10));
        if (response.statusCode != 200) {
          if (await file.exists()) await file.delete();
          throw StateError('Download of ${ref.name} failed (${response.statusCode})');
        }

        // Hash while streaming, so nothing unverified is ever fully written.
        // Scoped to this package's stream so concurrent downloads cannot
        // cross-match digests.
        String? actualDigest;
        final digestSink = sha256.startChunkedConversion(
          _DigestCollector((digest) => actualDigest = digest.toString()),
        );
        var fileReceived = 0;
        var cancelled = false;
        var overflowed = false;

        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            if (_cancelled.contains(runtimeId)) {
              cancelled = true;
              break;
            }
            fileReceived += chunk.length;
            if (ref.sizeBytes > 0 && fileReceived > ref.sizeBytes * 1.05) {
              overflowed = true;
              break;
            }
            received += chunk.length;
            digestSink.add(chunk);
            sink.add(chunk);
            _update(runtimeId, stateFor(runtimeId).copyWith(
              receivedBytes: received,
            ));
          }
          await sink.flush();
        } finally {
          await sink.close();
          await sink.flush();
          digestSink.close();
        }

        if (cancelled || overflowed) {
          if (await file.exists()) await file.delete();
          throw StateError(
            overflowed
                ? 'Download of ${ref.name} exceeded the size the index declared'
                : 'Cancelled',
          );
        }

        // Cheap sanity gate before the cryptographic one.
        if (ref.sizeBytes > 0 && fileReceived != ref.sizeBytes) {
          if (await file.exists()) await file.delete();
          throw StateError(
            'Size mismatch for ${ref.name} (expected ${ref.sizeBytes}, got $fileReceived)',
          );
        }

        final actual = actualDigest?.toLowerCase();
        if (actual != ref.sha256!.toLowerCase()) {
          if (await file.exists()) await file.delete();
          throw StateError(
            'Checksum mismatch for ${ref.name}. The download was discarded. '
            'This can mean a corrupted transfer or an intercepted one.',
          );
        }
      }

      _update(runtimeId, stateFor(runtimeId).copyWith(
          phase: RuntimeDownloadPhase.installing));
      
      if (_cancelled.contains(runtimeId)) throw StateError('Cancelled');
      
      final extracted = await extractor(runtimeId);
      if (!extracted) {
        throw StateError('Runtime extraction failed on device');
      }
      final marker = Directory('${rootDir.path}/${spec.runtimeId}');
      if (!marker.existsSync()) await marker.create(recursive: true);
      _markInstalled(runtimeId);
      _active.remove(runtimeId);
      _update(runtimeId, RuntimeDownloadState(
        phase: RuntimeDownloadPhase.installed,
        receivedBytes: total,
        totalBytes: total,
      ));
    } catch (e) {
      // Report first. Doing the cleanup before surfacing the error delayed the
      // user-visible failure behind filesystem I/O.
      _fail(runtimeId, e.toString());

      // Then remove anything already fetched. A partially populated pkgs/
      // directory is not a security problem on its own -- every file is verified
      // before the next download starts -- but leaving hundreds of megabytes
      // behind after a failed or cancelled install is not acceptable.
      //
      // Deliberately not awaited: `download()` is awaited by the UI, and holding
      // it open on filesystem I/O delays the error the user needs to see.
      unawaited(_discardPackages(spec.runtimeId));
    }
  }

  Future<void> _discardPackages(String runtimeId) async {
    try {
      final rootDir = Directory(await runtimesRootResolver());
      final pkgs = Directory('${rootDir.path}/$runtimeId/pkgs');
      if (await pkgs.exists()) {
        await pkgs.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> remove(String runtimeId) async {
    cancel(runtimeId);
    if (_active.contains(runtimeId)) {
      // Small wait to allow cancellation to propagate
      await Future.delayed(const Duration(milliseconds: 500));
    }
    try {
      final rootDir = Directory(await runtimesRootResolver());
      final dir = Directory('${rootDir.path}/$runtimeId');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
    final list = (prefs.getStringList(_installedKey) ?? const []).toList()
      ..remove(runtimeId);
    prefs.setStringList(_installedKey, list);
    _update(runtimeId, const RuntimeDownloadState());
  }

  /// Approximate download size in MB for UI hints (resolved lazily).
  Future<int?> approxSizeMb(RuntimeSpec spec) async {
    try {
      final refs = await resolvePackages(spec);
      final bytes = refs.fold<int>(0, (s, r) => s + r.sizeBytes);
      return (bytes / (1024 * 1024)).ceil();
    } catch (_) {
      return null;
    }
  }

  void cancel(String runtimeId) {
    if (_active.contains(runtimeId)) {
      _cancelled.add(runtimeId);
    }
  }
}

String runtimeDirName(String runtimeId) => '${AppConstants.runtimesDirName}/$runtimeId';

/// A `Sink<Digest>` that hands the final digest to [onDone].
class _DigestCollector implements Sink<Digest> {
  _DigestCollector(this.onDone);

  final void Function(String hex) onDone;
  bool _closed = false;

  @override
  void add(Digest data) {
    if (_closed) throw StateError('Digest sink already closed.');
    onDone(data.toString());
  }

  @override
  void close() => _closed = true;
}

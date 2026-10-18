import 'dart:async';
import 'dart:io';

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

  const TermuxPackageRef({
    required this.name,
    required this.fileName,
    required this.sizeBytes,
    this.depends = const [],
  });
}

/// Parses a Debian/Termux `Packages` index into package references.
TermuxPackageRef? parsePackageBlock(String block, String arch) {
  String? name;
  String? filename;
  String? size;
  String? architecture;
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
  return TermuxPackageRef(
    name: name,
    fileName: filename,
    sizeBytes: int.tryParse(size ?? '') ?? 0,
    depends: depends,
  );
}

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
    this.repoBase = 'https://packages.termux.dev/apt/termux-main',
    this.arch = 'aarch64',
    required this.runtimesRootResolver,
    required this.extractor,
  });

  static const _installedKey = 'runtimes_installed';

  RuntimeDownloadState stateFor(String runtimeId) =>
      _states[runtimeId] ??
      RuntimeDownloadState(
        phase: isInstalled(runtimeId)
            ? RuntimeDownloadPhase.installed
            : RuntimeDownloadPhase.idle,
      );

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
  Future<List<TermuxPackageRef>> resolvePackages(RuntimeSpec spec) async {
    final uri = Uri.parse('$repoBase/dists/stable/main/binary-$arch/Packages');
    final resp = await client.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw StateError('Package index fetch failed (${resp.statusCode})');
    }
    final index = parsePackagesIndex(resp.body, arch);
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
        final file = File('${pkgsDir.path}/${ref.fileName.split('/').last}');
        final streamed = http.Request('GET', Uri.parse('$repoBase/${ref.fileName}'));
        final response = await client.send(streamed).timeout(const Duration(minutes: 10));
        if (response.statusCode != 200) {
          if (await file.exists()) await file.delete();
          throw StateError('Download of ${ref.name} failed (${response.statusCode})');
        }
        final sink = file.openWrite();
        bool cancelled = false;
        await for (final chunk in response.stream) {
          if (_cancelled.contains(runtimeId)) {
            cancelled = true;
            break;
          }
          received += chunk.length;
          sink.add(chunk);
          _update(runtimeId, stateFor(runtimeId).copyWith(
            receivedBytes: received,
          ));
        }
        await sink.flush();
        await sink.close();
        if (cancelled) {
          if (await file.exists()) await file.delete();
          throw StateError('Cancelled');
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
      _fail(runtimeId, e.toString());
    }
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

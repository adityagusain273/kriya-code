import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;

import '../plugins/api/run_config.dart';
import 'exec_events.dart';
import 'local/local_runner.dart';
import 'models.dart';
import 'termux_runner.dart';

class ConsoleLine {
  final String text;
  final bool isStderr;

  const ConsoleLine(this.text, {this.isStderr = false});
}

class RunnerService extends ChangeNotifier {
  final LocalRunner local;

  bool running = false;
  bool _cancelRequested = false;
  String? lastError;
  final List<ConsoleLine> lines = [];

  RunnerService({required this.local});

  static const int _maxLines = 1000;

  String? _runId;
  StreamSubscription<ExecEvent>? _events;
  int _generation = 0;

  // Output arrives in chunks that can split a line, so complete lines are
  // drained and any partial tail waits for the next chunk.
  final _stdout = LineCollector();
  final _stderr = LineCollector();
  bool _sawStdout = false;
  bool _sawStderr = false;

  void _ensureStream() {
    if (_events != null) return;
    ExecEvents.instance.ensureListening();
    _events = ExecEvents.instance.stream.listen(_onEvent);
  }

  void _onEvent(ExecEvent event) {
    if (event.runId != _runId || !running) return;
    final isStderr = event.stream == 'stderr';
    if (isStderr) {
      _sawStderr = true;
    } else {
      _sawStdout = true;
    }
    final collector = isStderr ? _stderr : _stdout;
    for (final line in collector.add(event.data)) {
      _append(line, isStderr: isStderr);
    }
  }

  void _flushPending() {
    for (final line in _stdout.flush()) {
      _append(line);
    }
    for (final line in _stderr.flush()) {
      _append(line, isStderr: true);
    }
  }

  void _append(String text, {bool isStderr = false}) {
    for (final line in text.split('\n')) {
      lines.add(ConsoleLine(line, isStderr: isStderr));
    }
    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    _scheduleNotify();
  }

  // Streaming delivers many chunks; rebuilding once per chunk is enough.
  bool _notifyScheduled = false;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  Future<void> clear() async {
    lines.clear();
    notifyListeners();
  }

  void cancel() {
    if (!running) return;
    _cancelRequested = true;
    // Stop used to only flip a flag in Dart: the native process kept running
    // until its 30 second timeout. Native now holds a runId -> Process map.
    final id = _runId;
    if (id != null) unawaited(local.kill(id));
    running = false;
    notifyListeners();
  }

  Future<void> run({
    required RunRequest request,
    required RunConfig config,
    required String workDir,
  }) async {
    if (running) return;
    running = true;
    _cancelRequested = false;
    lastError = null;
    final generation = ++_generation;
    _runId = 'r${DateTime.now().microsecondsSinceEpoch}';
    _sawStdout = false;
    _sawStderr = false;
    _stdout.clear();
    _stderr.clear();
    _ensureStream();
    await clear();
    notifyListeners();

    try {
      if (config.hasLocal) {
        final runtimeId = config.local!.runtimeId;

        // In-process execution is the primary path. A build that targets SDK 28
        // or lower runs in the legacy SELinux domain, which may spawn the
        // downloaded runtimes directly out of app-private storage, so there is
        // no reason to hand the work to another app.
        final available = await local.hasRuntime(runtimeId);
        if (available) {
          final result = await local.run(
            request: request,
            target: config.local!,
            workDir: workDir,
            runId: _runId,
          );
          // A newer run may have started after Stop, in which case this one's
          // output belongs to nobody.
          if (generation != _generation || _cancelRequested) return;
          _flushPending();
          // Streaming may be unavailable (older install, plugin missing). The
          // summary is the fallback, and the only copy for short runs.
          if (!_sawStdout && result.stdout.isNotEmpty) _append(result.stdout);
          if (!_sawStderr && result.stderr.isNotEmpty) {
            _append(result.stderr, isStderr: true);
          }
          if (!result.success) {
            lastError = 'Process exited with code ${result.exitCode}';
          }
          return;
        }

        // Lazily populate availability so falling back to Termux actually takes
        // effect. Apart from the very first run, this is synchronous from the
        // caller's point of view because the grant dialog has already been
        // answered.
        await TermuxRunner.checkAvailability();
        if (TermuxRunner.isAvailable) {
          final result = await _runViaTermux(request, config.local!, workDir);
          if (generation != _generation || _cancelRequested) return;
          if (result.stdout.isNotEmpty) _append(result.stdout);
          if (result.stderr.isNotEmpty) _append(result.stderr, isStderr: true);
          if (!result.success) {
            lastError = 'Termux exited with code ${result.exitCode}';
          }
          return;
        }

        final termuxInstalled = await TermuxRunner.isInstalled();
        if (termuxInstalled) {
          lastError =
              'Runtime "$runtimeId" is not installed locally.\n'
              'Termux was detected, but RUN_COMMAND permission is not granted.\n'
              'Warning: B Code cannot execute code via Termux without this permission.\n'
              'Allow it in Settings → Termux Integration or Android App Info.';
        } else {
          lastError =
              'Runtime "$runtimeId" is not installed.\n'
              'Install it from Extensions → Downloads,\n'
              'or install Termux from Settings to run with system compilers.';
        }
      } else {
        lastError = 'No local runtime configured for this language.';
      }
    } catch (e) {
      lastError = 'Execution error: $e';
    } finally {
      if (generation == _generation) {
        _runId = null;
        running = false;
        notifyListeners();
      }
    }
  }

  static String? _createWorkspaceTar(String workDir, RunRequest request) {
    try {
      final dir = Directory(workDir);
      if (!dir.existsSync()) return null;

      final archive = Archive();
      int totalBytes = 0;
      const maxIndividualFileBytes = 2 * 1024 * 1024; // 2MB
      const maxArchiveBytes = 1024 * 1024; // 1MB compressed cap

      final relMain = p
          .normalize(p.isAbsolute(request.mainFile)
              ? p.relative(request.mainFile, from: workDir)
              : request.mainFile)
          .replaceAll('\\', '/');
      final cleanMain =
          relMain.startsWith('/') ? relMain.substring(1) : relMain;
      final mainBytes = utf8.encode(request.source);
      archive.addFile(ArchiveFile(cleanMain, mainBytes.length, mainBytes));
      totalBytes += mainBytes.length;

      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        final rel = p
            .normalize(p.relative(entity.path, from: workDir))
            .replaceAll('\\', '/');
        final cleanRel = rel.startsWith('/') ? rel.substring(1) : rel;

        if (cleanRel == cleanMain || cleanRel == p.basename(cleanMain)) {
          continue;
        }

        final parts = cleanRel.split('/');
        if (parts.any((part) =>
            part.startsWith('.') ||
            part == 'node_modules' ||
            part == 'build' ||
            part == '.dart_tool')) {
          continue;
        }

        final stat = entity.statSync();
        if (stat.size > maxIndividualFileBytes) continue;

        final fileBytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(cleanRel, fileBytes.length, fileBytes));
        totalBytes += fileBytes.length;

        if (totalBytes > maxArchiveBytes * 4) return null;
      }

      final tarBytes = TarEncoder().encode(archive);
      final gzipped = gzip.encode(tarBytes);
      if (gzipped.length > maxArchiveBytes) return null;
      return base64Encode(gzipped);
    } catch (_) {
      return null;
    }
  }

  Future<TermuxResult> _runViaTermux(
    RunRequest request,
    dynamic target,
    String workDir,
  ) async {
    final runtimeId = target.runtimeId as String;
    const termuxHome = '/data/data/com.termux/files/home';
    const termuxPrefix = '/data/data/com.termux/files/usr';
    const termuxStagingDir = '$termuxHome/.bcode/cache';
    final needsStaging = !workDir.startsWith(termuxHome);

    final targetWorkDir = needsStaging ? termuxStagingDir : workDir;

    final relMain = p.normalize(
      p.isAbsolute(request.mainFile)
          ? p.relative(request.mainFile, from: workDir)
          : request.mainFile,
    ).replaceAll(r'\', '/');
    final cleanMain = relMain.startsWith('/') ? relMain.substring(1) : relMain;

    final buildArgv = target.buildArgv != null
        ? _substitute(
            (target.buildArgv as List).cast<String>(),
            runtimeId,
            request,
            targetWorkDir,
            projectDir: workDir,
            runtimePrefix: termuxPrefix,
          )
        : null;
    final runArgv = _substitute(
      (target.runArgv as List).cast<String>(),
      runtimeId,
      request,
      targetWorkDir,
      projectDir: workDir,
      runtimePrefix: termuxPrefix,
    );
    runArgv.addAll(request.args);

    if (runArgv.isEmpty) {
      return const TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Empty command',
        exitCode: -1,
      );
    }

    String escape(String s) =>
        '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$')}"';

    if (needsStaging) {
      final tarB64 = _createWorkspaceTar(workDir, request);
      final cmdParts = <String>[
        'export PATH="/data/data/com.termux/files/usr/bin:\$PATH"',
        'mkdir -p $termuxStagingDir',
      ];

      if (tarB64 != null) {
        cmdParts.add(
          'echo \'$tarB64\' | base64 -d | tar -xz -C $termuxStagingDir',
        );
      } else {
        final encodedSource = base64Encode(utf8.encode(request.source));
        cmdParts.add(
          'mkdir -p "\$(dirname "$termuxStagingDir/\$1")" && echo \'$encodedSource\' | base64 -d > $termuxStagingDir/"\$1"',
        );
      }

      cmdParts.add('cd $termuxStagingDir');
      if (buildArgv != null) {
        cmdParts.add(buildArgv.map(escape).join(' '));
      }
      cmdParts.add(runArgv.map(escape).join(' '));

      return TermuxRunner.runCommand(
        command: '$termuxPrefix/bin/bash',
        args: [
          '-c',
          cmdParts.join(' && '),
          '--',
          cleanMain,
        ],
        stdin: request.stdin.isNotEmpty ? request.stdin : null,
        workDir: termuxHome,
      );
    }

    if (buildArgv != null) {
      final cmd =
          '${buildArgv.map(escape).join(" ")} && ${runArgv.map(escape).join(" ")}';
      return TermuxRunner.runCommand(
        command: '$termuxPrefix/bin/bash',
        args: ['-c', cmd],
        stdin: request.stdin.isNotEmpty ? request.stdin : null,
        workDir: workDir,
      );
    }

    return TermuxRunner.runCommand(
      command: runArgv.first,
      args: runArgv.length > 1 ? runArgv.sublist(1) : const [],
      stdin: request.stdin.isNotEmpty ? request.stdin : null,
      workDir: workDir,
    );
  }

  List<String> _substitute(
    List<String> template,
    String runtimeId,
    RunRequest request,
    String workDir, {
    String? projectDir,
    String? runtimePrefix,
  }) {
    final baseDir = projectDir ?? workDir;
    final relPath = p.normalize(
      p.isAbsolute(request.mainFile)
          ? p.relative(request.mainFile, from: baseDir)
          : request.mainFile,
    ).replaceAll(r'\', '/');
    final cleanRel = relPath.startsWith('/') ? relPath.substring(1) : relPath;
    final filePath = p.join(workDir, cleanRel);
    final fileName = p.basename(cleanRel);
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;

    // When delegating to real Termux, binaries live under Termux's own usr
    // prefix (e.g. /data/data/com.termux/files/usr/bin/python3).
    final runtimePath = runtimePrefix ?? '/opt/bcode-runtimes/$runtimeId';

    return template.map((arg) {
      return arg
          .replaceAll('{runtimeDir}', runtimePath)
          .replaceAll('{runtimePath}', runtimePath)
          .replaceAll('{outDir}', workDir)
          .replaceAll('{file}', filePath)
          .replaceAll('{dir}', workDir)
          .replaceAll('{name}', baseName);
    }).toList();
  }
}

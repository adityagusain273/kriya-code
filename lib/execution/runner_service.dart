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
import 'workload_preflight.dart';

class ConsoleLine {
  final String text;
  final bool isStderr;
  final bool isInput;

  const ConsoleLine(this.text, {this.isStderr = false, this.isInput = false});
}

class RunnerService extends ChangeNotifier {
  final LocalRunner local;

  bool running = false;
  bool _cancelRequested = false;
  String? lastError;
  final List<ConsoleLine> lines = [];

  RunnerService({required this.local}) {
    _ensureStream();
  }

  static const int _maxLines = 1000;

  String? _runId;
  StreamSubscription<ExecEvent>? _events;
  int _generation = 0;

  bool _sawStdout = false;
  bool _sawStderr = false;
  bool _lastLineComplete = true;
  bool _lastLineIsStderr = false;

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
    _appendChunk(event.data, isStderr: isStderr);
  }

  void _flushPending() {
    _lastLineComplete = true;
  }

  void _appendChunk(String chunk, {bool isStderr = false}) {
    final sanitized = chunk.replaceAll('\r', '');
    if (sanitized.isEmpty) return;

    final parts = sanitized.split('\n');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isFirst = i == 0;
      final isLast = i == parts.length - 1;

      if (isFirst && !_lastLineComplete && lines.isNotEmpty && _lastLineIsStderr == isStderr) {
        final prev = lines.last;
        lines[lines.length - 1] = ConsoleLine(
          prev.text + part,
          isStderr: prev.isStderr,
          isInput: prev.isInput,
        );
      } else if (!isLast || part.isNotEmpty) {
        lines.add(ConsoleLine(part, isStderr: isStderr));
      }
    }

    _lastLineComplete = sanitized.endsWith('\n');
    _lastLineIsStderr = isStderr;

    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    _scheduleNotify();
  }

  void _append(String text, {bool isStderr = false, bool isInput = false}) {
    for (final line in text.split('\n')) {
      lines.add(ConsoleLine(line, isStderr: isStderr, isInput: isInput));
    }
    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    _lastLineComplete = true;
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

  void sendStdin(String input) {
    if (!running || _runId == null) return;
    unawaited(local.sendStdin(_runId!, input));
    _lastLineComplete = true;
    _append('> $input', isInput: true);
    _lastLineComplete = true;
  }

  @visibleForTesting
  void setRunningForTesting(bool isRunning, {String? runId}) {
    running = isRunning;
    _runId = runId;
    notifyListeners();
  }

  @visibleForTesting
  void appendChunkForTesting(String chunk, {bool isStderr = false}) {
    _appendChunk(chunk, isStderr: isStderr);
  }

  Future<void> clear() async {
    lines.clear();
    _lastLineComplete = true;
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
    _lastLineComplete = true;
    _sawStdout = false;
    _sawStderr = false;
    _ensureStream();
    await clear();
    notifyListeners();

    // Advisory, not a gate: a framework project or an install step runs, but
    // the user is told it is competing with the editor for memory before it
    // does. Single-file scripts never reach this branch.
    final workload = WorkloadPreflight.fromDirectory(
      Directory(workDir),
      command: [
        ...(config.local?.buildArgv ?? const <String>[]),
        ...(config.local?.runArgv ?? const <String>[]),
      ].join(' '),
    );
    if (workload.prefersCloud) _append(workload.notice);

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
            // Local execution failed (e.g. clang -cc1 fork issue or missing sysroot headers).
            // Fall back to Termux if available.
            await TermuxRunner.checkAvailability();
            if (TermuxRunner.isAvailable) {
              final termuxResult =
                  await _runViaTermux(request, config.local!, workDir);
              if (generation != _generation || _cancelRequested) return;
              if (termuxResult.stdout.isNotEmpty) _append(termuxResult.stdout);
              if (termuxResult.stderr.isNotEmpty) {
                _append(termuxResult.stderr, isStderr: true);
              }
              if (!termuxResult.success) {
                lastError = 'Termux exited with code ${termuxResult.exitCode}';
              }
              return;
            }
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
              'Warning: Kriya cannot execute code via Termux without this permission.\n'
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

      // A web project is mostly source and a lockfile; node_modules is pruned
      // rather than copied, and keeping it out of the walk is what makes the
      // sync take seconds instead of minutes.
      final hasPackageJson = File(p.join(workDir, 'package.json')).existsSync();
      final maxIndividualFileBytes = hasPackageJson ? 8 * 1024 * 1024 : 2 * 1024 * 1024;
      final maxArchiveBytes = hasPackageJson ? 8 * 1024 * 1024 : 1024 * 1024;
      final maxRawBytes = hasPackageJson ? 32 * 1024 * 1024 : maxArchiveBytes * 4;

      final archive = Archive();
      int totalBytes = 0;

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

      for (final entity in _sourceFiles(dir)) {
        final rel = p
            .normalize(p.relative(entity.path, from: workDir))
            .replaceAll('\\', '/');
        final cleanRel = rel.startsWith('/') ? rel.substring(1) : rel;

        if (cleanRel == cleanMain || cleanRel == p.basename(cleanMain)) {
          continue;
        }

        final stat = entity.statSync();
        if (stat.size > maxIndividualFileBytes) continue;

        final fileBytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(cleanRel, fileBytes.length, fileBytes));
        totalBytes += fileBytes.length;

        if (totalBytes > maxRawBytes) return null;
      }

      final tarBytes = TarEncoder().encode(archive);
      final gzipped = gzip.encode(tarBytes);
      if (gzipped.length > maxArchiveBytes) return null;
      return base64Encode(gzipped);
    } catch (_) {
      return null;
    }
  }

  /// Filesystem-safe, stable per-project staging folder name.
  ///
  /// Only cache reuse depends on the hash staying the same; a change just
  /// re-syncs the sources.
  static String _stagingSlug(String workDir) {
    final base = p.basename(workDir).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final clean = base.isEmpty ? 'project' : base;
    return '$clean-${workDir.hashCode.toRadixString(16)}';
  }

  /// Source files under [dir], pruning whole dependency and build trees.
  static const _prunedDirs = {'node_modules', 'build', 'out', '.dart_tool'};

  static List<File> _sourceFiles(Directory dir) {
    final files = <File>[];
    final queue = <Directory>[dir];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final entity in current.listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          if (_prunedDirs.contains(name)) continue;
          queue.add(entity);
        } else if (entity is File) {
          files.add(entity);
        }
      }
    }
    return files;
  }

  Future<TermuxResult> _runViaTermux(
    RunRequest request,
    dynamic target,
    String workDir,
  ) async {
    final runtimeId = target.runtimeId as String;
    const termuxHome = '/data/data/com.termux/files/home';
    const termuxPrefix = '/data/data/com.termux/files/usr';
    // One cache dir per project. Sharing a single staging dir meant the
    // node_modules left behind by project A was picked up by project B, whose
    // package.json describes different dependencies.
    final termuxStagingDir = '$termuxHome/.bcode/cache/${_stagingSlug(workDir)}';
    final needsStaging = !workDir.startsWith(termuxHome);
    final hasPackageJson = File(p.join(workDir, 'package.json')).existsSync();

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
      } else if (hasPackageJson) {
        // Falling back to "write the entry file only" produced a directory with
        // no package.json, so npm failed with a misleading ENOENT. Say what is
        // actually wrong instead.
        return const TermuxResult(
          success: false,
          stdout: '',
          stderr: 'Cannot sync this web project to Termux: the source is larger '
              'than the transfer limit (8 MB compressed / 32 MB raw).\n'
              'node_modules is not copied — it stays in Termux between runs.\n'
              'Move large assets out of the project, or run it from Termux itself.',
          exitCode: -1,
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

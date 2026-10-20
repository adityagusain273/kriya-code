import 'package:flutter/foundation.dart';

import '../plugins/api/run_config.dart';
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

  void _append(String text, {bool isStderr = false}) {
    for (final line in text.split('\n')) {
      lines.add(ConsoleLine(line, isStderr: isStderr));
    }
    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    lines.clear();
    notifyListeners();
  }

  void cancel() {
    if (!running) return;
    _cancelRequested = true;
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
              request: request, target: config.local!, workDir: workDir);
          if (_cancelRequested) return;
          if (result.stdout.isNotEmpty) _append(result.stdout);
          if (result.stderr.isNotEmpty) _append(result.stderr, isStderr: true);
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
          if (_cancelRequested) return;
          if (result.stdout.isNotEmpty) _append(result.stdout);
          if (result.stderr.isNotEmpty) _append(result.stderr, isStderr: true);
          if (!result.success) {
            lastError = 'Termux exited with code ${result.exitCode}';
          }
          return;
        }

        lastError =
            'Runtime "$runtimeId" is not installed.\n'
            'Install it from Extensions → Downloads,\n'
            'or connect Termux from Settings.';
      } else {
        lastError = 'No local runtime configured for this language.';
      }
    } catch (e) {
      lastError = 'Execution error: $e';
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<TermuxResult> _runViaTermux(
    RunRequest request,
    dynamic target,
    String workDir,
  ) async {
    final runtimeId = target.runtimeId;
    final argv = <String>[];
    if (target.buildArgv != null) {
      argv.addAll(_substitute(target.buildArgv, runtimeId, request, workDir,
          runtimePrefix: '/data/data/com.termux/files/usr'));
    }
    argv.addAll(_substitute(target.runArgv, runtimeId, request, workDir,
        runtimePrefix: '/data/data/com.termux/files/usr'));
    argv.addAll(request.args);

    if (argv.isEmpty) {
      return const TermuxResult(
        success: false, stdout: '', stderr: 'Empty command', exitCode: -1);
    }

    final command = argv.first;
    final args = argv.length > 1 ? argv.sublist(1) : <String>[];

    return TermuxRunner.runCommand(
      command: command,
      args: args,
      workDir: workDir,
    );
  }

  List<String> _substitute(
    List<String> template,
    String runtimeId,
    RunRequest request,
    String workDir, {
    String? runtimePrefix,
  }) {
    final filePath = '$workDir/${request.mainFile}';
    final fileName = request.mainFile.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;

    // When delegating to real Termux, binaries live under Termux's own usr
    // prefix (e.g. /data/data/com.termux/files/usr/bin/python3).
    final runtimePath = runtimePrefix ?? '/opt/bcode-runtimes/$runtimeId';

    // Every token is substituted into a single argv element. The old `{args}`
    // token joined the user's arguments with spaces into one slot, so `"a b"`
    // arrived as a single argument and any target template using it would be an
    // injection point the moment the argv reached a shell. `request.args` is now
    // appended as individual arguments by the caller, matching LocalRunner.
    return template.map((arg) {
      return arg
          .replaceAll('{runtimeDir}', runtimePath)
          .replaceAll('{runtimePath}', runtimePath)
          .replaceAll('{file}', filePath)
          .replaceAll('{dir}', filePath.substring(0, filePath.lastIndexOf('/')))
          .replaceAll('{name}', baseName);
    }).toList();
  }
}

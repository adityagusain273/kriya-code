import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../plugins/api/run_config.dart';
import '../models.dart';

class LocalRunner {
  static const _channel = MethodChannel(AppConstants.execChannel);

  Future<bool> hasRuntime(String runtimeId) async {
    try {
      return await _channel.invokeMethod<bool>('hasRuntime', {'runtimeId': runtimeId}) ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> runtimeRoot() async {
    try {
      return await _channel.invokeMethod<String>('runtimesDir');
    } catch (_) {
      return null;
    }
  }

  Future<bool> extractRuntime(String runtimeId) async {
    try {
      return await _channel
              .invokeMethod<bool>('extractRuntime', {'runtimeId': runtimeId}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<RunResult> run({
    required RunRequest request,
    required LocalTarget target,
    required String workDir,
  }) async {
    final runtimeDir = await runtimeRoot();
    if (runtimeDir == null) {
      return RunResult.failure('Local runtimes not available');
    }
    final sw = Stopwatch()..start();
    try {
      final runtimePath = p.join(runtimeDir, target.runtimeId);
      String buildStdout = '';
      String buildStderr = '';

      if (target.buildArgv != null && target.buildArgv!.isNotEmpty) {
        final buildArgv = _substitute(target.buildArgv!, runtimeDir, runtimePath, request, workDir);
        final buildRaw = await _channel
            .invokeMethod<Map<Object?, Object?>>('exec', {
              'argv': buildArgv,
              'cwd': workDir,
              'env': target.env,
              'timeoutMs': 30000,
            })
            .timeout(const Duration(minutes: 2));
        final buildResult = buildRaw?.cast<String, Object?>() ?? {};
        buildStdout = (buildResult['stdout'] as String?) ?? '';
        buildStderr = (buildResult['stderr'] as String?) ?? '';
        
        if (buildResult['success'] != true) {
            sw.stop();
            return RunResult(
                success: false,
                stdout: buildStdout,
                stderr: buildStderr,
                exitCode: (buildResult['exitCode'] as num?)?.toInt() ?? -1,
                mode: ExecutionMode.local,
                durationMs: sw.elapsedMilliseconds,
            );
        }
      }

      final runArgv = _substitute(target.runArgv, runtimeDir, runtimePath, request, workDir);
      runArgv.addAll(request.args);

      final runRaw = await _channel
          .invokeMethod<Map<Object?, Object?>>('exec', {
            'argv': runArgv,
            'cwd': workDir,
            'env': target.env,
            'timeoutMs': 30000,
          })
          .timeout(const Duration(minutes: 2));
      final runResult = runRaw?.cast<String, Object?>() ?? {};
      sw.stop();

      final runStdout = (runResult['stdout'] as String?) ?? '';
      final runStderr = (runResult['stderr'] as String?) ?? '';

      return RunResult(
        success: runResult['success'] == true,
        stdout: [buildStdout, runStdout].where((s) => s.isNotEmpty).join('\n'),
        stderr: [buildStderr, runStderr].where((s) => s.isNotEmpty).join('\n'),
        exitCode: (runResult['exitCode'] as num?)?.toInt() ?? -1,
        mode: ExecutionMode.local,
        durationMs: sw.elapsedMilliseconds,
      );
    } on MissingPluginException {
      return RunResult.failure('Local execution not supported on this platform');
    } catch (e) {
      return RunResult.failure('Local execution failed: $e');
    }
  }

  List<String> _substitute(
    List<String> template,
    String runtimeDir,
    String runtimePath,
    RunRequest request,
    String workDir,
  ) {
    final filePath = p.join(workDir, request.mainFile);
    final fileName = p.basename(filePath);
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    return template.map((arg) {
      return arg
          .replaceAll('{runtimeDir}', runtimeDir)
          .replaceAll('{runtimePath}', runtimePath)
          .replaceAll('{file}', filePath)
          .replaceAll('{dir}', p.dirname(filePath))
          .replaceAll('{name}', baseName);
    }).toList();
  }
}

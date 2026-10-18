import 'package:flutter/services.dart';

import '../core/constants.dart';

class TermuxRunner {
  static const _channel = MethodChannel(AppConstants.termuxChannel);

  static bool _available = false;

  static bool get isAvailable => _available;

  static Future<bool> checkAvailability() async {
    try {
      final installed = await _channel.invokeMethod<bool>('isInstalled') ?? false;
      if (!installed) {
        _available = false;
        return false;
      }
      final allowed = await _channel.invokeMethod<bool>('isAllowed') ?? false;
      _available = allowed;
      return allowed;
    } on MissingPluginException {
      _available = false;
      return false;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  static Future<bool> isInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<TermuxResult> runCommand({
    required String command,
    List<String> args = const [],
    String? stdin,
    String? workDir,
  }) async {
    if (!_available) {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux is not available',
        exitCode: -1,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('runCommand', {
        'command': command,
        'args': args,
        'stdin': stdin,
        'workDir': workDir,
        'useResult': false,
      });
      sw.stop();
      final result = raw?.cast<String, Object?>() ?? {};
      return TermuxResult(
        success: result['success'] == true,
        stdout: (result['stdout'] as String?) ?? '',
        stderr: (result['stderr'] as String?) ?? '',
        exitCode: (result['exitCode'] as num?)?.toInt() ?? -1,
        durationMs: sw.elapsedMilliseconds,
      );
    } on MissingPluginException {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux plugin not available',
        exitCode: -1,
      );
    } catch (e) {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux error: $e',
        exitCode: -1,
      );
    }
  }

  static Future<TermuxResult> runScript({
    required String script,
    String? workDir,
  }) async {
    if (!_available) {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux is not available',
        exitCode: -1,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('runScript', {
        'script': script,
        'workDir': workDir,
        'useResult': false,
      });
      sw.stop();
      final result = raw?.cast<String, Object?>() ?? {};
      return TermuxResult(
        success: result['success'] == true,
        stdout: (result['stdout'] as String?) ?? '',
        stderr: (result['stderr'] as String?) ?? '',
        exitCode: (result['exitCode'] as num?)?.toInt() ?? -1,
        durationMs: sw.elapsedMilliseconds,
      );
    } on MissingPluginException {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux plugin not available',
        exitCode: -1,
      );
    } catch (e) {
      return TermuxResult(
        success: false,
        stdout: '',
        stderr: 'Termux error: $e',
        exitCode: -1,
      );
    }
  }
}

class TermuxResult {
  final bool success;
  final String stdout;
  final String stderr;
  final int exitCode;
  final int durationMs;

  const TermuxResult({
    required this.success,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.durationMs = 0,
  });
}

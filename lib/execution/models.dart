enum ExecutionMode { local }

class RunRequest {
  final String mainFile;
  final String source;
  final String stdin;
  final List<String> args;

  const RunRequest({
    required this.mainFile,
    required this.source,
    this.stdin = '',
    this.args = const [],
  });
}

class RunResult {
  final bool success;
  final String stdout;
  final String stderr;
  final int exitCode;
  final ExecutionMode mode;
  final int durationMs;
  final String? error;

  const RunResult({
    required this.success,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.mode,
    required this.durationMs,
    this.error,
  });

  factory RunResult.failure(String message) => RunResult(
        success: false,
        stdout: '',
        stderr: message,
        exitCode: -1,
        mode: ExecutionMode.local,
        durationMs: 0,
        error: message,
      );
}

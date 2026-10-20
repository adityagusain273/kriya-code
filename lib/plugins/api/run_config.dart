/// How a program for one language is started on the device.
///
/// Two shapes exist: `local` runs through a runtime installed under the app's own
/// storage, which is the normal case. Nothing here is interpreted by a shell, so a
/// command is an argv list and cannot contain shell operators such as `&&`; a
/// sequence of steps is expressed with [LocalTarget.buildArgv] followed by
/// [LocalTarget.runArgv], which the runner executes as two separate processes.
library;

export '../../editor/highlighting/language_pack.dart' show IndentRules;

/// A runtime from the on-demand catalogue, and the argv to use it.
class LocalTarget {
  /// Runtime id as declared in the runtime catalogue, e.g. `cpython`.
  final String runtimeId;

  /// Compiled first, when the language needs a build step. Optional.
  ///
  /// Output should be written to `{outDir}`, which is app-private: the workspace may
  /// be on the `noexec` shared volume, where a freshly built binary cannot be
  /// started.
  final List<String>? buildArgv;

  /// The program to run once any build step has succeeded.
  final List<String> runArgv;

  final Map<String, String> env;

  const LocalTarget({
    required this.runtimeId,
    required this.runArgv,
    this.buildArgv,
    this.env = const {},
  });
}

class RunConfig {
  final LocalTarget? local;

  const RunConfig({
    this.local,
  });

  bool get hasLocal => local != null;
}

class LocalTarget {
  final String runtimeId;
  final List<String>? buildArgv;
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

class IndentRules {
  final int indentWidth;
  final bool insertSpaces;
  final List<String> blockOpeners;
  final List<String> blockClosers;

  const IndentRules({
    this.indentWidth = 4,
    this.insertSpaces = true,
    this.blockOpeners = const [],
    this.blockClosers = const [],
  });
}

import 'package:highlight/highlight_core.dart';

import 'run_config.dart';

class LanguageContribution {
  final String id;
  final String name;
  final List<String> fileExtensions;
  final Mode grammar;
  final IndentRules indentRules;
  final RunConfig runConfig;

  const LanguageContribution({
    required this.id,
    required this.name,
    required this.fileExtensions,
    required this.grammar,
    this.indentRules = const IndentRules(),
    required this.runConfig,
  });

  bool matchesFile(String fileName) {
    final lower = fileName.toLowerCase();
    return fileExtensions.any((ext) => lower.endsWith('.$ext'));
  }
}

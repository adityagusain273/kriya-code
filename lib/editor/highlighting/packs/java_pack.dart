import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/java.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class JavaPack implements LanguagePack {
  @override
  String get id => 'java';

  @override
  String get displayName => 'Java';

  @override
  List<String> get fileExtensions => ['java'];

  @override
  Mode get grammar => java;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'openjdk',
          runArgv: ['{runtimePath}/bin/javac', '{file}', '&&', '{runtimePath}/bin/java', '{className}'],
        ),
      );
}

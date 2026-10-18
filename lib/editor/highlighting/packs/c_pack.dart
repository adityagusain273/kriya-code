import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/cpp.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class CPack implements LanguagePack {
  @override
  String get id => 'c';

  @override
  String get displayName => 'C';

  @override
  List<String> get fileExtensions => ['c', 'h'];

  @override
  Mode get grammar => cpp;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'clang',
          runArgv: ['{runtimePath}/bin/gcc', '{file}', '-o', '{file}.out', '&&', '{file}.out'],
        ),
      );
}

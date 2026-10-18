import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/typescript.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class TypeScriptPack implements LanguagePack {
  @override
  String get id => 'typescript';

  @override
  String get displayName => 'TypeScript';

  @override
  List<String> get fileExtensions => ['ts', 'tsx'];

  @override
  Mode get grammar => typescript;

  @override
  IndentRules get indentRules => const IndentRules(
        indentWidth: 2,
        blockOpeners: ['{', '[', '('],
        blockClosers: ['}', ')', ']'],
      );

  @override
  RunConfig get runConfig => const RunConfig();
}

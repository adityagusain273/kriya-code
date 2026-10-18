import 'package:highlight/languages/typescript.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class TypescriptExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'typescript',
    name: 'TypeScript',
    fileExtensions: ['ts', 'tsx'],
    grammar: typescript,
    indentRules: const IndentRules(
      indentWidth: 2,
      blockOpeners: ['{', '[', '('],
      blockClosers: ['}', ')', ']'],
    ),
    runConfig: const RunConfig(),
  );

  @override
  String get id => 'bcode.lang.typescript';

  @override
  String get name => 'TypeScript Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

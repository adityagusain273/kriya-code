import 'package:highlight/languages/javascript.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class JavascriptExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'javascript',
    name: 'JavaScript',
    fileExtensions: ['js', 'mjs', 'cjs'],
    grammar: javascript,
    indentRules: const IndentRules(
      indentWidth: 2,
      blockOpeners: ['{', '[', '('],
      blockClosers: ['}', ')', ']'],
    ),
    runConfig: const RunConfig(
      local: LocalTarget(
        runtimeId: 'nodejs',
        runArgv: ['{runtimePath}/bin/node', '{file}'],
      ),
    ),
  );

  @override
  String get id => 'bcode.lang.javascript';

  @override
  String get name => 'JavaScript Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

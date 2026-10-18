import 'package:highlight/languages/python.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class PythonExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'python',
    name: 'Python',
    fileExtensions: ['py', 'pyw'],
    grammar: python,
    indentRules: const IndentRules(indentWidth: 4, blockOpeners: [':']),
    runConfig: const RunConfig(
      local: LocalTarget(
        runtimeId: 'cpython',
        runArgv: ['{runtimePath}/bin/python3', '{file}'],
      ),
    ),
  );

  @override
  String get id => 'bcode.lang.python';

  @override
  String get name => 'Python Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

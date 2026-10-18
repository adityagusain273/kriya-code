import 'package:highlight/languages/java.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class JavaExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'java',
    name: 'Java',
    fileExtensions: ['java'],
    grammar: java,
    indentRules: const IndentRules(
      indentWidth: 4,
      blockOpeners: ['{'],
      blockClosers: ['}'],
    ),
    runConfig: const RunConfig(
      local: LocalTarget(
        runtimeId: 'openjdk',
        buildArgv: ['{runtimePath}/bin/javac', '{file}'],
        runArgv: ['{runtimePath}/bin/java', '-cp', '{dir}', '{name}'],
      ),
    ),
  );

  @override
  String get id => 'bcode.lang.java';

  @override
  String get name => 'Java Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

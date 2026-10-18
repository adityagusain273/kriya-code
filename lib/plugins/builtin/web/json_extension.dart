import 'package:highlight/languages/json.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class JsonExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'json',
    name: 'JSON',
    fileExtensions: ['json'],
    grammar: json,
    indentRules: const IndentRules(
      indentWidth: 2,
      blockOpeners: ['{', '['],
      blockClosers: ['}', ']'],
    ),
    runConfig: const RunConfig(),
  );

  @override
  String get id => 'bcode.lang.json';

  @override
  String get name => 'JSON Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

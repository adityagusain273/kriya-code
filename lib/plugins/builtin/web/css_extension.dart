import 'package:highlight/languages/css.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class CssExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'css',
    name: 'CSS',
    fileExtensions: ['css'],
    grammar: css,
    indentRules: const IndentRules(
      indentWidth: 2,
      blockOpeners: ['{'],
      blockClosers: ['}'],
    ),
    runConfig: const RunConfig(),
  );

  @override
  String get id => 'bcode.lang.css';

  @override
  String get name => 'CSS Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

import 'package:highlight/languages/xml.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class HtmlExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'html',
    name: 'HTML',
    fileExtensions: ['html', 'htm'],
    grammar: xml,
    indentRules: const IndentRules(indentWidth: 2),
    runConfig: const RunConfig(),
  );

  @override
  String get id => 'bcode.lang.html';

  @override
  String get name => 'HTML Language Pack';

  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
  }

  @override
  Future<void> deactivate() async {}
}

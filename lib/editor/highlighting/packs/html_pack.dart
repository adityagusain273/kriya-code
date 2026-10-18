import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/xml.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class HtmlPack implements LanguagePack {
  @override
  String get id => 'html';

  @override
  String get displayName => 'HTML';

  @override
  List<String> get fileExtensions => ['html', 'htm'];

  @override
  Mode get grammar => xml;

  @override
  IndentRules get indentRules => const IndentRules(indentWidth: 2);

  @override
  RunConfig get runConfig => const RunConfig();
}

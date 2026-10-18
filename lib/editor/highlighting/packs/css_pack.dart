import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/css.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class CssPack implements LanguagePack {
  @override
  String get id => 'css';

  @override
  String get displayName => 'CSS';

  @override
  List<String> get fileExtensions => ['css'];

  @override
  Mode get grammar => css;

  @override
  IndentRules get indentRules => const IndentRules(indentWidth: 2);

  @override
  RunConfig get runConfig => const RunConfig();
}

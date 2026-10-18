import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/json.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class JsonPack implements LanguagePack {
  @override
  String get id => 'json';

  @override
  String get displayName => 'JSON';

  @override
  List<String> get fileExtensions => ['json'];

  @override
  Mode get grammar => json;

  @override
  IndentRules get indentRules => const IndentRules(indentWidth: 2);

  @override
  RunConfig get runConfig => const RunConfig();
}

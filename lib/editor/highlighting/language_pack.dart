import 'package:highlight/highlight_core.dart';

import '../../plugins/api/run_config.dart';

abstract class LanguagePack {
  String get id;
  String get displayName;
  List<String> get fileExtensions;
  Mode get grammar;
  IndentRules get indentRules;
  RunConfig get runConfig;
}

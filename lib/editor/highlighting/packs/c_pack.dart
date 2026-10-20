import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/cpp.dart';

import '../language_pack.dart';

class CPack implements LanguagePack {
  @override
  String get id => 'c';

  @override
  String get displayName => 'C';

  @override
  List<String> get fileExtensions => ['c', 'h'];

  @override
  Mode get grammar => cpp;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{']);
}

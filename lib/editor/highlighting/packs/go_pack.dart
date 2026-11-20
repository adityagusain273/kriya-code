import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/go.dart';

import '../language_pack.dart';

class GoPack implements LanguagePack {
  @override
  String get id => 'go';

  @override
  String get displayName => 'Go';

  @override
  List<String> get fileExtensions => ['go'];

  @override
  Mode get grammar => go;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, insertSpaces: false, blockOpeners: ['{']);
}

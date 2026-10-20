import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/javascript.dart';

import '../language_pack.dart';

class JavascriptPack implements LanguagePack {
  @override
  String get id => 'javascript';

  @override
  String get displayName => 'JavaScript';

  @override
  List<String> get fileExtensions => ['js', 'mjs', 'cjs'];

  @override
  Mode get grammar => javascript;

  @override
  IndentRules get indentRules => const IndentRules(
        indentWidth: 2,
        blockOpeners: ['{', '[', '('],
        blockClosers: ['}', ')', ']'],
      );
}

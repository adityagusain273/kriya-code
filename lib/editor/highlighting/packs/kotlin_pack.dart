import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/kotlin.dart';

import '../language_pack.dart';

class KotlinPack implements LanguagePack {
  @override
  String get id => 'kotlin';

  @override
  String get displayName => 'Kotlin';

  @override
  List<String> get fileExtensions => ['kt', 'kts'];

  @override
  Mode get grammar => kotlin;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{']);
}

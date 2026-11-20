import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/rust.dart';

import '../language_pack.dart';

class RustPack implements LanguagePack {
  @override
  String get id => 'rust';

  @override
  String get displayName => 'Rust';

  @override
  List<String> get fileExtensions => ['rs'];

  @override
  Mode get grammar => rust;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{']);
}

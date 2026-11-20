import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/ruby.dart';

import '../language_pack.dart';

class RubyPack implements LanguagePack {
  @override
  String get id => 'ruby';

  @override
  String get displayName => 'Ruby';

  @override
  List<String> get fileExtensions => ['rb', 'rake', 'gemspec'];

  @override
  Mode get grammar => ruby;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: [
        'do',
        '{',
        'class',
        'module',
        'def',
        'if',
        'unless',
        'case',
        'while',
        'until',
        'for',
        'begin',
      ]);
}

import 'package:highlight/highlight_core.dart';

/// Grammar and indentation for one language.
///
/// Deliberately says nothing about how to run it. Execution lives with the language
/// extensions in `lib/plugins/builtin/`, and a second copy of the run command here
/// was how the app ended up with two answers for "how do I run C" — one of them
/// passing a literal `&&` as an argument, which cannot work when there is no shell
/// involved.
abstract class LanguagePack {
  String get id;
  String get displayName;
  List<String> get fileExtensions;
  Mode get grammar;
  IndentRules get indentRules;
}

/// How a language indents, and which tokens open and close an indented block.
///
/// Declared here rather than next to the run command because indentation is a
/// property of the grammar, not of how the program is executed.
class IndentRules {
  final int indentWidth;
  final bool insertSpaces;
  final List<String> blockOpeners;
  final List<String> blockClosers;

  const IndentRules({
    this.indentWidth = 4,
    this.insertSpaces = true,
    this.blockOpeners = const [],
    this.blockClosers = const [],
  });
}

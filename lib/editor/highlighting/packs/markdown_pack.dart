import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/markdown.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class MarkdownPack implements LanguagePack {
  @override
  String get id => 'markdown';

  @override
  String get displayName => 'Markdown';

  @override
  List<String> get fileExtensions => ['md', 'mkdown', 'mkd'];

  @override
  Mode get grammar => markdown;

  @override
  IndentRules get indentRules => const IndentRules(indentWidth: 2);

  @override
  RunConfig get runConfig => const RunConfig();
}

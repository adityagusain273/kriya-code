import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/bash.dart';

import '../language_pack.dart';

class BashPack implements LanguagePack {
  @override
  String get id => 'bash';

  @override
  String get displayName => 'Bash';

  @override
  List<String> get fileExtensions => ['sh', 'bash', 'zsh'];

  @override
  Mode get grammar => bash;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['then', 'do', '{']);
}

import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/python.dart';

import '../../../plugins/api/run_config.dart';
import '../language_pack.dart';

class PythonPack implements LanguagePack {
  @override
  String get id => 'python';

  @override
  String get displayName => 'Python';

  @override
  List<String> get fileExtensions => ['py', 'pyw'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= _patchGrammar();

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: [':']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'cpython',
          runArgv: ['{runtimePath}/bin/python3', '{file}'],
        ),
      );

  Mode _patchGrammar() {
    final kw = python.keywords as Map<String, String>;
    kw['keyword'] = (kw['keyword'] as String)
        .replaceAll('print ', ' ')
        .replaceAll(' print', ' ');
    kw['built_in'] = '${kw['built_in']} print';

    python.contains?.removeWhere((m) =>
        m != null && m.begin != null && m.begin!.contains('(print|exec)\\('));

    python.contains?.insert(
      0,
      Mode(
        className: 'built_in',
        begin:
            '\\b(print|exec|len|range|int|str|float|list|dict|set|tuple|type|isinstance|input|open|super|abs|all|any|bin|bool|chr|dir|divmod|enumerate|eval|filter|format|frozenset|getattr|globals|hasattr|hash|hex|id|isinstance|issubclass|iter|locals|map|max|min|next|oct|ord|pow|print|property|repr|reversed|round|setattr|slice|sorted|sum|super|vars|zip)\\(',
      ),
    );

    return python;
  }
}

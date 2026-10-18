import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/markdown.dart';

import '../../plugins/api/run_config.dart';
import 'language_pack.dart';

@pragma('vm:entry-point')
class _PythonPackImpl implements LanguagePack {
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

@pragma('vm:entry-point')
class _JavascriptPackImpl implements LanguagePack {
  @override
  String get id => 'javascript';

  @override
  String get displayName => 'JavaScript';

  @override
  List<String> get fileExtensions => ['js', 'jsx', 'mjs', 'cjs'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= javascript;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'nodejs',
          runArgv: ['{runtimePath}/bin/node', '{file}'],
        ),
      );
}

@pragma('vm:entry-point')
class _TypescriptPackImpl implements LanguagePack {
  @override
  String get id => 'typescript';

  @override
  String get displayName => 'TypeScript';

  @override
  List<String> get fileExtensions => ['ts', 'tsx'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= typescript;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'nodejs',
          runArgv: ['{runtimePath}/bin/npx', 'ts-node', '{file}'],
        ),
      );
}

@pragma('vm:entry-point')
class _JavaPackImpl implements LanguagePack {
  @override
  String get id => 'java';

  @override
  String get displayName => 'Java';

  @override
  List<String> get fileExtensions => ['java'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= java;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'openjdk',
          buildArgv: ['{runtimePath}/bin/javac', '{file}'],
          runArgv: ['{runtimePath}/bin/java', '{name}'],
        ),
      );
}

@pragma('vm:entry-point')
class _CPackImpl implements LanguagePack {
  @override
  String get id => 'c';

  @override
  String get displayName => 'C';

  @override
  List<String> get fileExtensions => ['c', 'h'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= cpp;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'clang',
          buildArgv: ['{runtimePath}/bin/clang', '{file}', '-o', '{name}'],
          runArgv: ['{name}'],
        ),
      );
}

@pragma('vm:entry-point')
class _CppPackImpl implements LanguagePack {
  @override
  String get id => 'cpp';

  @override
  String get displayName => 'C++';

  @override
  List<String> get fileExtensions => ['cpp', 'cc', 'cxx', 'hpp', 'hxx'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= cpp;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 4, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'clang',
          buildArgv: ['{runtimePath}/bin/clang++', '{file}', '-o', '{name}'],
          runArgv: ['{name}'],
        ),
      );
}

@pragma('vm:entry-point')
class _HtmlPackImpl implements LanguagePack {
  @override
  String get id => 'html';

  @override
  String get displayName => 'HTML';

  @override
  List<String> get fileExtensions => ['html', 'htm'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= xml;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['<', '{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'bash',
          runArgv: ['{runtimePath}/bin/bash', '-c', 'cd {dir} && python3 -m http.server 8080'],
        ),
      );
}

@pragma('vm:entry-point')
class _CssPackImpl implements LanguagePack {
  @override
  String get id => 'css';

  @override
  String get displayName => 'CSS';

  @override
  List<String> get fileExtensions => ['css'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= css;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['{', '[', '(']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'bash',
          runArgv: ['{runtimePath}/bin/bash', '-c', 'cd {dir} && python3 -m http.server 8080'],
        ),
      );
}

@pragma('vm:entry-point')
class _JsonPackImpl implements LanguagePack {
  @override
  String get id => 'json';

  @override
  String get displayName => 'JSON';

  @override
  List<String> get fileExtensions => ['json'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= json;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['{', '[']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'bash',
          runArgv: ['{runtimePath}/bin/cat', '{file}'],
        ),
      );
}

@pragma('vm:entry-point')
class _MarkdownPackImpl implements LanguagePack {
  @override
  String get id => 'markdown';

  @override
  String get displayName => 'Markdown';

  @override
  List<String> get fileExtensions => ['md', 'markdown'];

  Mode? _grammar;

  @override
  Mode get grammar => _grammar ??= markdown;

  @override
  IndentRules get indentRules =>
      const IndentRules(indentWidth: 2, blockOpeners: ['>', '-', '*', '1.']);

  @override
  RunConfig get runConfig => const RunConfig(
        local: LocalTarget(
          runtimeId: 'bash',
          runArgv: ['{runtimePath}/bin/cat', '{file}'],
        ),
      );
}
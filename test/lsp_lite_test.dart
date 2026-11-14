import 'dart:io';

import 'package:b_code/editor/diagnostics_bar.dart';
import 'package:b_code/lsp/definition_provider.dart';
import 'package:b_code/lsp/diagnostics.dart';
import 'package:b_code/lsp/outline_parser.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 500+ line Python file: 40 classes, each with three methods, then a
/// top-level function.
String pythonSample({int classes = 40}) {
  final b = StringBuffer('import os\n\n');
  for (var c = 0; c < classes; c++) {
    b.writeln('class Class$c:');
    b.writeln('    """Docstring $c."""');
    b.writeln('    def __init__(self, value):');
    b.writeln('        self.value = value');
    b.writeln();
    b.writeln('    def method_a(self):');
    b.writeln('        return self.value + 1');
    b.writeln();
    b.writeln('    def method_b(self, other):');
    b.writeln('        total = 0');
    b.writeln('        for i in range(other):');
    b.writeln('            total += i');
    b.writeln('        return total');
    b.writeln();
  }
  b.writeln('def entry_point():');
  b.writeln('    return 0');
  return b.toString();
}

/// A 500+ line JavaScript file: a constant, a function, an arrow function and a
/// class per block.
String jsSample({int blocks = 60}) {
  final b = StringBuffer('// generated\n');
  b.writeln("import thing from 'thing';\n");
  b.writeln("const VERSION = '1.0.0';\n");
  for (var i = 0; i < blocks; i++) {
    b.writeln('function helper$i(a) {');
    b.writeln('  const inner = a * 2;');
    b.writeln('  return inner + $i;');
    b.writeln('}');
    b.writeln();
    b.writeln('const arrow$i = (a) => {');
    b.writeln('  return a + $i;');
    b.writeln('};');
    b.writeln();
    b.writeln('class Widget$i {');
    b.writeln('  render() {');
    b.writeln("    return 'widget $i';");
    b.writeln('  }');
    b.writeln('}');
    b.writeln();
  }
  return b.toString();
}

void main() {
  group('Python outline', () {
    test('extracts a 500-line class and method hierarchy', () {
      final text = pythonSample();
      expect(text.split('\n').length, greaterThan(500));

      final outline = OutlineParser.parse(text, 'python');
      final classes = outline.where((s) => s.kind == SymbolKind.class_).toList();
      expect(classes, hasLength(40));
      expect(outline.last.name, 'entry_point');
      expect(outline.last.kind, SymbolKind.function);
      expect(outline.last.children, isEmpty);
    });

    test('nests methods under their class with the right line and offset', () {
      final text = pythonSample();
      final first = OutlineParser.parse(text, 'python').first;
      expect(first.name, 'Class0');
      expect(first.line, 2);

      final names = first.children.map((s) => s.name).toList();
      expect(names, ['__init__', 'method_a', 'method_b']);
      expect(first.children.every((s) => s.kind == SymbolKind.method), isTrue);

      final methodA = first.children[1];
      expect(methodA.line, 7);
      expect(text.substring(methodA.offset, methodA.offset + 8), 'method_a');

      // A class ends where the next one starts, not at the last method.
      final second = OutlineParser.parse(text, 'python')[1];
      expect(first.endLine, second.line - 1);
    });

    test('a def nested in a def is a function, not a method', () {
      final outline = OutlineParser.parse(
        'class A:\n'
        '    def one(self):\n'
        '        def two():\n'
        '            return 1\n'
        '        return two\n',
        'python',
      );
      final one = outline.single.children.single;
      expect(one.kind, SymbolKind.method);
      expect(one.children.single.kind, SymbolKind.function);
    });

    test('a symbol inside a docstring or a comment is not a symbol', () {
      final outline = OutlineParser.parse(
        '"""\n'
        'def notReal():\n'
        '"""\n'
        '# def alsoNot():\n'
        'def real():\n'
        '    return 1\n',
        'python',
      );
      expect(outline.map((s) => s.name), ['real']);
    });
  });

  group('JavaScript outline', () {
    test('extracts a 500-line file structure', () {
      final text = jsSample();
      expect(text.split('\n').length, greaterThan(500));

      final outline = OutlineParser.parse(text, 'javascript');
      expect(outline.where((s) => s.kind == SymbolKind.class_), hasLength(60));
      expect(
        outline.where((s) => s.kind == SymbolKind.function && s.name.startsWith('helper')),
        hasLength(60),
      );
      expect(
        outline.where((s) => s.name.startsWith('arrow') && s.kind == SymbolKind.function),
        hasLength(60),
      );
      expect(outline.where((s) => s.name == 'VERSION').single.kind,
          SymbolKind.variable);

      final first = outline.firstWhere((s) => s.name == 'VERSION');
      expect(first.line, 3);
      expect(text.substring(first.offset, first.offset + 7), 'VERSION');
    });

    test('a declaration inside a function is not top level', () {
      final outline = OutlineParser.parse(
        'function outer() {\n'
        '  const inner = 1;\n'
        '  return inner;\n'
        '}\n',
        'javascript',
      );
      expect(outline.map((s) => s.name), ['outer']);
    });

    test('a block ends on its closing brace', () {
      final text = 'class A {\n  m() {\n    return 1;\n  }\n}\n\n'
          'function after() {}\n';
      final outline = OutlineParser.parse(text, 'javascript');
      final a = outline.firstWhere((s) => s.name == 'A');
      expect(a.endLine, 4);
      final after = outline.firstWhere((s) => s.name == 'after');
      expect(after.line, 6);
    });

    test('braces in strings and comments are not brackets', () {
      expect(
        CodeDiagnostics.analyze(
          "const s = '}{';\n"
          '// ) ] }\n'
          'function ok() { return s; }\n',
          'javascript',
        ),
        isEmpty,
      );
    });
  });

  group('go to definition', () {
    late Directory root;
    late FsService fs;

    setUp(() {
      root = Directory.systemTemp.createTempSync('bcode_def_');
      fs = FsService(root.path);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('finds a definition used before it is declared', () async {
      final text = 'value = helper(2)\n\n\ndef helper(x):\n    return x\n';
      final provider = DefinitionProvider(fs: fs);
      final location = await provider.resolve(
        active: const DocumentSnapshot('/w/main.py', ''),
        offset: 0,
        languageId: 'python',
        open: const [],
      );
      expect(location, isNull);

      final found = await provider.resolve(
        active: DocumentSnapshot('/w/main.py', text),
        offset: 'value = '.length,
        languageId: 'python',
        open: [DocumentSnapshot('/w/main.py', text)],
      );
      expect(found, isNotNull);
      expect(found!.path, '/w/main.py');
      expect(found.name, 'helper');
      expect(found.line, 3);
      expect(text.substring(found.offset, found.offset + 6), 'helper');
    });

    test('finds a declaration in another open tab', () async {
      final provider = DefinitionProvider(fs: fs);
      final location = await provider.resolve(
        active: DocumentSnapshot('/w/main.py', 'helper(1)\n'),
        offset: 1,
        languageId: 'python',
        open: [
          DocumentSnapshot('/w/main.py', 'helper(1)\n'),
          DocumentSnapshot('/w/util.py', 'def helper(x):\n    return x\n'),
        ],
      );
      expect(location, isNotNull);
      expect(location!.path, '/w/util.py');
      expect(location.line, 0);
    });

    test('finds a declaration in the workspace index', () async {
      await fs.createDirectory('pkg');
      await fs.writeFile(
        'pkg/util.py',
        'def helper(x):\n'
        '    return x + 1\n',
      );
      await fs.writeFile('other.py', 'helper = 3\n');

      final provider = DefinitionProvider(fs: fs);
      final location = await provider.resolve(
        active: DocumentSnapshot('${fs.rootPath}/main.py', 'print(helper(1))\n'),
        offset: 6,
        languageId: 'python',
        open: [DocumentSnapshot('${fs.rootPath}/main.py', 'print(helper(1))\n')],
      );
      expect(location, isNotNull);
      expect(location!.path, '${fs.rootPath}/pkg/util.py');
      expect(location.line, 0);
    });

    test('a word that is not declared anywhere resolves to nothing', () async {
      final provider = DefinitionProvider(fs: fs);
      final location = await provider.resolve(
        active: DocumentSnapshot('/w/main.py', 'print(missing)\n'),
        offset: 6,
        languageId: 'python',
        open: const [],
      );
      expect(location, isNull);
    });

    test('the word under the caret is found at its edges', () {
      expect(DefinitionProvider.wordAt('helper(1)', 0), 'helper');
      expect(DefinitionProvider.wordAt('helper(1)', 5), 'helper');
      expect(DefinitionProvider.wordAt('helper(1)', 6), 'helper');
      expect(DefinitionProvider.wordAt('helper(1)', 9), isNull);
      expect(DefinitionProvider.wordAt('', 0), isNull);
      expect(DefinitionProvider.wordAt('a ', 99), isNull);
    });
  });

  group('diagnostics', () {
    test('a healthy 500-line file has none', () {
      expect(CodeDiagnostics.analyze(pythonSample(), 'python'), isEmpty);
      expect(CodeDiagnostics.analyze(jsSample(), 'javascript'), isEmpty);
    });

    test('one broken bracket is one diagnostic that clears on fix', () {
      const broken = 'def a():\n    return (1 + 2\n';
      final found = CodeDiagnostics.analyze(broken, 'python');
      expect(found, hasLength(1));
      expect(found.single.line, 1);
      expect(found.single.column, 11);
      expect(found.single.message, contains("Unclosed '('"));

      expect(
        CodeDiagnostics.analyze('def a():\n    return (1 + 2)\n', 'python'),
        isEmpty,
      );
    });

    test('a closer with no opener is reported where it appears', () {
      final found = CodeDiagnostics.analyze('x = [1, 2))\n', 'python');
      expect(found, hasLength(1));
      expect(found.single.column, 9);
      expect(found.single.message, "Unexpected ')'");
    });

    test('an unterminated string is reported at the quote', () {
      final found = CodeDiagnostics.analyze('x = "abc\ny = 2\n', 'python');
      expect(found, hasLength(1));
      expect(found.single.line, 0);
      expect(found.single.column, 4);
      expect(found.single.message, 'Unterminated string literal');
    });

    test('a triple-quoted string may span lines', () {
      expect(
        CodeDiagnostics.analyze('"""a\nb\nc"""\nx = 1\n', 'python'),
        isEmpty,
      );
    });

    test('mixed tabs and spaces in indentation', () {
      final found = CodeDiagnostics.analyze('def f():\n \tpass\n', 'python');
      expect(
        found.any((d) => d.message == 'Mixed tabs and spaces in indentation'),
        isTrue,
      );
    });

    test('a block statement missing a colon is flagged on that statement', () {
      final found = CodeDiagnostics.analyze(
        'if __name__ == "__main__"\n'
        '    main()\n',
        'python',
      );
      expect(found, hasLength(1));
      expect(found.first.line, 0);
      expect(found.first.message, "Expected ':' at end of statement");
    });

    test('an indent with no block above it', () {
      final found = CodeDiagnostics.analyze('def f():\n    a = 1\n      b = 2\n', 'python');
      expect(found.any((d) => d.message == 'Unexpected indent'), isTrue);
    });

    test('a block opener with nothing indented under it', () {
      final found = CodeDiagnostics.analyze('def f():\nx = 1\n', 'python');
      expect(found.any((d) => d.message == 'Expected an indented block'), isTrue);
    });

    test('an unindent that matches no outer level', () {
      final found = CodeDiagnostics.analyze(
        'def f():\n'
        '    if a:\n'
        '        pass\n'
        '   else:\n'
        '        pass\n',
        'python',
      );
      expect(
        found.any((d) => d.message == 'Unindent does not match any outer indentation level'),
        isTrue,
      );
    });

    test('a continuation line may line up under anything', () {
      final found = CodeDiagnostics.analyze(
        'def f():\n'
        '    return max(\n'
        '        a,\n'
        '            b,\n'
        '    )\n',
        'python',
      );
      expect(found, isEmpty);
    });

    test('a string containing brackets is not unbalanced', () {
      expect(
        CodeDiagnostics.analyze('x = "("\ny = 1\n', 'python'),
        isEmpty,
      );
    });

    test('a regex containing a quote is not an unterminated string', () {
      expect(
        CodeDiagnostics.analyze('const re = /"/g;\nconst y = 1;\n', 'javascript'),
        isEmpty,
      );
    });

    test('a docstring-only class body is not an empty block', () {
      expect(
        CodeDiagnostics.analyze(
          r'''class slice(AST):
    """Deprecated AST node class."""

class Index(slice):
    """Deprecated."""
''',
          'python',
        ),
        isEmpty,
      );
    });

    test('code after a closing triple quote is a continuation', () {
      expect(
        CodeDiagnostics.analyze(
          r'''x = """
    text
    """ % (a,)
def f():
    return 1
''',
          'python',
        ),
        isEmpty,
      );
    });

    test('a wrapped if condition with a trailing backslash is one statement', () {
      expect(
        CodeDiagnostics.analyze(
          'def f(proto):\n'
          '    if proto not in {0, 1} or \\\n'
          '            proto is None:\n'
          '        return None\n'
          '    return 1\n',
          'python',
        ),
        isEmpty,
      );
    });

    test('a def whose parameter list wraps is one statement', () {
      expect(
        CodeDiagnostics.analyze(
          'class A:\n'
          '    def __init__(self, default, default_factory, init, repr, hash, compare,\n'
          '                 metadata, kw_only):\n'
          '        self.name = None\n',
          'python',
        ),
        isEmpty,
      );
    });

    test('languages with no checks report nothing', () {
      expect(CodeDiagnostics.analyze('x = (\n', 'dart'), isEmpty);
      expect(CodeDiagnostics.analyze('x = (\n', null), isEmpty);
    });

    test('a 500-line file with one error reports exactly that one', () {
      final text = pythonSample().replaceFirst(
        '        return self.value + 1',
        '        return (self.value + 1',
      );
      final found = CodeDiagnostics.analyze(text, 'python');
      expect(found, hasLength(1));
      expect(found.single.line, 8);
      expect(found.single.message, contains("Unclosed '('"));
    });
  });

  group('diagnostics bar', () {
    testWidgets('shows the line and reports the tapped diagnostic', (tester) async {
      Diagnostic? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiagnosticsBar(
            diagnostics: [
              Diagnostic(offset: 4, length: 1, line: 2, column: 4, message: "Unclosed '('"),
            ],
            onSelect: (d) => tapped = d,
          ),
        ),
      ));

      expect(find.text("Line 3: Unclosed '('"), findsOneWidget);
      await tester.tap(find.text("Line 3: Unclosed '('"));
      expect(tapped?.line, 2);
    });

    testWidgets('caps the rows and counts the rest', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiagnosticsBar(
            diagnostics: [
              for (var i = 0; i < 5; i++)
                Diagnostic(offset: i, length: 1, line: i, column: 0, message: 'problem $i'),
            ],
            onSelect: (_) {},
          ),
        ),
      ));

      expect(find.text('+2 more'), findsOneWidget);
      expect(find.textContaining('problem 3'), findsNothing);
    });
  });

  group('outline symbol model', () {
    test('a container reports itself as one', () {
      final outline = OutlineParser.parse('class A:\n    pass\n', 'python');
      expect(outline.single.isContainer, isTrue);
      expect(outline.single.toString(), contains('A (SymbolKind.class_)'));
    });

    test('an unsupported language has no outline and no symbols', () {
      expect(OutlineParser.parse('void main() {}', 'dart'), isEmpty);
      expect(OutlineParser.parse('', 'python'), isEmpty);
    });
  });
}

import 'package:b_code/editor/highlighting/async_highlighter.dart';
import 'package:b_code/editor/highlighting/bcode_controller.dart';
import 'package:b_code/editor/highlighting/bcode_theme.dart';
import 'package:b_code/editor/highlighting/highlight_engine.dart';
import 'package:b_code/editor/highlighting/packs/c_pack.dart';
import 'package:b_code/editor/highlighting/packs/cpp_pack.dart';
import 'package:b_code/editor/highlighting/packs/css_pack.dart';
import 'package:b_code/editor/highlighting/packs/html_pack.dart';
import 'package:b_code/editor/highlighting/packs/java_pack.dart';
import 'package:b_code/editor/highlighting/packs/javascript_pack.dart';
import 'package:b_code/editor/highlighting/packs/json_pack.dart';
import 'package:b_code/editor/highlighting/packs/markdown_pack.dart';
import 'package:b_code/editor/highlighting/packs/python_pack.dart';
import 'package:b_code/editor/highlighting/packs/typescript_pack.dart';
import 'package:b_code/editor/highlighting/syntax_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/highlight_core.dart';

/// One realistic snippet per bundled pack. Deliberately includes constructs that make
/// the highlighter emit container nodes rather than leaves — preprocessor directives,
/// doctypes, template literals, escaped quotes — because those are the shapes where
/// a node-tree transform is most likely to drop or duplicate text.
const samples = <String, String>{
  'python': 'def f(x):\n    return x + 1  # note\nprint(f(2))\n',
  'java':
      'class A {\n  int x = 1;\n  void m(String s) { System.out.println(s); }\n}\n',
  'c': '#include <stdio.h>\nint main(void) { printf("hi\\n"); return 0; }\n',
  'cpp':
      '#include <iostream>\nint main() { std::cout << "hi" << std::endl; }\n',
  'javascript':
      'function f(a) { return a + 1; }\nconst y = [1, 2].map(v => v + 1);\n',
  'typescript':
      'interface A { x: number }\nconst f = (a: A): number => a.x + 1;\n',
  'html': '<!DOCTYPE html>\n<html><body class="x"><p>hi</p></body></html>\n',
  'css': '.a { color: #fff; }\n.b > .c { margin: 0 auto; }\n',
  'json': '{"a": 1, "b": [true, null], "c": "s"}\n',
  'markdown': '# Title\n\n- item `code`\n\n```js\nvar a = 1;\n```\n',
};

/// String shapes that make the grammar emit a `string` node with children.
const stringCases = <String, List<String>>{
  'python': [
    r's = f"a{x}b"',
    r's = rb"raw\x00"',
    r's = "tab\t nl\n quote\""',
    's = """tri\nline"""',
    r'x = "a" "b"',
  ],
  'javascript': [
    r'const s = `a${b}c`;',
    r'const s = `outer ${ `inner ${x}` } end`;',
    r'const s = "a\"b";',
    r'const t = /ab+c/gi;',
  ],
  'typescript': [
    r'const s: string = `a${b as string}c`;',
    r'type T = `pre${string}post`;',
  ],
  'java': [
    r'String s = "a\"b";',
    'String s = """text block""";',
  ],
  'c': [
    r'char *s = "a\"b";',
    r'char *s = "esc \x41 \101 \0";',
  ],
  'cpp': [
    r'auto s = R"(raw "quoted" string)";',
  ],
  'html': [
    '<style>.a{content:"}"}</style>',
    '<!-- a "quoted" comment -->',
  ],
  'css': [
    '.a::before { content: "}"; }',
    '@media (min-width: 1px) { .b { color: red } }',
  ],
  'json': [
    r'{"k": "a\"b", "n": [1, {"m": null}]}',
  ],
};

HighlightEngine buildEngine() => HighlightEngine()
  ..register(PythonPack())
  ..register(JavaPack())
  ..register(CPack())
  ..register(CppPack())
  ..register(JavascriptPack())
  ..register(TypeScriptPack())
  ..register(HtmlPack())
  ..register(CssPack())
  ..register(JsonPack())
  ..register(MarkdownPack());

String flatten(InlineSpan span) {
  final b = StringBuffer();
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null) b.write(s.text);
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(span);
  return b.toString();
}

Future<BCodeController> pump(WidgetTester tester, String text, Mode? g) async {
  final controller = BCodeController(
    text: text,
    language: g,
    params: const EditorParams(tabSpaces: 4),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CodeTheme(
          data: CodeThemeData(styles: bcodeTheme),
          child: CodeField(controller: controller, expands: true),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(controller.settleHighlight);
  await tester.pump();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = buildEngine();
  tearDownAll(AsyncHighlighter.instance.close);

  group('theme coverage', () {
    testWidgets(
        'every token class a bundled grammar emits is styled by every '
        'shipped theme', (tester) async {
      final emitted = <String>{};
      for (final entry in samples.entries) {
        final g = await engine.grammarFor(entry.key);
        final c = await pump(tester, entry.value, g);
        for (final run in c.highlightRuns ?? const <HighlightRun>[]) {
          if (run.className != null) emitted.add(run.className!);
        }
        c.dispose();
      }
      expect(emitted, isNotEmpty);

      final problems = <String>[];
      for (final theme in SyntaxThemes.all) {
        for (final className in emitted) {
          if (!theme.styles.containsKey(className)) {
            problems.add('${theme.id} does not style $className');
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('every theme defines the whole bracket palette', () {
      for (final theme in SyntaxThemes.all) {
        for (final key in bracketPalette.keys) {
          expect(theme.styles.containsKey(key), isTrue,
              reason: '${theme.id} is missing $key');
        }
      }
    });

    test('every styled token actually resolves to a colour', () {
      for (final theme in SyntaxThemes.all) {
        for (final entry in tokenFallbacks.entries) {
          final style = theme.styles[entry.key];
          if (style == null) continue;
          expect(style.color, isNotNull,
              reason: '${theme.id}.${entry.key} has no colour to fall back to');
        }
      }
    });

    test('the editor default theme resolves to a known theme', () {
      expect(SyntaxThemes.fromId('monokai_sublime').id, 'monokai_sublime');
      expect(SyntaxThemes.fromId('nope').id, 'monokai_sublime');
      expect(SyntaxThemes.fromId('monokai_sublime').styles,
          containsPair('bracket-1', isNotNull));
    });
  });

  group('rendered text fidelity', () {
    testWidgets('the span tree renders exactly the document', (tester) async {
      for (final entry in samples.entries) {
        final g = await engine.grammarFor(entry.key);
        final c = await pump(tester, entry.value, g);
        final ctx = tester.element(find.byType(CodeField));
        expect(flatten(c.buildTextSpan(context: ctx, withComposing: false)),
            entry.value,
            reason: '${entry.key} lost or duplicated text');
        c.dispose();
      }
    });

    testWidgets('awkward string literals survive the node transform',
        (tester) async {
      for (final entry in stringCases.entries) {
        final g = await engine.grammarFor(entry.key);
        for (final src in entry.value) {
          final c = await pump(tester, src, g);
          final ctx = tester.element(find.byType(CodeField));
          expect(
              flatten(c.buildTextSpan(context: ctx, withComposing: false)), src,
              reason: '${entry.key}: $src');
          c.dispose();
        }
      }
    });

    testWidgets('newline count is preserved', (tester) async {
      const src = 'def f():\n    s = "a\\"b"\n    return s  # c\n';
      final g = await engine.grammarFor('python');
      final c = await pump(tester, src, g);
      final ctx = tester.element(find.byType(CodeField));
      final out = flatten(c.buildTextSpan(context: ctx, withComposing: false));
      expect('\n'.allMatches(out).length, '\n'.allMatches(src).length);
      c.dispose();
    });

    testWidgets('rebuilding does not mutate the tree further', (tester) async {
      // The rendered span is cached and must stay byte-for-byte identical across
      // repaints, including after the highlight result has been flattened.
      for (final entry in samples.entries) {
        final g = await engine.grammarFor(entry.key);
        final c = await pump(tester, entry.value, g);
        final ctx = tester.element(find.byType(CodeField));
        final first =
            flatten(c.buildTextSpan(context: ctx, withComposing: false));
        for (var i = 0; i < 4; i++) {
          expect(flatten(c.buildTextSpan(context: ctx, withComposing: false)),
              first,
              reason: '${entry.key} drifted on rebuild ${i + 2}');
        }
        c.dispose();
      }
    });
  });

  group('token colourisation', () {
    testWidgets('a snippet renders several distinct colours', (tester) async {
      final theme = SyntaxThemes.fromId('monokai_sublime').styles;
      const src = 'def f(x):\n    return "s" + str(x)\n';
      final g = await engine.grammarFor('python');
      final c = await pump(tester, src, g);
      final ctx = tester.element(find.byType(CodeField));
      final span = c.buildTextSpan(context: ctx, withComposing: false);

      final root = theme['root']?.color;
      final seen = <Color?>{};
      var colouredChars = 0;
      var totalChars = 0;

      void walk(InlineSpan s, TextStyle? inherited) {
        if (s is! TextSpan) return;
        final effective = s.style ?? inherited;
        final t = s.text;
        if (t != null && t.trim().isNotEmpty) {
          totalChars += t.length;
          final col = effective?.color;
          if (col != null && col != root) {
            colouredChars += t.length;
            seen.add(col);
          }
        }
        for (final ch in s.children ?? const <InlineSpan>[]) {
          walk(ch, effective);
        }
      }

      walk(span, null);
      expect(seen.length, greaterThanOrEqualTo(4),
          reason: 'expected several token colours, saw $seen');
      expect(colouredChars * 2, greaterThan(totalChars),
          reason: 'less than half the snippet was coloured');
      c.dispose();
    });

    testWidgets('a bracket keeps a colour rather than falling back to the body',
        (tester) async {
      final theme = SyntaxThemes.fromId('monokai_sublime').styles;
      // The Python pack hands the highlighter `print(` as one `built_in` token, so
      // `(` would render as body text if the bracket class were unstyled.
      const src = 'print(1)\n';
      final g = await engine.grammarFor('python');
      final c = await pump(tester, src, g);
      final ctx = tester.element(find.byType(CodeField));
      final span = c.buildTextSpan(context: ctx, withComposing: false);

      Color? bracketColour;
      void walk(InlineSpan s, TextStyle? inherited) {
        if (s is! TextSpan) return;
        final effective = s.style ?? inherited;
        if (s.text == '(' || s.text == ')') bracketColour = effective?.color;
        for (final ch in s.children ?? const <InlineSpan>[]) {
          walk(ch, effective);
        }
      }

      walk(span, null);
      expect(bracketColour, isNotNull);
      expect(bracketColour, isNot(theme['root']?.color));
      c.dispose();
    });
  });
}

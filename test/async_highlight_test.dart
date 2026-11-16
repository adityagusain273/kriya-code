import 'dart:async';

import 'package:b_code/editor/highlighting/async_highlighter.dart';
import 'package:b_code/editor/highlighting/bcode_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/plaintext.dart';

String flatten(InlineSpan span) {
  final buffer = StringBuffer();
  void walk(InlineSpan current) {
    if (current is! TextSpan) return;
    if (current.text != null) buffer.write(current.text);
    for (final child in current.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  walk(span);
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('span preservation', () {
    test('splicing keeps the prefix and suffix classes', () {
      final oldRuns = const [
        HighlightRun(0, 3, 'keyword'),
        HighlightRun(3, 6, 'string'),
      ];
      final runs = spliceHighlightRuns(oldRuns, 'abcxyz', 'abQxyz');

      expect(runs.map((r) => r.start), [0, 3]);
      expect(runs.map((r) => r.end), [3, 6]);
      expect(runs.first.className, 'keyword');
      expect(runs.last.className, 'string');
    });

    test('splicing always covers the whole buffer', () {
      const oldRuns = [HighlightRun(0, 4, 'keyword')];
      for (final edit in ['', 'x', 'longer text', '\n\n']) {
        final runs = spliceHighlightRuns(oldRuns, 'code', edit);
        if (edit.isEmpty) {
          expect(runs, isEmpty, reason: 'edit=$edit');
          continue;
        }
        expect(runs.first.start, 0, reason: 'edit=$edit');
        expect(runs.last.end, edit.length, reason: 'edit=$edit');
      }
    });

    testWidgets('typing keeps colours while the async pass is pending',
        (tester) async {
      final pending = <Completer<List<HighlightRun>?>>[];
      final controller = BCodeController(
        text: 'abc',
        language: plaintext,
        highlightRequest: (text, mode) {
          final completer = Completer<List<HighlightRun>?>();
          pending.add(completer);
          return completer.future;
        },
      );
      addTearDown(controller.dispose);

      await tester.pump(const Duration(milliseconds: 1));
      pending.removeAt(0).complete(const [HighlightRun(0, 3, 'keyword')]);
      await tester.pump();
      expect(controller.highlightRuns, isNotNull);

      controller.value = const TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 3),
      );

      // Nothing has completed yet, but the previous colours were re-anchored.
      expect(controller.text, 'abcd');
      expect(controller.highlightRuns, isNotNull);
      expect(controller.highlightRuns!.last.end, 4);
      expect(controller.selection.baseOffset, 2);
      expect(controller.value.composing, const TextRange(start: 1, end: 3));

      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      expect(
        flatten(controller.buildTextSpan(context: context, style: null)),
        'abcd',
      );

      // The debounce has not elapsed, so no new request was made.
      expect(pending, hasLength(0));
      await tester.pump(BCodeController.highlightDebounce);
      expect(pending, hasLength(1));
      pending.removeAt(0).complete(const [HighlightRun(0, 4, 'comment')]);
      await tester.pump();

      expect(controller.highlightRuns!.single.className, 'comment');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    });

    testWidgets('a burst of keystrokes costs one tokenization', (tester) async {
      var requests = 0;
      final controller = BCodeController(
        text: 'a',
        language: plaintext,
        highlightRequest: (text, mode) async {
          requests++;
          return [HighlightRun(0, text.length, 'keyword')];
        },
      );
      addTearDown(controller.dispose);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(requests, 1);

      controller.text = 'ab';
      controller.text = 'abc';
      controller.text = 'abcd';
      await tester.pump(const Duration(milliseconds: 100));

      expect(requests, 1);
      expect(controller.highlightRuns, isNotNull);
      expect(controller.highlightRuns!.last.end, 4);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(requests, 2);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    });

    testWidgets('selection and composing changes do not re-tokenize',
        (tester) async {
      var requests = 0;
      final controller = BCodeController(
        text: 'abcdef',
        language: plaintext,
        highlightRequest: (text, mode) async {
          requests++;
          return [HighlightRun(0, text.length, 'keyword')];
        },
      );
      addTearDown(controller.dispose);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(requests, 1);

      controller.value = const TextEditingValue(
        text: 'abcdef',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 4),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(requests, 1);
      expect(controller.selection.baseOffset, 3);
      expect(controller.value.composing, const TextRange(start: 1, end: 4));

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    });
    testWidgets('a run list that does not cover the buffer renders plain text',
        (tester) async {
      final controller = BCodeController(
        text: 'abcdef',
        language: plaintext,
        highlightRequest: (text, mode) async => const [
          HighlightRun(0, 2, 'keyword'),
          HighlightRun(4, 5, 'comment'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final span = controller.buildTextSpan(context: context, style: null);

      expect(span.text, 'abcdef');
      expect(span.children, isNull);
    });
  });

  group('content cache', () {
    tearDownAll(AsyncHighlighter.instance.close);

    test('the same buffer is tokenized once', () async {
      const source = 'const value = 1;\nprint(value);\n';
      final first = await AsyncHighlighter.instance.highlight(
        source,
        javascript,
      );
      final second = await AsyncHighlighter.instance.highlight(
        source,
        javascript,
      );

      expect(first, isNotNull);
      expect(first!.last.end, source.length);
      expect(identical(first, second), isTrue,
          reason: 'the cache should return the same run list');
    });

    test('line endings survive the worker round trip', () async {
      const source = 'const a = 1;\r\n';
      final runs = await AsyncHighlighter.instance.highlight(
        source,
        javascript,
      );

      expect(runs, isNotNull);
      expect(runs!.last.end, source.length);
    });
  });

  group('tree flattening', () {
    test('brackets are coloured by depth and strings are left alone', () {
      final runs = buildHighlightRuns(
        [
          Node(value: 'print('),
          Node(className: 'string', value: '"("'),
          Node(value: ')'),
        ],
        'print("(")',
      );

      expect(runs, isNotNull);
      expect(runs!.last.end, 10);
      final brackets =
          runs.where((r) => (r.className ?? '').startsWith('bracket-'));
      expect(brackets, hasLength(2));
      expect(brackets.first.className, 'bracket-1');
      expect(brackets.last.className, 'bracket-1');
      final string = runs.where((r) => r.className == 'string');
      expect(string.single.start, 6);
      expect(string.single.end, 9);
    });

    test('a tree that does not cover the text is rejected', () {
      expect(
        buildHighlightRuns([Node(value: 'short')], 'longer text'),
        isNull,
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart';

import 'package:kriya_code/editor/highlighting/async_highlighter.dart';
import 'package:kriya_code/editor/highlighting/bcode_controller.dart';

String _lines(int count, {int width = 20}) =>
    List.generate(count, (i) => 'x' * width + '$i').join('\n');

Future<BCodeController> _mount(
  WidgetTester tester,
  String text, {
  List<HighlightRun>? runs,
}) async {
  final controller = BCodeController(
    text: text,
    language: Mode(),
    highlightRequest: (_, __) async => runs,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CodeField(controller: controller, expands: true),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BCodeController.isLargeBuffer', () {
    test('a small buffer is colourable', () {
      expect(BCodeController.isLargeBuffer(_lines(100)), isFalse);
    });

    test('a buffer past the line threshold is large', () {
      expect(
        BCodeController.isLargeBuffer(_lines(2001)),
        isTrue,
        reason: '2,001 lines is past the 2,000-line threshold',
      );
    });

    test('a buffer past the character threshold is large', () {
      final wide = 'x' * (60 * 1024 + 1);
      expect(BCodeController.isLargeBuffer(wide), isTrue);
    });

    test('a buffer just under both thresholds is not large', () {
      expect(BCodeController.isLargeBuffer(_lines(1999)), isFalse);
    });
  });

  group('large-file guard', () {
    testWidgets('a large buffer never tokenises', (tester) async {
      var requested = 0;
      final controller = BCodeController(
        text: _lines(2001),
        language: Mode(),
        highlightRequest: (_, __) async {
          requested++;
          return const [];
        },
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CodeField(controller: controller, expands: true)),
        ),
      );
      await tester.runAsync(controller.settleHighlight);

      expect(controller.plainTextFallback, isTrue);
      expect(controller.highlightRuns, isNull);
      expect(requested, 0, reason: 'a large buffer must not be tokenised');
    });

    testWidgets('a large buffer renders as one plain span', (tester) async {
      final controller = await _mount(tester, _lines(2001), runs: const []);
      addTearDown(controller.dispose);
      await tester.runAsync(controller.settleHighlight);

      final context = tester.element(find.byType(CodeField));
      final span = controller.buildTextSpan(context: context, style: null);

      expect(span.children, isNull);
      expect(span.text, isNotNull);
      expect(span.text!.length, controller.text.length);
    });

    testWidgets('a small buffer keeps its colours', (tester) async {
      final controller = await _mount(
        tester,
        'void main() {}',
        runs: const [HighlightRun(0, 4, 'keyword'), HighlightRun(4, 13, null)],
      );
      addTearDown(controller.dispose);
      await tester.runAsync(controller.settleHighlight);

      expect(controller.plainTextFallback, isFalse);
      expect(controller.highlightRuns, isNotNull);
    });

    test('a buffer that grows past the threshold drops its colours', () async {
      final controller = BCodeController(
        text: 'void main() {}',
        language: Mode(),
        highlightRequest: (text, mode) async =>
            [HighlightRun(0, text.length, null)],
      );
      addTearDown(controller.dispose);
      await controller.settleHighlight();
      expect(controller.highlightRuns, isNotNull);

      controller.text = _lines(2001);
      await Future<void>.delayed(Duration.zero);

      expect(controller.plainTextFallback, isTrue);
      expect(
        controller.highlightRuns,
        isNull,
        reason: 'the stale runs must go, or the span would still be huge',
      );
    });

    testWidgets('shrinking back under the threshold resumes highlighting',
        (tester) async {
      var requested = 0;
      final controller = BCodeController(
        text: _lines(2001),
        language: Mode(),
        highlightRequest: (text, mode) async {
          requested++;
          return [HighlightRun(0, text.length, null)];
        },
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CodeField(controller: controller, expands: true)),
        ),
      );
      await tester.runAsync(controller.settleHighlight);
      expect(requested, 0);

      controller.text = 'void main() {}';
      await tester.runAsync(controller.settleHighlight);

      expect(controller.plainTextFallback, isFalse);
      expect(controller.highlightRuns, isNotNull);
    });
  });
}
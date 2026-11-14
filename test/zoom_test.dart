import 'package:b_code/editor/zoom_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  double fontSize,
  ValueChanged<double> onFontSizeCommit, {
  ValueChanged<double>? onFontSizePreview,
  double minFontSize = 8.0,
  double maxFontSize = 64.0,
  Widget? child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BCodeZoomView(
        fontSize: fontSize,
        onFontSizePreview: onFontSizePreview,
        onFontSizeCommit: onFontSizeCommit,
        minFontSize: minFontSize,
        maxFontSize: maxFontSize,
        child: child ?? const SizedBox(width: 400, height: 400),
      ),
    ),
  );
}

void main() {
  testWidgets('shows nothing at default 14pt', (tester) async {
    await tester.pumpWidget(host(14.0, (_) {}));
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('pinching out increases font size and commits on release', (tester) async {
    var size = 14.0;
    double? committed;
    await tester.pumpWidget(host(
      size,
      (v) => committed = v,
      onFontSizePreview: (v) => size = v,
    ));

    final touch1 = await tester.startGesture(const Offset(200, 100), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 300), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 50));
    await touch2.moveTo(const Offset(200, 450));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(committed, isNotNull);
    expect(committed!, greaterThan(14.0));
  });

  testWidgets('pinching in reduces font size', (tester) async {
    var size = 20.0;
    double? committed;
    await tester.pumpWidget(host(
      size,
      (v) => committed = v,
      onFontSizePreview: (v) => size = v,
    ));

    final touch1 = await tester.startGesture(const Offset(200, 50), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 350), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 170));
    await touch2.moveTo(const Offset(200, 230));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(committed, isNotNull);
    expect(committed!, lessThan(20.0));
  });

  testWidgets('one-finger drag does not zoom', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(14.0, (_) => calls++));

    final touch = await tester.startGesture(const Offset(200, 200));
    await touch.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch.up();
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('tapping the pinch badge restores the configured font size',
      (tester) async {
    double? committed;
    await tester.pumpWidget(host(14.0, (v) => committed = v));

    final touch1 = await tester.startGesture(const Offset(200, 100), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 300), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 50));
    await touch2.moveTo(const Offset(200, 450));
    await tester.pump();

    expect(find.textContaining('px'), findsOneWidget);

    await tester.tap(find.textContaining('px'), pointer: 3);
    await tester.pump();

    expect(committed, 14.0);

    await touch1.up();
    await touch2.up();
  });

  testWidgets('two-finger pinch works on the editor itself', (tester) async {
    final controller = CodeController(text: 'def hello():\n    print("world")\n');
    addTearDown(controller.dispose);

    double? committed;
    await tester.pumpWidget(host(
      14.0,
      (v) => committed = v,
      child: CodeField(controller: controller, expands: true),
    ));

    final touch1 = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 250), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 100));
    await touch2.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(committed, isNotNull);
    expect(committed!, greaterThan(14.0));
  });
}

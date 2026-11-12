import 'package:b_code/editor/zoom_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives BCodeZoomView the way the editor does: the caller owns the scale.
Widget host(
  double scale,
  ValueChanged<double> onScaleChanged, {
  double minScale = 0.5,
  double maxScale = 3.0,
  Widget? child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BCodeZoomView(
        scale: scale,
        onScaleChanged: onScaleChanged,
        minScale: minScale,
        maxScale: maxScale,
        child: child ?? const SizedBox(width: 400, height: 400),
      ),
    ),
  );
}

void main() {
  testWidgets('shows nothing until the user zooms', (tester) async {
    await tester.pumpWidget(host(1.0, (_) {}));
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('pinching out raises the scale', (tester) async {
    var scale = 1.0;
    await tester.pumpWidget(host(scale, (v) => scale = v));

    final touch1 = await tester.startGesture(const Offset(200, 100), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 300), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 50));
    await touch2.moveTo(const Offset(200, 450));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(scale, greaterThan(1.0));
    await tester.pumpWidget(host(scale, (_) {}));
    expect(find.text('${(scale * 100).round()}%'), findsOneWidget);
  });

  testWidgets('pinching in zooms below 100%', (tester) async {
    var scale = 1.0;
    await tester.pumpWidget(host(scale, (v) => scale = v));

    final touch1 = await tester.startGesture(const Offset(200, 50), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 350), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 170));
    await touch2.moveTo(const Offset(200, 230));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(scale, lessThan(1.0));
  });

  testWidgets('one-finger drag does not zoom, so scrolling and selection survive',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(1.0, (_) => calls++));

    final touch = await tester.startGesture(const Offset(200, 200));
    await touch.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch.up();
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('two-finger pinch works on the editor itself', (tester) async {
    final controller = CodeController(text: 'def hello():\n    print("world")\n');
    addTearDown(controller.dispose);

    var scale = 1.0;
    await tester.pumpWidget(host(
      scale,
      (v) => scale = v,
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

    expect(scale, greaterThan(1.0));
  });

  testWidgets('tapping the indicator resets to 100%', (tester) async {
    var scale = 2.5;
    await tester.pumpWidget(host(scale, (v) => scale = v));
    expect(find.text('250%'), findsOneWidget);

    await tester.tap(find.text('250%'));
    await tester.pumpWidget(host(scale, (_) {}));
    await tester.pump();

    expect(scale, 1.0);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('clamps to the configured range', (tester) async {
    var scale = 1.0;
    await tester.pumpWidget(host(scale, (v) => scale = v, minScale: 1, maxScale: 4));

    final touch1 = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 300), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 50));
    await touch2.moveTo(const Offset(200, 550));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(scale, 4.0);
  });

  testWidgets('keeps the child it was given', (tester) async {
    await tester.pumpWidget(host(
      1.0,
      (_) {},
      child: const Stack(
        children: [
          SizedBox(key: Key('base'), width: 100, height: 100),
          Positioned.fill(child: IgnorePointer(child: Text('overlay'))),
        ],
      ),
    ));

    expect(find.byKey(const Key('base')), findsOneWidget);
    expect(find.text('overlay'), findsOneWidget);
  });
}

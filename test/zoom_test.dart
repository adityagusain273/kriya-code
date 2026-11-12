import 'package:b_code/editor/zoom_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

TransformationController controllerOf(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

Widget host(Widget child, {double maxScale = 4}) => MaterialApp(
  home: Scaffold(
    body: BCodeZoomView(
      minScale: 1,
      maxScale: maxScale,
      child: child,
    ),
  ),
);

void main() {
  testWidgets('shows nothing until the user zooms', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 200, height: 200)));

    // Enabling the extension must be invisible until it is used.
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('reports the applied scale', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 200, height: 200)));

    // A real pinch ends up moving the transformation controller, so that is what is
    // driven here. Simulating two fingers directly proved nothing: the gesture was
    // delivered but never produced a span change, so the test passed a viewer that
    // was in fact fine and failed to catch one that was not.
    controllerOf(tester).value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 2.0, 1);
    await tester.pump();

    expect(find.text('200%'), findsOneWidget);
  });

  testWidgets('tapping the indicator resets to 100%', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 200, height: 200)));

    controllerOf(tester).value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1);
    await tester.pump();
    expect(find.text('250%'), findsOneWidget);

    await tester.tap(find.text('250%'));
    await tester.pump();

    expect(find.textContaining('%'), findsNothing);
    // The transform itself has to be reset, not just the label, or the content
    // would stay enlarged with the indicator claiming otherwise.
    expect(controllerOf(tester).value.getMaxScaleOnAxis(), 1.0);
  });

  testWidgets('keeps the child it was given', (tester) async {
    // The overlay that draws syntax colours sits on top of the editor. Wrapping the
    // editor and dropping the overlay is how zoom silently removed highlighting.
    await tester.pumpWidget(
      host(
        const Stack(
          children: [
            SizedBox(key: Key('base'), width: 100, height: 100),
            Positioned.fill(child: IgnorePointer(child: Text('overlay'))),
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('base')), findsOneWidget);
    expect(find.text('overlay'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('reports the scale as it settles, not on every frame', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 200, height: 200)));

    // 100% would read as "not zoomed" and hide the indicator, so the label is only
    // meaningful away from it.
    controllerOf(tester).value = Matrix4.identity()..scaleByDouble(1.0, 1.0, 1.0, 1);
    await tester.pump();
    expect(find.textContaining('%'), findsNothing);

    controllerOf(tester).value = Matrix4.identity()..scaleByDouble(1.5, 1.5, 1.5, 1);
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
  });

  testWidgets('pinching with two fingers scales the viewer', (tester) async {
    await tester.pumpWidget(host(const SizedBox(width: 400, height: 400)));

    final touch1 = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 250), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 100));
    await touch2.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(controllerOf(tester).value.getMaxScaleOnAxis(), greaterThan(1.0));
  });

  testWidgets('pinching on an editable text field scales the viewer', (tester) async {
    final controller = TextEditingController(text: 'line 1\nline 2\nline 3\nline 4\nline 5\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(TextField(controller: controller, maxLines: null, expands: true)));

    final touch1 = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 250), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 100));
    await touch2.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(controllerOf(tester).value.getMaxScaleOnAxis(), greaterThan(1.0));
  });

  testWidgets('pinching on CodeField scales the viewer and allows pan', (tester) async {
    final controller = CodeController(text: 'def hello():\n    print("world")\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(CodeField(controller: controller, expands: true)));

    final touch1 = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final touch2 = await tester.startGesture(const Offset(200, 250), pointer: 2);
    await tester.pump();
    await touch1.moveTo(const Offset(200, 100));
    await touch2.moveTo(const Offset(200, 350));
    await tester.pump();
    await touch1.up();
    await touch2.up();
    await tester.pump();

    expect(controllerOf(tester).value.getMaxScaleOnAxis(), greaterThan(1.0));
    expect(find.textContaining('%'), findsOneWidget);
  });
}
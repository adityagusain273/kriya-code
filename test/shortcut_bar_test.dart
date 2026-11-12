import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/editor/shortcut_bar.dart';

Widget wrap(CodeController controller, {int indentWidth = 4}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
                child: TextField(
                    controller: controller, maxLines: null, expands: true)),
            EditorShortcutBar(
              controller: controller,
              indentWidth: indentWidth,
              onFind: () {},
              onSave: () {},
            ),
          ],
        ),
      ),
    );

void main() {
  group('EditorShortcutBar', () {
    testWidgets(
        'inserting a bracket produces a matched pair with cursor inside',
        (tester) async {
      final controller = CodeController(text: 'printx');

      await tester.pumpWidget(wrap(controller));
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await tester.tap(find.text('('));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      addTearDown(controller.dispose);

      expect(controller.text, 'print()x');
      expect(controller.selection.baseOffset, 6,
          reason: 'cursor should sit between the pair');
    });

    testWidgets('inserting quote wraps the selected text', (tester) async {
      final controller = CodeController(text: 'ab');

      await tester.pumpWidget(wrap(controller));
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 2);
      await tester.pump();
      await tester.tap(find.text('"'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      addTearDown(controller.dispose);

      expect(controller.text, '"ab"');
      expect(controller.selection.baseOffset, 4,
          reason: 'cursor lands after the closing quote');
    });

    testWidgets('plain symbols insert single character', (tester) async {
      final controller = CodeController(text: 'a');

      await tester.pumpWidget(wrap(controller));
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await tester.tap(find.text(';'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      addTearDown(controller.dispose);

      expect(controller.text, 'a;');
      expect(controller.selection.baseOffset, 2);
    });

    testWidgets('TAB inserts indent spaces', (tester) async {
      final controller = CodeController(text: 'if:');

      await tester.pumpWidget(wrap(controller, indentWidth: 4));
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_tab));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      addTearDown(controller.dispose);

      expect(controller.text, 'if:    ');
      expect(controller.selection.baseOffset, 7);
    });
  });
}

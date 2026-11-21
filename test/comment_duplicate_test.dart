import 'package:kriya_code/editor/highlighting/bcode_controller.dart';
import 'package:kriya_code/editor/line_commands.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/plaintext.dart';

/// Builds a controller the way `EditorTab` does. Without a language the underlying
/// editor segments the text incorrectly and keeps only the first line.
BCodeController controllerWith(String text, {int offset = 0}) {
  final controller = BCodeController(text: text, language: plaintext);
  controller.selection = TextSelection.collapsed(offset: offset);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('duplicateLine', () {
    test('duplicating the only line of a file adds a separator', () {
      final c = controllerWith('ab');
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, 'ab\nab');
    });

    test('duplicating the last line adds a separator', () {
      final c = controllerWith('a\nb', offset: 2);
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, 'a\nb\nb');
    });

    test('duplicating a middle line', () {
      final c = controllerWith('a\nb\nc', offset: 2);
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, 'a\nb\nb\nc');
    });

    test('duplicating the first line', () {
      final c = controllerWith('a\nb');
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, 'a\na\nb');
    });

    test('a file that already ends in a newline keeps exactly one', () {
      final c = controllerWith('ab\n');
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, 'ab\nab\n');
    });

    test('an empty line duplicates to a second empty line', () {
      final c = controllerWith('');
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.text, '\n');
    });

    test('the caret lands on the copied line', () {
      final c = controllerWith('a\nb', offset: 2);
      addTearDown(c.dispose);

      c.duplicateLine();

      expect(c.selection.baseOffset, 5);
    });
  });

  group('toggleComment with a line prefix', () {
    test('comments the caret line', () {
      final c = controllerWith('print(1)\nprint(2)');
      addTearDown(c.dispose);

      c.toggleComment('//', '');

      expect(c.text, '// print(1)\nprint(2)');
    });

    test('uncomments an already commented line', () {
      final c = controllerWith('// print(1)');
      addTearDown(c.dispose);

      c.toggleComment('//', '');

      expect(c.text, 'print(1)');
    });

    test('round trips', () {
      final c = controllerWith('x = 1');
      addTearDown(c.dispose);

      c.toggleComment('#', '');
      expect(c.text, '# x = 1');
      c.toggleComment('#', '');
      expect(c.text, 'x = 1');
    });

    test('preserves leading indentation', () {
      final c = controllerWith('    x = 1', offset: 6);
      addTearDown(c.dispose);

      c.toggleComment('#', '');

      expect(c.text, '    # x = 1');
    });
  });

  group('toggleComment with a block prefix', () {
    test('wraps a css rule in a complete block comment', () {
      final c = controllerWith('.foo { color: red; }');
      addTearDown(c.dispose);

      c.toggleComment('/*', '*/');

      expect(c.text, '/* .foo { color: red; } */');
      expect(c.text.contains('*/'), isTrue,
          reason: 'an unterminated /* swallows every following line');
    });

    test('css round trips', () {
      final c = controllerWith('.a {}\n.b {}', offset: 0);
      addTearDown(c.dispose);

      c.toggleComment('/*', '*/');
      expect(c.text, '/* .a {} */\n.b {}');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.toggleComment('/*', '*/');
      expect(c.text, '.a {}\n.b {}');
    });

    test('a line that is nothing but the marker does not throw', () {
      final c = controllerWith('<!--');
      addTearDown(c.dispose);

      c.toggleComment('<!--', '-->');

      expect(c.text.contains('<!--'), isTrue);
    });

    test('a bare css marker does not throw', () {
      final c = controllerWith('/*');
      addTearDown(c.dispose);

      c.toggleComment('/*', '*/');

      expect(c.text.contains('/*'), isTrue);
    });

    test('uncommenting keeps the surrounding lines intact', () {
      final c = controllerWith('/* .a {} */\n.b {}');
      addTearDown(c.dispose);

      c.toggleComment('/*', '*/');

      expect(c.text, '.a {}\n.b {}');
    });

    test('uncommenting is undoable', () {
      final c = controllerWith('/* .a {} */');
      addTearDown(c.dispose);

      c.toggleComment('/*', '*/');
      expect(c.text, '.a {}');

      c.historyController.undo();
      expect(c.text, '/* .a {} */');
    });

    test('wraps a selection', () {
      final c = controllerWith('abcdef');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

      c.toggleComment('<!--', '-->');

      expect(c.text, 'a<!-- bcd -->ef');
    });

    test('unwraps a commented selection', () {
      final c = controllerWith('a<!-- bcd -->ef');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 13);

      c.toggleComment('<!--', '-->');

      expect(c.text, 'a bcd ef');
    });
  });

  group('stripBlockMarkers', () {
    test('unwraps a well formed comment', () {
      expect(stripBlockMarkers('<!-- x -->', '<!--', '-->'), ' x ');
      expect(stripBlockMarkers('/* x */', '/*', '*/'), ' x ');
    });

    test('returns null when the markers are not both present', () {
      expect(stripBlockMarkers('<!-- x', '<!--', '-->'), isNull);
      expect(stripBlockMarkers('x -->', '<!--', '-->'), isNull);
      expect(stripBlockMarkers('plain', '/*', '*/'), isNull);
    });

    test('returns null instead of throwing on a bare marker', () {
      expect(stripBlockMarkers('<!--', '<!--', '-->'), isNull);
      expect(stripBlockMarkers('/*', '/*', '*/'), isNull);
    });
  });
}

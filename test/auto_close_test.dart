import 'package:b_code/editor/highlighting/bcode_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/plaintext.dart';

/// Drives the controller the way the keyboard does: one character inserted at the
/// caret, which is what the editor's own auto-close hooks look for.
///
/// Going through the widget and tapping keys cannot verify this reliably, because
/// the on-screen shortcut row scrolls while being tapped and the wrong key ends up
/// under the finger.
/// A controller with the caret placed, the way a focused field has one.
///
/// A fresh controller's selection sits at -1, and the editor's insertion hook
/// deliberately ignores an edit made from that state, so a test that types without
/// focusing first is not exercising the same path as a real keystroke.
BCodeController focused(String text) {
  final controller = BCodeController(text: text, language: plaintext);
  controller.selection = TextSelection.collapsed(offset: text.length);
  return controller;
}

TextEditingValue typed(BCodeController controller, String character) {
  final text = controller.text;
  final caret = controller.selection.start.clamp(0, text.length);
  return TextEditingValue(
    text: text.replaceRange(caret, caret, character),
    selection: TextSelection.collapsed(offset: caret + character.length),
  );
}

void main() {
  group('typing an opening bracket closes it', () {
    test('parenthesis', () {
      final c = focused('');
      c.value = typed(c, '(');
      expect(c.text, '()');
      // Caret must sit between the brackets, or the next keystroke lands outside.
      expect(c.selection.baseOffset, 1);
    });

    test('square bracket', () {
      final c = focused('');
      c.value = typed(c, '[');
      expect(c.text, '[]');
    });

    test('brace', () {
      final c = focused('');
      c.value = typed(c, '{');
      expect(c.text, '{}');
    });

    test('double quote', () {
      final c = focused('');
      c.value = typed(c, '"');
      expect(c.text, '""');
    });

    test('a second opening bracket does not double up', () {
      final c = focused('');
      c.value = typed(c, '(');
      c.value = typed(c, '(');
      // Typing the bracket again inside the pair is a real case: it should end up
      // nested rather than producing an unbalanced mess.
      expect(RegExp(r'\(').allMatches(c.text).length, 2);
      expect(')'.allMatches(c.text).length, 2);
    });
  });

  group('typing a closing bracket steps over it', () {
    test('does not duplicate the closer', () {
      final c = focused('()');
      c.selection = const TextSelection.collapsed(offset: 1);
      c.value = typed(c, ')');
      expect(c.text, '()');
    });
  });

  group('a genuine closing character still inserts', () {
    test('an unmatched bracket is not swallowed', () {
      final c = focused('print(1) + 2');
      c.selection = const TextSelection.collapsed(offset: 12);
      c.value = typed(c, ')');
      // There is no open pair here, so the character must be inserted rather than
      // used to step over something that was not there.
      expect(c.text, 'print(1) + 2)');
    });

    test('a bracket typed after a closed pair inserts', () {
      final c = focused('f()');
      c.selection = const TextSelection.collapsed(offset: 3);
      c.value = typed(c, ')');
      expect(c.text, 'f())');
    });

    test('typing over the closer of an inner pair steps over', () {
      final c = focused('f(g())');
      c.selection = const TextSelection.collapsed(offset: 5);
      c.value = typed(c, ')');
      expect(c.text, 'f(g())');
      // The caret belongs after the bracket it stepped over.
      expect(c.selection.baseOffset, 6);
    });
  });

  group('quotes', () {
    test('stepping over a closing quote does not duplicate it', () {
      final c = focused('');
      c.value = typed(c, '"');
      expect(c.text, '""');
      c.value = typed(c, '"');
      expect(c.text, '""');
    });

    test('typing the quote closes the string that was opened', () {
      final c = focused('');
      c.value = typed(c, '"');
      c.value = typed(c, 'a');
      c.value = typed(c, '"');
      // The closer is under the caret, so the keystroke finishes the string rather
      // than starting a new one.
      expect(c.text, '"a"');
      expect(c.selection.baseOffset, 3);
    });
  });

  group('ordinary characters are untouched', () {
    test('a letter inserts literally', () {
      final c = focused('');
      c.value = typed(c, 'a');
      expect(c.text, 'a');
    });

    test('text typed inside a pair stays inside it', () {
      final c = focused('');
      c.value = typed(c, '(');
      c.value = typed(c, 'x');
      expect(c.text, '(x)');
    });
  });
}
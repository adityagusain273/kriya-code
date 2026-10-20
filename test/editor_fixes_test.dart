import 'package:b_code/editor/editor_page.dart';
import 'package:b_code/editor/find_replace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectLineEnding', () {
    test('reports the convention in use', () {
      expect(detectLineEnding('a\nb\n'), 'LF');
      expect(detectLineEnding('a\r\nb\r\n'), 'CRLF');
      expect(detectLineEnding('a\rb\r'), 'CR');
      expect(detectLineEnding('a\r\nb\n'), 'Mixed');
      expect(detectLineEnding(''), 'LF');
    });
  });

  group('FindReplaceController staleness', () {
    testWidgets('replaces the live match after the buffer changed underneath',
        (tester) async {
      final editor = TextEditingController(text: 'alpha\nbravo\ncharlie');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor);
      addTearDown(fr.dispose);

      fr.query = 'bravo';
      fr.search(jumpToFirst: true);
      expect(fr.matchCount, 1);

      // The find bar is closed, the user types at the top of the file, then reopens
      // it. Nothing recomputed the offsets, so the recorded match still points at
      // 6..11, which now covers `ha` and the newline.
      editor.value = TextEditingValue(
        text: 'XXalpha\nbravo\ncharlie',
        selection: const TextSelection.collapsed(offset: 17),
      );

      fr.replacement = 'ZZZ';
      fr.replaceCurrent();

      expect(editor.text, 'XXalpha\nZZZ\ncharlie');
    });

    testWidgets('reports matches for the current buffer, not the last search',
        (tester) async {
      final editor = TextEditingController(text: 'aaa');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor);
      addTearDown(fr.dispose);

      fr.query = 'a';
      fr.search(jumpToFirst: true);
      expect(fr.matchCount, 3);

      editor.value = TextEditingValue(
        text: 'aaaaa',
        selection: const TextSelection.collapsed(offset: 5),
      );

      expect(fr.matchCount, 5);
    });

    testWidgets('a selection change alone does not invalidate the matches',
        (tester) async {
      final editor = TextEditingController(text: 'a a a');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor);
      addTearDown(fr.dispose);

      fr.query = 'a';
      fr.search(jumpToFirst: true);
      expect(fr.matchCount, 3);

      // Moving the caret is what the bar itself does after every match.
      editor.selection = const TextSelection.collapsed(offset: 0);
      expect(fr.matchCount, 3);
      expect(fr.currentIndex, 0);

      fr.replacement = 'b';
      fr.replaceCurrent();
      expect(editor.text, 'b a a');
    });

    testWidgets('navigating uses live offsets after the buffer changed',
        (tester) async {
      final editor = TextEditingController(text: 'x\nx\nx');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor);
      addTearDown(fr.dispose);

      fr.query = 'x';
      fr.search(jumpToFirst: true);

      editor.value = TextEditingController(text: 'pre\nx\nx').value;
      expect(fr.matchCount, 2);

      // Still on the first match, which now sits at 4 rather than 0.
      expect(fr.currentIndex, 0);
      fr.previous();
      expect(editor.selection.baseOffset, 6);
      fr.next();
      expect(editor.selection.baseOffset, 4);
    });

    testWidgets('stops notifying once disposed', (tester) async {
      final editor = TextEditingController(text: 'aaa');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor)..query = 'a';
      fr.search(jumpToFirst: true);

      var notifications = 0;
      fr.addListener(() => notifications++);
      fr.dispose();

      editor.value = TextEditingValue(
        text: 'bbbbb',
        selection: const TextSelection.collapsed(offset: 5),
      );

      expect(notifications, 0);
    });

    testWidgets('replaceAll rewrites every live match', (tester) async {
      final editor = TextEditingController(text: 'foo\nfoo\nfoo');
      addTearDown(editor.dispose);
      final fr = FindReplaceController(editor);
      addTearDown(fr.dispose);

      fr.query = 'foo';
      fr.search(jumpToFirst: true);
      fr.replacement = 'bar';

      editor.value = TextEditingValue(
        text: 'head\nfoo\nfoo',
        selection: const TextSelection.collapsed(offset: 12),
      );

      fr.replaceAll();
      expect(editor.text, 'head\nbar\nbar');
    });
  });
}

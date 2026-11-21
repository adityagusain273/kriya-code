import 'package:kriya_code/editor/highlighting/bcode_controller.dart';
import 'package:highlight/languages/plaintext.dart';
import 'package:kriya_code/editor/line_commands.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a controller the way `EditorTab` does.
///
/// The language argument is not optional in practice: without one the underlying
/// editor segments the text incorrectly and keeps only the first line, which would
/// make these tests assert against a truncated document.
BCodeController controllerWith(String text, {int offset = 0}) {
  final controller = BCodeController(text: text, language: plaintext);
  controller.selection = TextSelection.collapsed(offset: offset);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('currentLineRange', () {
    test('first line starts at zero', () {
      final c = controllerWith('one\ntwo\nthree');
      expect(c.currentLineRange(), <int>[0, 3]);
    });

    test('middle line excludes the newline', () {
      final c = controllerWith('one\ntwo\nthree', offset: 5);
      expect(c.currentLineRange(), <int>[4, 7]);
    });

    test('last line stops at end of text', () {
      final c = controllerWith('one\ntwo\nthree', offset: 9);
      expect(c.currentLineRange(), <int>[8, 13]);
    });

    test('empty document has an empty range', () {
      expect(controllerWith('').currentLineRange(), <int>[0, 0]);
    });
  });

  group('moveLine', () {
    test('moves the caret line up', () {
      // Caret on the middle line.
      final c = controllerWith('a\nb\nc', offset: 2);
      expect(c.moveLine(-1), isTrue);
      expect(c.text, 'b\na\nc');
    });

    test('moves the caret line down', () {
      final c = controllerWith('a\nb\nc', offset: 0);
      expect(c.moveLine(1), isTrue);
      expect(c.text, 'b\na\nc');
    });

    test('refuses at the first line', () {
      final c = controllerWith('a\nb', offset: 0);
      expect(c.moveLine(-1), isFalse);
      expect(c.text, 'a\nb');
    });

    test('refuses at the last line', () {
      final c = controllerWith('a\nb', offset: 2);
      expect(c.moveLine(1), isFalse);
      expect(c.text, 'a\nb');
    });

    test('keeps the caret on the same character', () {
      // Caret sits on the 'b' itself, not on the newline after it.
      final c = controllerWith('a\nb\nc', offset: 2);
      expect(c.moveLine(-1), isTrue);
      expect(c.text, 'b\na\nc');
      expect(
        c.text.substring(c.selection.baseOffset, c.selection.baseOffset + 1),
        'b',
      );
    });

    test('keeps the column within the line when moving down', () {
      final c = controllerWith('a\nbc\nd', offset: 3);
      expect(c.moveLine(1), isTrue);
      expect(c.text, 'a\nd\nbc');
      // 'bc' moved down; the caret was on 'c', which is now at offset 5.
      expect(
        c.text.substring(c.selection.baseOffset, c.selection.baseOffset + 1),
        'c',
      );
    });

    test('preserves blank lines', () {
      // text: 'a', '', 'b' with caret on the blank line.
      final c = controllerWith('a\n\nb', offset: 2);
      expect(c.moveLine(-1), isTrue);
      expect(c.text, '\na\nb');
    });

    test('round trips', () {
      final c = controllerWith('one\ntwo\nthree', offset: 5);
      c.moveLine(-1);
      c.moveLine(1);
      expect(c.text, 'one\ntwo\nthree');
    });
  });

  group('copyLines', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('copies the caret line when nothing is selected', () async {
      final c = controllerWith('one\ntwo\nthree', offset: 5);
      c.copyLines();
      await Future<void>.delayed(Duration.zero);
      final copy = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      final data = (copy.arguments as Map)['text'] as String;
      expect(data, 'two');
    });

    test('copies every line a selection touches', () async {
      // Offsets 1..7 span the first two lines of 'one\ntwo\nthree' without
      // reaching into the third.
      final c = controllerWith('one\ntwo\nthree');
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 7);
      c.copyLines();
      await Future<void>.delayed(Duration.zero);
      final copy = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      final data = (copy.arguments as Map)['text'] as String;
      expect(data, 'one\ntwo');
    });
  });

  group('cutLines', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('removes the caret line and leaves the rest intact', () {
      final c = controllerWith('one\ntwo\nthree', offset: 5);
      c.cutLines();
      expect(c.text, 'one\nthree');
    });

    test('cutting the only line leaves one empty line, not a missing buffer', () {
      final c = controllerWith('only', offset: 2);
      c.cutLines();
      // The buffer stays open and empty rather than disappearing; the text is on
      // the clipboard and undo restores it.
      expect(c.text, isEmpty);
    });

    test('removes a whole block and keeps the remainder', () {
      final c = controllerWith('one\ntwo\nthree\nfour');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      c.cutLines();
      expect(c.text, 'three\nfour');
    });
  });
}
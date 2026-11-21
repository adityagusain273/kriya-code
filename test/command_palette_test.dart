import 'package:kriya_code/editor/command_palette.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keys the palette's action list looks up. Listed here so adding an action without
/// registering its callback fails a test instead of producing a dead menu entry.
const _callbackKeys = <String>[
  'open_explorer',
  'find_replace',
  'goto_line',
  'toggle_comment',
  'duplicate_line',
  'move_line_up',
  'move_line_down',
  'copy_line',
  'cut_line',
];

void main() {
  setUp(clearRunCallbacks);

  test('the callback registry reports what is registered', () {
    expect(hasEditCallback(const Key('move_line_up')), isFalse);
    setEditCallback(const Key('move_line_up'), () {});
    expect(hasEditCallback(const Key('move_line_up')), isTrue);
    clearRunCallbacks();
    expect(hasEditCallback(const Key('move_line_up')), isFalse);
  });

  test('every documented callback key is a distinct key', () {
    final keys = _callbackKeys.map(Key.new).toSet();
    expect(keys.length, _callbackKeys.length);
  });
}

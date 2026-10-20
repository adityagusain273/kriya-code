import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

/// Line-level editing commands that every code editor is expected to have.
///
/// These operate on the caret's line, or on every line the selection touches, and
/// leave the caret on the same line of text afterwards so repeated presses keep
/// doing the expected thing. They live here rather than in the editor page because
/// they are pure text transforms and worth testing without a widget tree.
///
/// Declared on [CodeController] rather than the editor's `BCodeController` subclass
/// so the commands resolve at the static type the editor page passes them at.
extension LineCommands on CodeController {
  /// Character range of the caret's line, as `[start, end)`.
  List<int> currentLineRange() {
    final text = value.text;
    if (text.isEmpty) return <int>[0, 0];
    final int caret = value.selection.start.clamp(0, text.length);
    int start = text.lastIndexOf('\n', caret > 0 ? caret - 1 : 0);
    start = start < 0 ? 0 : start + 1;
    int end = text.indexOf('\n', caret);
    if (end < 0) end = text.length;
    return <int>[start, end];
  }

  /// Swaps the caret's line with its neighbour.
  ///
  /// Returns false at the first and last line, where there is nothing to swap with,
  /// so a shortcut bound to this does not silently do nothing.
  bool moveLine(int delta) {
    final text = value.text;
    final lines = text.split('\n');
    final [start, end] = currentLineRange();
    var index = 0;
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      if (offset == start) {
        index = i;
        break;
      }
      offset += lines[i].length + 1;
    }
    final target = index + delta;
    if (index == 0 && delta < 0) return false;
    if (index == lines.length - 1 && delta > 0) return false;
    if (target < 0 || target >= lines.length) return false;

    final moved = lines.removeAt(index);
    lines.insert(target, moved);

    // Offsets are recomputed from the rebuilt text rather than carried over: the
    // lines that were swapped change length relative to everything after them, so
    // the old caret offset points at a different character.
    final rebuilt = lines.join('\n');
    final int caretInLine = value.selection.start - start;
    int newLineStart = 0;
    for (var i = 0; i < target; i++) {
      newLineStart += lines[i].length + 1;
    }
    _replaceBuffer(rebuilt, newLineStart + caretInLine);
    return true;
  }

  /// Duplicates the caret's line below itself.
  ///
  /// The separator goes *before* the copy. Putting it after — the obvious way to
  /// write this — silently concatenates whenever the line is the last one and the
  /// buffer has no trailing newline, so duplicating the only line of a file turned
  /// `ab` into `abab` and the last line of `a\nb` into `bb`.
  void duplicateLine() {
    final text = value.text;
    final selection = value.selection;
    if (selection.start < 0) return;

    final lines = text.split('\n');
    var pos = 0;
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (pos + lines[i].length >= selection.start) {
        index = i;
        break;
      }
      pos += lines[i].length + 1;
    }

    final line = lines[index];
    final insertAt = pos + line.length;
    final rebuilt = text.replaceRange(insertAt, insertAt, '\n$line');
    _replaceBuffer(rebuilt, insertAt + 1 + line.length);
  }

  /// Toggles a comment over the selection, or over the caret's line when there is
  /// none.
  ///
  /// An empty [suffix] selects the line-comment shape; a non-empty one selects the
  /// block-comment shape, which is the only correct form for languages where `//`
  /// does not exist.
  void toggleComment(String prefix, String suffix) {
    final text = value.text;
    final selection = value.selection;
    if (selection.start < 0) return;
    if (suffix.isEmpty) {
      _toggleLineComment(text, selection, prefix);
    } else {
      _toggleBlockComment(text, selection, prefix, suffix);
    }
  }

  void _toggleLineComment(String text, TextSelection sel, String prefix) {
    final lines = text.split('\n');
    final lineIdx = _lineIndexOf(text, sel.start);
    final line = lines[lineIdx];
    final trimmed = line.trimLeft();
    final leading = line.substring(0, line.length - trimmed.length);

    if (trimmed.startsWith('$prefix ') || trimmed.startsWith(prefix)) {
      final stripped = trimmed.startsWith('$prefix ')
          ? trimmed.substring(prefix.length + 1)
          : trimmed.substring(prefix.length);
      lines[lineIdx] = '$leading$stripped';
    } else {
      lines[lineIdx] = '$leading$prefix $trimmed';
    }
    _replaceKeepingCaret(lines.join('\n'), sel.start);
  }

  void _toggleBlockComment(
    String text,
    TextSelection sel,
    String prefix,
    String suffix,
  ) {
    if (!sel.isCollapsed && sel.start >= 0 && sel.end <= text.length) {
      final trimmed = text.substring(sel.start, sel.end).trim();
      final unwrapped = stripBlockMarkers(trimmed, prefix, suffix);
      if (unwrapped != null) {
        _splice(sel.start, sel.end, unwrapped, sel.start + unwrapped.length);
      } else {
        final wrapped = '$prefix $trimmed $suffix';
        _splice(sel.start, sel.end, wrapped, sel.start + wrapped.length);
      }
      return;
    }

    final lines = text.split('\n');
    final lineIdx = _lineIndexOf(text, sel.start);
    final line = lines[lineIdx];
    final trimmed = line.trim();
    final leading = line.substring(0, line.length - trimmed.length);

    final unwrapped = stripBlockMarkers(trimmed, prefix, suffix);
    if (unwrapped != null) {
      lines[lineIdx] = '$leading${unwrapped.trim()}';
    } else {
      lines[lineIdx] = '$leading$prefix $trimmed $suffix';
    }
    _replaceKeepingCaret(lines.join('\n'), sel.start);
  }

  /// Replaces the caret's range with [replacement] and parks the caret after it.
  void _splice(int start, int end, String replacement, int caret) {
    final updated = value.text.replaceRange(start, end, replacement);
    _replaceBuffer(updated, caret);
  }

  void _replaceKeepingCaret(String text, int caret) {
    _replaceBuffer(text, caret);
  }

  /// Assigns a whole new buffer and parks the caret at [caret].
  ///
  /// Setting `value` with a wholesale replacement is not safe on this editor.
  /// `CodeController`'s setter does not take the new text at face value: it diffs it
  /// against the previous buffer and rebuilds the full text, deriving the far end of
  /// the replaced range from the *length delta*. That only holds for a single
  /// character inserted or deleted at the caret, which is what the setter was
  /// written for. Uncommenting a block comment replaces `/* x {} */` with `x {}` —
  /// equal prefix and suffix around a shorter middle — and the buffer came back as
  /// `{} */`, six characters of the user's code silently destroyed.
  ///
  /// `fullText` is the library's own path for assigning a buffer wholesale and skips
  /// the reconstruction entirely. Undo still works, because the subsequent `selection`
  /// assignment goes back through the normal setter and is what records history.
  void _replaceBuffer(String text, int caret) {
    final target = caret.clamp(0, text.length).toInt();
    fullText = text;
    selection = TextSelection.collapsed(offset: target);
  }

  /// Index of the line containing [offset].
  ///
  /// The loop needs no explicit last-line branch: [index] already holds
  /// `lines.length - 1` when nothing matches earlier.
  int _lineIndexOf(String text, int offset) {
    final lines = text.split('\n');
    var pos = 0;
    for (var i = 0; i < lines.length; i++) {
      if (pos + lines[i].length >= offset) return i;
      pos += lines[i].length + 1;
    }
    return lines.length - 1;
  }

  /// Copies whole lines, the way every editor does when there is no selection.
  ///
  /// With text selected this is a plain copy, which is what makes it safe to bind to
  /// the same key: the behaviour only differs when a copy would otherwise copy
  /// nothing.
  void copyLines() {
    final ranges = _selectedLineRanges();
    if (ranges.isEmpty) return;
    final text = value.text;
    final copied = _joined(ranges, text);
    unawaited(Clipboard.setData(ClipboardData(text: copied)));
  }

  /// Copies whole lines and removes them.
  void cutLines() {
    final ranges = _selectedLineRanges();
    if (ranges.isEmpty) return;
    final text = value.text;
    final copied = _joined(ranges, text);
    unawaited(Clipboard.setData(ClipboardData(text: copied)));

    // Remove from the end so earlier offsets stay valid.
    final start = ranges.first[0];
    var removeTo = ranges.last[1];
    // Swallow the newline that joined this block to the next one.
    if (removeTo < text.length) removeTo += 1;
    final rebuilt = text.replaceRange(start, removeTo, '');
    _replaceBuffer(rebuilt, start);
  }

  /// Clipboard text for a set of line ranges.
  ///
  /// Any trailing newline is dropped: a copied line should paste as a line, not
  /// carry the separator that used to join it to its neighbour, which would
  /// accumulate blank lines each time it was pasted.
  String _joined(List<List<int>> ranges, String text) {
    final joined = ranges.map((r) => text.substring(r[0], r[1])).join('\n');
    return joined.endsWith('\n') ? joined.substring(0, joined.length - 1) : joined;
  }

  /// Ranges of every line touched by the selection, or the caret's line.
  ///
  /// Collapsed-ness is derived from the offsets rather than read from
  /// `TextSelection.isCollapsed`, because the editor controller re-normalises a
  /// selection it was given and can leave it looking expanded even when both ends
  /// sit on the same character. Trusting the flag there turned a single-line copy
  /// into a copy of everything from that line onward.
  List<List<int>> _selectedLineRanges() {
    final String text = value.text;
    if (text.isEmpty) return const <List<int>>[];

    final selection = value.selection;
    final int a = selection.start < 0 ? 0 : selection.start;
    final int b = selection.end < 0 ? 0 : selection.end;
    final int selStart = a < b ? a : b;
    final int selEnd = a < b ? b : a;
    final bool collapsed = selStart == selEnd;

    if (collapsed) return <List<int>>[currentLineRange()];

    final List<int> offsets = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) offsets.add(i + 1);
    }
    if (offsets.last != text.length) offsets.add(text.length);

    final List<List<int>> ranges = <List<int>>[];
    for (var i = 0; i + 1 < offsets.length; i++) {
      final int lineStart = offsets[i];
      // `offsets[i + 1]` points just past this line's newline. Pull it back so a
      // range covers the line's text only: copying then produces clean text, and
      // cutting can decide deliberately whether to take the newline that joined
      // this line to the next.
      final int rawEnd = offsets[i + 1];
      final int lineEnd = rawEnd < text.length ? rawEnd - 1 : rawEnd;
      if (lineEnd < selStart || lineStart > selEnd) continue;
      ranges.add(<int>[lineStart, lineEnd]);
    }
    return ranges;
  }
}

/// Removes a block comment's markers, or null when [trimmed] does not wrap one.
///
/// A line holding nothing but the marker satisfies both `startsWith` and
/// `endsWith` while being shorter than the two markers put together, so slicing
/// the inner range threw a `RangeError` instead of uncommenting anything.
String? stripBlockMarkers(String trimmed, String prefix, String suffix) {
  if (trimmed.length < prefix.length + suffix.length) return null;
  if (!trimmed.startsWith(prefix)) return null;
  if (!trimmed.endsWith(suffix)) return null;
  return trimmed.substring(prefix.length, trimmed.length - suffix.length);
}

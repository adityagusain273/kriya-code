import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LineNumberGutter extends StatelessWidget {
  const LineNumberGutter({
    super.key,
    required this.scrollPixels,
    required this.lineCount,
    required this.lineHeight,
    required this.textStyle,
    required this.width,
    this.errorLines = const {},
    this.topPadding = 0,
    this.lineTexts,
    this.charWidth,
    this.editorWidth,
  });

  final ValueListenable<double> scrollPixels;
  final int lineCount;
  final double lineHeight;
  final TextStyle textStyle;
  final double width;
  final Set<int> errorLines;
  final double topPadding;

  /// When word wrap is on, pass the text of each logical line so the gutter
  /// can compute how many visual rows each line occupies.
  final List<String>? lineTexts;
  final double? charWidth;
  final double? editorWidth;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: LineNumberPainter(
          scrollPixels: scrollPixels,
          lineCount: lineCount,
          lineHeight: lineHeight,
          textStyle: textStyle,
          width: width,
          errorLines: errorLines,
          topPadding: topPadding,
          lineTexts: lineTexts,
          charWidth: charWidth,
          editorWidth: editorWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class LineNumberPainter extends CustomPainter {
  LineNumberPainter({
    required this.scrollPixels,
    required this.lineCount,
    required this.lineHeight,
    required this.textStyle,
    required this.width,
    required this.errorLines,
    required this.topPadding,
    this.lineTexts,
    this.charWidth,
    this.editorWidth,
  }) : super(repaint: scrollPixels);

  final ValueListenable<double> scrollPixels;
  final int lineCount;
  final double lineHeight;
  final TextStyle textStyle;
  final double width;
  final Set<int> errorLines;
  final double topPadding;
  final List<String>? lineTexts;
  final double? charWidth;
  final double? editorWidth;

  static const double _rightMargin = 8;
  static const double _markerSize = 7;

  final LinkedHashMap<int, TextPainter> _numbers = LinkedHashMap<int, TextPainter>();

  /// Offsets are recomputed only when the text or the width changes; scrolling
  /// repaints keep hitting this cache instead of re-walking every line.
  List<int>? _cachedOffsets;
  List<String>? _cachedTexts;
  double? _cachedEditorWidth;

  /// Computes the visual row start (0-based) for each logical line,
  /// accounting for word-wrapped lines that span multiple rows.
  List<int> _computeVisualOffsets() {
    final texts = lineTexts;
    final cw = charWidth;
    final ew = editorWidth;
    if (_cachedOffsets != null &&
        identical(texts, _cachedTexts) &&
        ew == _cachedEditorWidth) {
      return _cachedOffsets!;
    }
    final offsets = List<int>.filled(lineCount, 0);
    if (texts == null || cw == null || ew == null || cw <= 0 || ew <= 0) {
      for (var i = 0; i < lineCount; i++) { offsets[i] = i; }
    } else {
      final charsPerRow = math.max(1, (ew / cw).floor());
      var row = 0;
      for (var i = 0; i < lineCount; i++) {
        offsets[i] = row;
        final len = i < texts.length ? texts[i].length : 0;
        row += math.max(1, (len / charsPerRow).ceil());
      }
    }
    _cachedOffsets = offsets;
    _cachedTexts = texts;
    _cachedEditorWidth = ew;
    return offsets;
  }

  TextPainter _number(int value) {
    final cached = _numbers.remove(value);
    if (cached != null) {
      _numbers[value] = cached;
      return cached;
    }
    if (_numbers.length > 512) _numbers.clear();
    final painter = TextPainter(
      text: TextSpan(text: '$value', style: textStyle),
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    _numbers[value] = painter;
    return painter;
  }

  /// The zero-based line range that intersects a viewport of [height] at
  /// [pixels] (no-wrap only: assumes one visual row per logical line).
  static (int, int) visibleRange({
    required double pixels,
    required double lineHeight,
    required double height,
    required int lineCount,
  }) {
    if (lineCount == 0 || lineHeight <= 0) return (0, -1);
    final first = math.max(0, (pixels / lineHeight).floor());
    final last = math.min(lineCount - 1, ((pixels + height) / lineHeight).ceil());
    return (first, last);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount == 0 || lineHeight <= 0) return;
    final pixels = scrollPixels.value;
    final offsets = _computeVisualOffsets();

    for (var i = 0; i < lineCount; i++) {
      final y = topPadding - pixels + offsets[i] * lineHeight;
      if (y + lineHeight < 0) continue;
      if (y > size.height) break;

      if (errorLines.contains(i)) {
        final top = y + (lineHeight - _markerSize) / 2;
        canvas.drawCircle(
          Offset(_markerSize / 2 + 1, top + _markerSize / 2),
          _markerSize / 2,
          Paint()..color = const Color(0xFFEF5350),
        );
      }
      final painter = _number(i + 1);
      final dx = width - _rightMargin - painter.width;
      painter.paint(canvas, Offset(dx, y));
    }
  }

  @override
  bool shouldRepaint(LineNumberPainter old) =>
      old.lineCount != lineCount ||
      old.lineHeight != lineHeight ||
      old.width != width ||
      old.errorLines != errorLines ||
      old.topPadding != topPadding ||
      old.textStyle != textStyle ||
      old.charWidth != charWidth ||
      old.editorWidth != editorWidth ||
      !identical(old.lineTexts, lineTexts);
}

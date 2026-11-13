import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The line-number column, painted only for the lines that are on screen.
///
/// `flutter_code_editor` builds its gutter as a [Table] with one row per line in
/// the file: 2001 rows, 8000 widgets, every one of them walked on each repaint
/// while scrolling. Measured on a 2001-line file that column cost ~19 ms of the
/// ~32 ms frame, which alone put the scroll budget out of reach. Drawing the
/// ~50 visible numbers instead keeps the column visually identical.
class LineNumberGutter extends StatelessWidget {
  const LineNumberGutter({
    super.key,
    required this.scrollPixels,
    required this.lineCount,
    required this.lineHeight,
    required this.textStyle,
    required this.width,
    this.topPadding = 0,
  });

  final ValueListenable<double> scrollPixels;
  final int lineCount;
  final double lineHeight;
  final TextStyle textStyle;
  final double width;

  /// Space the field keeps above its first line (`InputDecoration.contentPadding`).
  final double topPadding;

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
          topPadding: topPadding,
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
    required this.topPadding,
  }) : super(repaint: scrollPixels);

  final ValueListenable<double> scrollPixels;
  final int lineCount;
  final double lineHeight;
  final TextStyle textStyle;
  final double width;
  final double topPadding;
  static const double _rightMargin = 8;

  /// One laid-out paragraph per number, reused across frames.
  final LinkedHashMap<int, TextPainter> _numbers = LinkedHashMap<int, TextPainter>();

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
  /// [pixels], which is all this painter ever lays out.
  static (int, int) visibleRange({
    required double pixels,
    required double lineHeight,
    required double height,
    required int lineCount,
  }) {
    final first = math.max(0, (pixels / lineHeight).floor());
    final last = math.min(lineCount - 1, ((pixels + height) / lineHeight).ceil());
    return (first, last);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount == 0 || lineHeight <= 0) return;
    final pixels = scrollPixels.value;
    final (first, last) = visibleRange(
      pixels: pixels,
      lineHeight: lineHeight,
      height: size.height,
      lineCount: lineCount,
    );
    if (first >= lineCount) return;
    final y = topPadding - pixels;
    for (var i = first; i <= last; i++) {
      final painter = _number(i + 1);
      // A paragraph laid out at maxWidth keeps its own (shorter) width, so the
      // column's right edge has to be applied here: textAlign alone is a no-op
      // for a number that does not fill the column.
      final dx = width - _rightMargin - painter.width;
      painter.paint(canvas, Offset(dx, y + i * lineHeight));
    }
  }

  @override
  bool shouldRepaint(LineNumberPainter old) =>
      old.lineCount != lineCount ||
      old.lineHeight != lineHeight ||
      old.width != width ||
      old.topPadding != topPadding ||
      old.textStyle != textStyle;
}
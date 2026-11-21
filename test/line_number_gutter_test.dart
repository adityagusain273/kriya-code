import 'package:kriya_code/editor/line_number_gutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LineNumberPainter.visibleRange', () {
    test('a viewport at the top starts at the first line', () {
      expect(
        LineNumberPainter.visibleRange(
          pixels: 0,
          lineHeight: 21,
          height: 500,
          lineCount: 2001,
        ),
        (0, 24),
      );
    });

    test('only the lines a viewport can show are returned, never the whole file', () {
      final (first, last) = LineNumberPainter.visibleRange(
        pixels: 21 * 1000,
        lineHeight: 21,
        height: 500,
        lineCount: 2001,
      );
      expect(first, 1000);
      expect(last, 1024);
      expect(last - first + 1, lessThan(30));
    });

    test('scrolling past the end clamps to the last line', () {
      final (first, last) = LineNumberPainter.visibleRange(
        pixels: 21 * 1990,
        lineHeight: 21,
        height: 500,
        lineCount: 2001,
      );
      expect(first, 1990);
      expect(last, 2000);
    });

    test('an empty file has no visible lines', () {
      final (first, last) = LineNumberPainter.visibleRange(
        pixels: 0,
        lineHeight: 21,
        height: 500,
        lineCount: 0,
      );
      expect(first, 0);
      expect(last, -1);
    });
  });
}
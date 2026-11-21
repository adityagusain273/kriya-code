import 'package:kriya_code/editor/highlighting/diagnostic_highlight_builder.dart';
import 'package:kriya_code/lsp/diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticHighlightedBuilder', () {
    test('returns untouched span when diagnostics are empty', () {
      const original = TextSpan(text: 'print("hello")');
      final builder = DiagnosticHighlightedBuilder(
        diagnostics: const [],
        textLength: 14,
        rootStyle: null,
        textSpan: original,
      );
      final result = builder.build();
      expect(result.text, 'print("hello")');
      expect(result.children, isNull);
    });

    test('applies wavy underline decoration to specified diagnostic range', () {
      const original = TextSpan(
        children: [
          TextSpan(text: 'def '),
          TextSpan(text: 'foo()'),
          TextSpan(text: ':\n'),
          TextSpan(text: '    return (1 + 2\n'),
        ],
      );

      // Offset of the unclosed '(' is 22, length 1
      const diagnostic = Diagnostic(
        offset: 22,
        length: 1,
        line: 1,
        column: 11,
        message: "Unclosed '('",
      );

      final builder = DiagnosticHighlightedBuilder(
        diagnostics: const [diagnostic],
        textLength: 29,
        rootStyle: null,
        textSpan: original,
      );

      final result = builder.build();
      expect(result.children, isNotNull);

      // Verify that at least one child span has TextDecorationStyle.wavy
      final wavySpans = result.children!.where((span) {
        if (span is! TextSpan) return false;
        return span.style?.decorationStyle == TextDecorationStyle.wavy;
      }).toList();

      expect(wavySpans, isNotEmpty);
      final wavy = wavySpans.first as TextSpan;
      expect(wavy.text, '(');
      expect(wavy.style?.decoration?.contains(TextDecoration.underline), isTrue);
      expect(wavy.style?.decorationColor, const Color(0xFFFF5252));
    });

    test('merges overlapping diagnostics cleanly without duplicate slicing', () {
      const original = TextSpan(text: 'abcdefghij');

      final builder = DiagnosticHighlightedBuilder(
        diagnostics: const [
          Diagnostic(offset: 2, length: 4, line: 0, column: 2, message: 'Err1'), // 2..6
          Diagnostic(offset: 4, length: 4, line: 0, column: 4, message: 'Err2'), // 4..8
        ],
        textLength: 10,
        rootStyle: null,
        textSpan: original,
      );

      final result = builder.build();
      expect(result.children, isNotNull);

      final pieces = <String>[];
      for (final span in result.children!) {
        if (span is TextSpan && span.text != null) {
          pieces.add(span.text!);
        }
      }

      // Expected pieces: 'ab' (normal), 'cdefgh' (error: 2..8), 'ij' (normal)
      expect(pieces, ['ab', 'cdefgh', 'ij']);

      final errorSpan = result.children![1] as TextSpan;
      expect(errorSpan.style?.decorationStyle, TextDecorationStyle.wavy);
    });
  });
}

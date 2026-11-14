import 'package:flutter/widgets.dart';

import '../../lsp/diagnostics.dart';

/// Decorates [textSpan] by applying wavy red underlines to character ranges
/// flagged in [diagnostics].
class DiagnosticHighlightedBuilder {
  final List<Diagnostic> diagnostics;
  final int textLength;
  final TextStyle? rootStyle;
  final TextSpan textSpan;

  DiagnosticHighlightedBuilder({
    required this.diagnostics,
    required this.textLength,
    required this.rootStyle,
    required this.textSpan,
  }) {
    matchIndexes = _buildMatchIndexes(diagnostics, textLength);
  }

  late final List<int> matchIndexes;
  final _spans = <InlineSpan>[];
  int _currentMatchIndex = 0;
  int _currentWindowStart = 0;
  TextStyle? _currentSpanStyle;

  bool get _isCurrentMatchIndexDiagnostic => _currentMatchIndex.isOdd;
  bool get _areAllMatchesProcessed => _currentMatchIndex >= matchIndexes.length;

  static const _errorColor = Color(0xFFFF5252);

  TextStyle get _diagnosticStyle {
    final base = (_currentSpanStyle != null)
        ? rootStyle?.merge(_currentSpanStyle) ?? _currentSpanStyle!
        : rootStyle ?? const TextStyle();

    final existing = base.decoration;
    final combined = existing != null && existing != TextDecoration.none
        ? TextDecoration.combine([existing, TextDecoration.underline])
        : TextDecoration.underline;

    return base.copyWith(
      decoration: combined,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: _errorColor,
      decorationThickness: 2.5,
      backgroundColor: const Color(0x38FF5252),
    );
  }

  TextStyle? get _actualStyle =>
      _isCurrentMatchIndexDiagnostic ? _diagnosticStyle : _currentSpanStyle;

  TextSpan build() {
    if (matchIndexes.isEmpty) {
      return textSpan;
    }

    textSpan.visitChildren((span) {
      if (span is! TextSpan) return true;
      final currentText = span.text;
      if (currentText == null || currentText.isEmpty) {
        return true;
      }
      _currentSpanStyle = span.style;
      _processText(currentText);
      return true;
    });

    return TextSpan(
      children: _spans,
      style: rootStyle,
    );
  }

  void _processText(String text) {
    if (_areAllMatchesProcessed) {
      _spans.add(TextSpan(text: text, style: _currentSpanStyle));
      return;
    }

    final sliceIndex = matchIndexes[_currentMatchIndex] - _currentWindowStart;

    if (sliceIndex < 0 || sliceIndex > text.length) {
      _spans.add(TextSpan(text: text, style: _actualStyle));
      _currentWindowStart += text.length;
      return;
    }

    if (sliceIndex != 0) {
      _spans.add(TextSpan(
        text: text.substring(0, sliceIndex),
        style: _actualStyle,
      ));
    }

    _currentWindowStart = matchIndexes[_currentMatchIndex];
    _currentMatchIndex++;

    if (sliceIndex == text.length) {
      return;
    }

    final textAfter = text.substring(sliceIndex);
    if (textAfter.isNotEmpty) {
      _processText(textAfter);
    }
  }

  static List<int> _buildMatchIndexes(List<Diagnostic> diagnostics, int textLength) {
    if (diagnostics.isEmpty || textLength <= 0) return const [];

    final intervals = <({int start, int end})>[];
    for (final d in diagnostics) {
      if (d.offset < 0 || d.offset >= textLength) continue;
      final start = d.offset;
      final len = d.length > 0 ? d.length : 1;
      final end = (start + len).clamp(start, textLength);
      if (end > start) {
        intervals.add((start: start, end: end));
      }
    }

    if (intervals.isEmpty) return const [];
    intervals.sort((a, b) => a.start.compareTo(b.start));

    final merged = <({int start, int end})>[];
    var current = intervals.first;
    for (var i = 1; i < intervals.length; i++) {
      final next = intervals[i];
      if (next.start <= current.end) {
        current = (
          start: current.start,
          end: next.end > current.end ? next.end : current.end,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    final result = <int>[];
    for (final m in merged) {
      result.add(m.start);
      result.add(m.end);
    }
    return result;
  }
}

import 'package:path/path.dart' as p;

import '../execution/runner_service.dart';
import 'diagnostics.dart';

/// Parses compiler and runtime stderr output into [Diagnostic] instances.
class RuntimeErrorParser {
  static final _pyFilePattern =
      RegExp(r'^\s*File "(?<file>[^"]+)", line (?<line>\d+)(?:, in (?<scope>.*))?');
  static final _pyErrorMsg =
      RegExp(r'^(?<type>[a-zA-Z_][a-zA-Z0-9_]*(?:Error|Exception))(?::\s*(?<msg>.*))?');

  static final _gccWithCol = RegExp(
      r'^(?<file>[^:\n]+):(?<line>\d+):(?<col>\d+):\s*(?:fatal )?(?<type>error|warning):\s*(?<msg>.*)',
      caseSensitive: false);
  static final _gccWithoutCol = RegExp(
      r'^(?<file>[^:\n]+):(?<line>\d+):\s*(?:fatal )?(?<type>error|warning):\s*(?<msg>.*)',
      caseSensitive: false);

  static final _jsLocation =
      RegExp(r'^(?<file>[^:\n\s]+):(?<line>\d+)(?::(?<col>\d+))?$');
  static final _jsStackFrame =
      RegExp(r'^\s*at\s+.*?\((?<file>[^:\n]+):(?<line>\d+):(?<col>\d+)\)');
  static final _jsErrorMsg =
      RegExp(r'^(?<type>[a-zA-Z_][a-zA-Z0-9_]*Error)(?::\s*(?<msg>.*))?');

  /// Parses runner stderr lines into diagnostics for the active document.
  static List<Diagnostic> parse({
    required List<ConsoleLine> lines,
    required String activeFilePath,
    required String fileContent,
  }) {
    if (lines.isEmpty) return const [];

    final activeBase = p.basename(activeFilePath);
    final textLines = fileContent.split('\n');
    final lineStarts = _computeLineStarts(textLines);

    bool matchesActive(String errorFile) {
      if (errorFile == activeFilePath) return true;
      final normErr = p.normalize(errorFile);
      final normAct = p.normalize(activeFilePath);
      if (normErr == normAct) return true;
      if (normAct.endsWith(normErr) || normErr.endsWith(normAct)) return true;
      return p.basename(normErr) == activeBase;
    }

    Diagnostic? makeDiagnostic({
      required int line1Based,
      int? col1Based,
      required String message,
    }) {
      final lineIdx = line1Based - 1;
      if (lineIdx < 0 || lineIdx >= textLines.length) return null;

      final lineStart = lineStarts[lineIdx];
      final lineStr = textLines[lineIdx];

      int offset;
      int length;

      if (col1Based != null && col1Based > 0) {
        final colIdx = col1Based - 1;
        offset = lineStart + colIdx.clamp(0, lineStr.length);
        final wordLen = _wordLengthAt(lineStr, colIdx.clamp(0, lineStr.length));
        length = wordLen > 0 ? wordLen : 1;
      } else {
        final trimmed = lineStr.trim();
        final indent = lineStr.indexOf(trimmed);
        offset = lineStart + (indent >= 0 ? indent : 0);
        length = trimmed.isNotEmpty ? trimmed.length : 1;
      }

      return Diagnostic(
        offset: offset,
        length: length,
        line: lineIdx,
        column: offset - lineStart,
        message: message,
      );
    }

    final results = <Diagnostic>[];

    // Pass 1: GCC / Clang / Dart style errors: "file:line:col: error: msg"
    for (final cl in lines) {
      final text = cl.text.trim();
      if (text.isEmpty) continue;

      final matchCol = _gccWithCol.firstMatch(text);
      if (matchCol != null) {
        final f = matchCol.namedGroup('file')!;
        if (matchesActive(f)) {
          final l = int.parse(matchCol.namedGroup('line')!);
          final c = int.parse(matchCol.namedGroup('col')!);
          final msg = '${matchCol.namedGroup('type')}: ${matchCol.namedGroup('msg')}';
          final d = makeDiagnostic(line1Based: l, col1Based: c, message: msg);
          if (d != null) results.add(d);
        }
        continue;
      }

      final matchNoCol = _gccWithoutCol.firstMatch(text);
      if (matchNoCol != null) {
        final f = matchNoCol.namedGroup('file')!;
        if (matchesActive(f)) {
          final l = int.parse(matchNoCol.namedGroup('line')!);
          final msg = '${matchNoCol.namedGroup('type')}: ${matchNoCol.namedGroup('msg')}';
          final d = makeDiagnostic(line1Based: l, message: msg);
          if (d != null) results.add(d);
        }
        continue;
      }
    }

    if (results.isNotEmpty) {
      return List.unmodifiable(results);
    }

    // Pass 2: Python tracebacks and syntax errors
    int? pyLastLine;
    int? pyCaretCol;
    String? pyError;

    for (var i = 0; i < lines.length; i++) {
      final lineText = lines[i].text;
      final fileMatch = _pyFilePattern.firstMatch(lineText);
      if (fileMatch != null) {
        final f = fileMatch.namedGroup('file')!;
        if (matchesActive(f)) {
          pyLastLine = int.tryParse(fileMatch.namedGroup('line') ?? '');
          pyCaretCol = null;
        }
        continue;
      }

      // Check for Python caret pointer line: e.g. "       ^"
      final trimmed = lineText.trim();
      if (trimmed == '^') {
        final caretIndex = lineText.indexOf('^');
        if (caretIndex >= 0) {
          pyCaretCol = caretIndex + 1;
        }
      }

      final errMatch = _pyErrorMsg.firstMatch(lineText.trim());
      if (errMatch != null) {
        final errType = errMatch.namedGroup('type')!;
        final errMsg = errMatch.namedGroup('msg');
        pyError = errMsg != null && errMsg.isNotEmpty ? '$errType: $errMsg' : errType;
      }
    }

    if (pyLastLine != null) {
      final message = pyError ?? 'Runtime Error';
      final d = makeDiagnostic(
        line1Based: pyLastLine,
        col1Based: pyCaretCol,
        message: message,
      );
      if (d != null) results.add(d);
      return List.unmodifiable(results);
    }

    // Pass 3: Node.js / JavaScript errors
    String? jsError;
    int? jsLine;
    int? jsCol;

    for (final cl in lines) {
      final text = cl.text.trim();
      final errMatch = _jsErrorMsg.firstMatch(text);
      if (errMatch != null) {
        jsError = text;
        continue;
      }

      final locMatch = _jsLocation.firstMatch(text);
      if (locMatch != null) {
        final f = locMatch.namedGroup('file')!;
        if (matchesActive(f)) {
          jsLine = int.tryParse(locMatch.namedGroup('line') ?? '');
          final cStr = locMatch.namedGroup('col');
          if (cStr != null) jsCol = int.tryParse(cStr);
        }
        continue;
      }

      final frameMatch = _jsStackFrame.firstMatch(text);
      if (frameMatch != null && jsLine == null) {
        final f = frameMatch.namedGroup('file')!;
        if (matchesActive(f)) {
          jsLine = int.tryParse(frameMatch.namedGroup('line') ?? '');
          final cStr = frameMatch.namedGroup('col');
          if (cStr != null) jsCol = int.tryParse(cStr);
        }
      }
    }

    if (jsLine != null) {
      final message = jsError ?? 'JavaScript Error';
      final d = makeDiagnostic(
        line1Based: jsLine,
        col1Based: jsCol,
        message: message,
      );
      if (d != null) results.add(d);
    }

    return List.unmodifiable(results);
  }

  static List<int> _computeLineStarts(List<String> lines) {
    final starts = <int>[];
    var current = 0;
    for (final line in lines) {
      starts.add(current);
      current += line.length + 1; // + 1 for '\n'
    }
    return starts;
  }

  static int _wordLengthAt(String line, int col) {
    if (col < 0 || col >= line.length) return 1;
    var end = col;
    while (end < line.length && _isWordChar(line[end])) {
      end++;
    }
    final len = end - col;
    return len > 0 ? len : 1;
  }

  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        (code >= 48 && code <= 57) || // 0-9
        code == 95; // _
  }
}

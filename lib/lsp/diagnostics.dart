import 'source_scan.dart';

class Diagnostic {
  final int offset;
  final int length;
  final int line;
  final int column;
  final String message;

  const Diagnostic({
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.message,
  });

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.offset == offset &&
      other.length == length &&
      other.message == message;

  @override
  int get hashCode => Object.hash(offset, length, message);
}

/// Syntax sanity checks for the two languages the editor ships grammars for.
///
/// Each rule here is one that is cheap, local, and has no false positive on
/// code the editor itself produces. Anything that needs a real parse — type
/// errors, unresolved names — is deliberately out.
class CodeDiagnostics {
  static List<Diagnostic> analyze(String text, String? languageId) {
    final language = sourceLanguageFor(languageId);
    if (language == null) return const [];

    final scanned = scanSource(text, language);
    final found = <Diagnostic>[];
    _unbalancedBrackets(scanned, found);
    _unterminatedStrings(scanned, found);
    if (language == SourceLanguage.python) {
      _pythonIndentation(text, scanned, found);
    }

    found.sort((a, b) => a.offset.compareTo(b.offset));
    return List<Diagnostic>.unmodifiable(found);
  }

  static const Map<String, String> _pairs = {
    ')': '(',
    ']': '[',
    '}': '{',
  };

  static void _unbalancedBrackets(ScannedSource scanned, List<Diagnostic> out) {
    final code = scanned.code;
    final open = <String>[];
    final openAt = <int>[];
    final reported = <int>{};

    void report(int at, String message) {
      final line = scanned.lineOf(at);
      if (!reported.add(line)) return;
      out.add(_diagnostic(scanned, at, 1, message));
    }

    for (var i = 0; i < code.length; i++) {
      final c = code[i];
      if (c == '(' || c == '[' || c == '{') {
        open.add(c);
        openAt.add(i);
      } else if (_pairs.containsKey(c)) {
        // A mismatched opener is dropped, so one stray closer is one diagnostic
        // instead of a cascade against every bracket that follows it.
        if (open.isEmpty || open.last != _pairs[c]) {
          report(i, "Unexpected '$c'");
          if (open.isNotEmpty) {
            open.removeLast();
            openAt.removeLast();
          }
        } else {
          open.removeLast();
          openAt.removeLast();
        }
      }
    }

    for (final at in openAt) {
      report(at, "Unclosed '${code[at]}'");
    }
  }

  static void _unterminatedStrings(ScannedSource scanned, List<Diagnostic> out) {
    for (final literal in scanned.strings) {
      if (!literal.isUnterminated) continue;
      out.add(_diagnostic(
        scanned,
        literal.start,
        1,
        literal.triple ? 'Unterminated string' : 'Unterminated string literal',
      ));
    }
  }

  /// The indentation rules CPython reports as `IndentationError`, checked only
  /// on lines that start a statement: a continuation line inside brackets may
  /// line up under anything, and flagging it is a false positive.
  static void _pythonIndentation(
    String text,
    ScannedSource scanned,
    List<Diagnostic> out,
  ) {
    final codeLines = scanned.code.split('\n');
    final textLines = text.split('\n');
    final levels = <int>[0];
    var previousIndent = 0;
    var previousOpenedBlock = false;
    var previousHasBody = false;

    for (final statement in _statements(codeLines, scanned.linesStartingInLiteral)) {
      final code = codeLines[statement.start];
      if (code.trim().isEmpty) {
        // A docstring is masked away with the rest of the string, but it is a
        // statement, and a class whose whole body is one is not an error.
        final raw = statement.start < textLines.length ? textLines[statement.start] : '';
        if (raw.trim().isNotEmpty && visualIndent(raw) > previousIndent) {
          previousHasBody = true;
        }
        continue;
      }

      final leading = _leading(code);
      final tab = leading.indexOf('\t');
      final space = leading.indexOf(' ');
      if (tab >= 0 && space >= 0) {
        final at = _secondKind(leading);
        out.add(_diagnostic(
          scanned,
          scanned.lineStart(statement.start) + at,
          1,
          'Mixed tabs and spaces in indentation',
        ));
      }

      final indent = visualIndent(code);
      if (indent > previousIndent) {
        if (!previousOpenedBlock) {
          out.add(_diagnostic(
            scanned,
            scanned.lineStart(statement.start) + leading.length,
            indent - previousIndent,
            'Unexpected indent',
          ));
        } else {
          levels.add(indent);
          previousHasBody = true;
        }
      } else if (indent < previousIndent) {
        while (levels.length > 1 && levels.last > indent) {
          levels.removeLast();
        }
        if (levels.last != indent) {
          out.add(_diagnostic(
            scanned,
            scanned.lineStart(statement.start) + leading.length,
            indent,
            'Unindent does not match any outer indentation level',
          ));
        }
      } else if (previousOpenedBlock && !previousHasBody) {
        out.add(_diagnostic(
          scanned,
          scanned.lineStart(statement.start) + leading.length,
          1,
          'Expected an indented block',
        ));
      }

      previousIndent = indent;
      previousOpenedBlock =
          codeLines[statement.end].trimRight().endsWith(':');
      previousHasBody = false;
    }
  }

  /// Consecutive physical lines that form one logical statement: an indented
  /// line after a block opener, a bracketed expression, or a backslash
  /// continuation. The colon that opens a block sits at the end of the last of
  /// them, not necessarily the first.
  static List<_Statement> _statements(
    List<String> codeLines,
    Set<int> linesStartingInLiteral,
  ) {
    final statements = <_Statement>[];
    final starts = _startsStatement(codeLines, linesStartingInLiteral);
    var start = -1;
    for (var i = 0; i < codeLines.length; i++) {
      if (!starts[i]) continue;
      if (start >= 0) statements.add(_Statement(start, i - 1));
      start = i;
    }
    if (start >= 0) statements.add(_Statement(start, codeLines.length - 1));
    return statements;
  }

  /// Whether each line starts a statement, from the masked source.
  ///
  /// A line inside brackets is a continuation, and so is one after a trailing
  /// backslash. Both may be indented by any amount, and treating them as new
  /// statements is what made the check fire on a wrapped `if` condition.
  static List<bool> _startsStatement(
    List<String> codeLines,
    Set<int> linesStartingInLiteral,
  ) {
    final starts = <bool>[];
    var depth = 0;
    var continued = false;
    for (var i = 0; i < codeLines.length; i++) {
      final line = codeLines[i];
      starts.add(
          depth == 0 && !continued && !linesStartingInLiteral.contains(i));
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '(' || c == '[' || c == '{') {
          depth++;
        } else if (c == ')' || c == ']' || c == '}') {
          if (depth > 0) depth--;
        }
      }
      final trimmed = line.trimRight();
      continued = depth == 0 && trimmed.endsWith('\\');
    }
    return starts;
  }

  /// Character index where the indentation switches from one kind of whitespace
  /// to the other.
  static int _secondKind(String leading) {
    final first = leading[0];
    for (var i = 1; i < leading.length; i++) {
      if (leading[i] != first) return i;
    }
    return leading.length - 1;
  }

  static String _leading(String line) {
    var i = 0;
    while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    return line.substring(0, i);
  }

  static Diagnostic _diagnostic(
    ScannedSource scanned,
    int offset,
    int length,
    String message,
  ) {
    final line = scanned.lineOf(offset);
    return Diagnostic(
      offset: offset,
      length: length,
      line: line,
      column: offset - scanned.lineStart(line),
      message: message,
    );
  }
}
class _Statement {
  final int start;
  final int end;

  const _Statement(this.start, this.end);
}

/// Languages the LSP-lite features understand.
enum SourceLanguage {
  python,
  javascript,
  c,
  cpp,
  java,
  json,
}

SourceLanguage? sourceLanguageFor(String? languageId) {
  switch (languageId) {
    case 'python':
      return SourceLanguage.python;
    case 'javascript':
    case 'typescript':
      return SourceLanguage.javascript;
    case 'c':
      return SourceLanguage.c;
    case 'cpp':
    case 'c++':
      return SourceLanguage.cpp;
    case 'java':
      return SourceLanguage.java;
    case 'json':
      return SourceLanguage.json;
    default:
      return null;
  }
}

String languageIdOf(SourceLanguage language) => switch (language) {
      SourceLanguage.python => 'python',
      SourceLanguage.javascript => 'javascript',
      SourceLanguage.c => 'c',
      SourceLanguage.cpp => 'cpp',
      SourceLanguage.java => 'java',
      SourceLanguage.json => 'json',
    };

/// A quoted literal, as the scanner found it.
class StringLiteral {
  final int start;
  final int end;
  final bool triple;

  const StringLiteral(this.start, this.end, this.triple);

  /// The literal never closed before the end of the file.
  bool get isUnterminated => end < 0;
}

/// The source with comments, string bodies and regex literals blanked out.
class ScannedSource {
  /// Same length as the input, so every offset still maps 1:1 onto it.
  final String code;

  final List<StringLiteral> strings;

  /// Offset of the first character of every line.
  final List<int> lineStarts;

  /// Lines that begin inside a multi-line literal. Whatever code follows the
  /// closing quotes on such a line is a continuation, not a new statement.
  final Set<int> linesStartingInLiteral;

  ScannedSource(
    this.code,
    this.strings,
    this.lineStarts,
    this.linesStartingInLiteral,
  );

  /// Zero-based line of [offset].
  int lineOf(int offset) => lineOfOffset(lineStarts, offset);

  int lineStart(int line) {
    if (line < 0) return 0;
    if (line >= lineStarts.length) return code.length;
    return lineStarts[line];
  }
}

/// Zero-based line of [offset] in a list of line-start offsets.
int lineOfOffset(List<int> lineStarts, int offset) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (lineStarts[mid] <= offset) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

/// Tab stops every 8 columns, which is what CPython reports in its own
/// indentation errors. Shared with the outline parser so a symbol and its
/// diagnostic land on the same column.
int visualIndent(String line) {
  var column = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == ' ') {
      column++;
    } else if (c == '\t') {
      column += 8 - (column % 8);
    } else {
      break;
    }
  }
  return column;
}

/// Blanks everything that is not code, so the regex and bracket passes below
/// cannot be fooled by a quote inside a string or a brace inside a comment.
///
/// The result keeps the input's length and line breaks, which is what lets
/// callers keep reporting original offsets and line numbers.
ScannedSource scanSource(String text, SourceLanguage language) {
  final out = StringBuffer();
  final strings = <StringLiteral>[];
  final lineStarts = <int>[0];
  final n = text.length;
  var i = 0;
  var lastCode = '';
  var lastWord = '';

  void blank(int from, int to) {
    for (var k = from; k < to && k < n; k++) {
      if (text[k] == '\n') {
        lineStarts.add(k + 1);
        out.write('\n');
      } else {
        out.write(' ');
      }
    }
  }

  while (i < n) {
    final c = text[i];

    if (c == '\n') {
      lineStarts.add(i + 1);
      out.write('\n');
      lastCode = '';
      lastWord = '';
      i++;
      continue;
    }

    if (language == SourceLanguage.python) {
      if (c == '#') {
        var j = i;
        while (j < n && text[j] != '\n') {
          j++;
        }
        blank(i, j);
        i = j;
        continue;
      }
    } else {
      if (c == '/' && i + 1 < n && text[i + 1] == '/') {
        var j = i;
        while (j < n && text[j] != '\n') {
          j++;
        }
        blank(i, j);
        i = j;
        continue;
      }
      if (c == '/' && i + 1 < n && text[i + 1] == '*') {
        var j = i + 2;
        while (j + 1 < n && !(text[j] == '*' && text[j + 1] == '/')) {
          j++;
        }
        j = j + 1 < n ? j + 2 : n;
        blank(i, j);
        i = j;
        continue;
      }
      if (c == '/' && _startsRegex(lastCode, lastWord)) {
        final end = _regexEnd(text, i);
        if (end > 0) {
          blank(i, end);
          i = end;
          lastCode = 'x';
          lastWord = '';
          continue;
        }
      }
    }

    if (c == '"' || c == "'" || (language == SourceLanguage.javascript && c == '`')) {
      final triple = language == SourceLanguage.python &&
          i + 2 < n &&
          text[i + 1] == c &&
          text[i + 2] == c;
      var j = i + (triple ? 3 : 1);
      var closed = false;
      while (j < n) {
        final d = text[j];
        if (d == '\\' && !triple) {
          j = j + 2 > n ? n : j + 2;
          continue;
        }
        if (triple) {
          if (d == c && j + 2 < n && text[j + 1] == c && text[j + 2] == c) {
            j += 3;
            closed = true;
            break;
          }
        } else if (d == c) {
          j++;
          closed = true;
          break;
        } else if (d == '\n' && c != '`') {
          break;
        }
        j++;
      }
      strings.add(StringLiteral(i, closed ? j : -1, triple));
      blank(i, j);
      i = j;
      lastCode = 'x';
      lastWord = '';
      continue;
    }

    out.write(c);
    final lower = c.toLowerCase();
    if (lower.codeUnitAt(0) >= 97 && lower.codeUnitAt(0) <= 122) {
      lastWord += lower;
    } else if (c.trim().isNotEmpty) {
      lastWord = '';
    }
    if (c.trim().isNotEmpty) lastCode = c;
    i++;
  }

  final inside = <int>{};
  for (final literal in strings) {
    final from = lineOfOffset(lineStarts, literal.start);
    final last = literal.isUnterminated ? text.length - 1 : literal.end - 1;
    final to = lineOfOffset(lineStarts, last);
    for (var line = from + 1; line <= to; line++) {
      inside.add(line);
    }
  }

  return ScannedSource(out.toString(), strings, lineStarts, inside);
}

/// Index just past a regex literal that starts at [start], or -1 when the slash
/// is a division.
int _regexEnd(String text, int start) {
  final n = text.length;
  var j = start + 1;
  var inClass = false;
  while (j < n) {
    final d = text[j];
    if (d == '\n') return -1;
    if (d == '\\') {
      j += 2;
      continue;
    }
    if (inClass) {
      if (d == ']') inClass = false;
    } else if (d == '[') {
      inClass = true;
    } else if (d == '/') {
      return j + 1;
    }
    j++;
  }
  return -1;
}

/// A slash starts a regex only where a value may start. Treating `a / b` as a
/// regex would swallow the rest of the line, quote and all.
bool _startsRegex(String lastCode, String lastWord) {
  if (lastCode.isEmpty) return true;
  if ('([{=,:;!&|?+-*%^~<>'.contains(lastCode)) return true;
  return const {'return', 'typeof', 'case', 'in', 'of', 'new', 'delete', 'void', 'do', 'else', 'yield', 'await'}
      .contains(lastWord);
}
import 'source_scan.dart';

enum SymbolKind { class_, method, function, variable }

class OutlineSymbol {
  final String name;
  final SymbolKind kind;
  final String detail;

  /// Zero-based line of the declaration.
  final int line;

  /// Zero-based column of the name.
  final int column;

  /// Character offset of the name, which is what the editor puts the caret on.
  final int offset;

  /// Zero-based line of the last line of the declaration's block.
  final int endLine;

  final List<OutlineSymbol> children;

  const OutlineSymbol({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
    required this.offset,
    required this.endLine,
    this.detail = '',
    this.children = const [],
  });

  bool get isContainer => kind == SymbolKind.class_;

  @override
  String toString() => '$name ($kind) L${line + 1}';
}

/// One pass of regex and indentation work over the masked source.
///
/// There is no parser and no language server: this is enough to draw an outline
/// and to find a definition, and it degrades to "no symbols" on a file it does
/// not understand instead of throwing.
class OutlineParser {
  static List<OutlineSymbol> parse(String text, String? languageId) {
    final language = sourceLanguageFor(languageId);
    if (language == null) return const [];
    final scanned = scanSource(text, language);
    return switch (language) {
      SourceLanguage.python => _python(scanned),
      SourceLanguage.javascript => _javascript(scanned),
    };
  }

  static final RegExp _pythonDef =
      RegExp(r'^(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(');
  static final RegExp _pythonClass = RegExp(r'^class\s+([A-Za-z_]\w*)');

  static List<OutlineSymbol> _python(ScannedSource scanned) {
    final lines = scanned.code.split('\n');
    final drafts = <_Draft>[];
    final stack = <_Draft>[];
    var lastContentLine = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;
      lastContentLine = i;

      final indent = visualIndent(line);
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }

      final classMatch = _pythonClass.firstMatch(trimmed);
      final match = classMatch ?? _pythonDef.firstMatch(trimmed);
      if (match == null) continue;

      final isClass = classMatch != null;
      final name = match.group(1)!;
      final column = indent + _nameOffsetIn(match.group(0)!, name);
      final draft = _Draft(
        name: name,
        kind: isClass
            ? SymbolKind.class_
            : (stack.isNotEmpty && stack.last.kind == SymbolKind.class_)
                ? SymbolKind.method
                : SymbolKind.function,
        line: i,
        column: column,
        offset: scanned.lineStart(i) + column,
        indent: indent,
        detail: isClass ? 'class' : 'def',
      );
      drafts.add(draft);
      stack.add(draft);
    }

    _closeBlocks(drafts, lastContentLine);
    return _nest(drafts);
  }

  static final RegExp _jsClass = RegExp(r'^(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)');
  static final RegExp _jsFunction =
      RegExp(r'^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\(');
  static final RegExp _jsDeclaration =
      RegExp(r'^(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(.*)$');

  static List<OutlineSymbol> _javascript(ScannedSource scanned) {
    final lines = scanned.code.split('\n');
    final drafts = <_Draft>[];
    var lastContentLine = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;
      lastContentLine = i;

      // Classes and `const`/`let` are only top-level declarations; the same
      // text indented is a local inside a function body, not a symbol.
      final topLevel = line.length == trimmed.length;
      final classMatch = topLevel ? _jsClass.firstMatch(trimmed) : null;
      final functionMatch =
          classMatch == null ? _jsFunction.firstMatch(trimmed) : null;
      final declaration = classMatch == null && functionMatch == null && topLevel
          ? _jsDeclaration.firstMatch(trimmed)
          : null;

      final match = classMatch ?? functionMatch ?? declaration;
      if (match == null) continue;

      final name = match.group(1)!;
      final column =
          (line.length - trimmed.length) + _nameOffsetIn(match.group(0)!, name);

      var kind = SymbolKind.variable;
      var detail = 'variable';
      if (classMatch != null) {
        kind = SymbolKind.class_;
        detail = 'class';
      } else if (functionMatch != null) {
        kind = SymbolKind.function;
        detail = 'function';
      } else {
        final rhs = declaration!.group(2)!;
        if (rhs.startsWith('function') ||
            rhs.startsWith('async function') ||
            rhs.contains('=>')) {
          kind = SymbolKind.function;
          detail = 'function';
        }
      }

      final end = _blockEnd(scanned, i, column);
      drafts.add(_Draft(
        name: name,
        kind: kind,
        line: i,
        column: column,
        offset: scanned.lineStart(i) + column,
        indent: 0,
        detail: detail,
        endLine: end,
      ));
    }

    _closeBlocks(drafts, lastContentLine);
    return _nest(drafts);
  }

  /// Where [name] sits inside [matched].
  ///
  /// `RegExpMatch` exposes the start of the whole match but not of a group, and
  /// `indexOf` alone is wrong for a declaration whose keyword contains the name
  /// (`const s = 1`).
  static int _nameOffsetIn(String matched, String name) {
    var from = 0;
    while (from <= matched.length) {
      final at = matched.indexOf(name, from);
      if (at < 0) return matched.length;
      final before = at == 0 ? '' : matched[at - 1];
      final after = at + name.length < matched.length ? matched[at + name.length] : '';
      if (!_isIdentifierChar(before) && !_isIdentifierChar(after)) return at;
      from = at + 1;
    }
    return matched.length;
  }

  static bool _isIdentifierChar(String c) {
    if (c.isEmpty) return false;
    final unit = c.codeUnitAt(0);
    return (unit >= 65 && unit <= 90) ||
        (unit >= 97 && unit <= 122) ||
        (unit >= 48 && unit <= 57) ||
        unit == 95 ||
        unit == 36;
  }

  /// Line of the `}` that closes the block opened on [line], when there is one.
  static int _blockEnd(ScannedSource scanned, int line, int from) {
    final code = scanned.code;
    final start = scanned.lineStart(line) + from;
    final open = code.indexOf('{', start);
    if (open < 0) return -1;
    if (scanned.lineOf(open) != line) return -1;

    var depth = 0;
    for (var i = open; i < code.length; i++) {
      if (code[i] == '{') {
        depth++;
      } else if (code[i] == '}') {
        depth--;
        if (depth == 0) return scanned.lineOf(i);
      }
    }
    return -1;
  }

  /// A declaration's block runs to the line before the next one at the same or
  /// a shallower level, or to the end of the file.
  static void _closeBlocks(List<_Draft> drafts, int lastContentLine) {
    for (var a = 0; a < drafts.length; a++) {
      if (drafts[a].endLine >= 0) continue;
      var end = lastContentLine;
      for (var b = a + 1; b < drafts.length; b++) {
        if (drafts[b].indent <= drafts[a].indent) {
          end = drafts[b].line - 1;
          break;
        }
      }
      drafts[a].endLine = end;
    }
  }

  static List<OutlineSymbol> _nest(List<_Draft> drafts) {
    final roots = <_Draft>[];
    final stack = <_Draft>[];
    for (final draft in drafts) {
      while (stack.isNotEmpty && stack.last.indent >= draft.indent) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(draft);
      } else {
        stack.last.children.add(draft);
      }
      stack.add(draft);
    }
    return roots.map(_symbol).toList(growable: false);
  }

  static OutlineSymbol _symbol(_Draft d) => OutlineSymbol(
        name: d.name,
        kind: d.kind,
        line: d.line,
        column: d.column,
        offset: d.offset,
        endLine: d.endLine,
        detail: d.detail,
        children: d.children.map(_symbol).toList(growable: false),
      );
}

class _Draft {
  final String name;
  final SymbolKind kind;
  final int line;
  final int column;
  final int offset;
  final int indent;
  final String detail;
  final List<_Draft> children = [];
  int endLine;

  _Draft({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
    required this.offset,
    required this.indent,
    required this.detail,
    this.endLine = -1,
  });
}
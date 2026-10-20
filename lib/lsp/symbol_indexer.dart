import 'autocomplete_item.dart';

class SymbolIndexer {
  static List<AutocompleteItem> index(String text, String? languageId) {
    final items = <AutocompleteItem>{};
    switch (languageId) {
      case 'python':
        items.addAll(_extractPython(text));
      case 'javascript':
      case 'typescript':
        items.addAll(_extractJs(text));
      case 'java':
        items.addAll(_extractJava(text));
      case 'c':
      case 'cpp':
        items.addAll(_extractC(text));
      case 'dart':
        items.addAll(_extractDart(text));
      default:
        items.addAll(_extractGeneric(text));
    }
    return items.toList();
  }

  static final _pythonDef = RegExp(r'^\s*def\s+(\w+)\s*\(([^)]*)\)', multiLine: true);
  static final _pythonClass = RegExp(r'^\s*class\s+(\w+)', multiLine: true);
  static final _pythonVar = RegExp(r'^(\w+)\s*=', multiLine: true);

  static Set<AutocompleteItem> _extractPython(String text) {
    final items = <AutocompleteItem>{};
    for (final m in _pythonDef.allMatches(text)) {
      final name = m.group(1)!;
      final params = m.group(2)!;
      items.add(AutocompleteItem(
        label: '$name()',
        insertText: name,
        kind: AutocompleteKind.function_,
        detail: 'def $name($params)',
      ));
    }
    for (final m in _pythonClass.allMatches(text)) {
      final name = m.group(1)!;
      items.add(AutocompleteItem(
        label: name,
        insertText: name,
        kind: AutocompleteKind.class_,
        detail: 'class $name',
      ));
    }
    for (final m in _pythonVar.allMatches(text)) {
      final name = m.group(1)!;
      if (name.length > 1 && !name.startsWith('_')) {
        items.add(AutocompleteItem(
          label: name,
          insertText: name,
          kind: AutocompleteKind.variable,
          detail: 'variable',
        ));
      }
    }
    return items;
  }

  static final _jsFn = RegExp(
      r'(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:function|\([^)]*\)\s*=>))',
      multiLine: true);
  static final _jsClass = RegExp(r'\bclass\s+(\w+)', multiLine: true);
  static final _jsVar = RegExp(r'(?:const|let|var)\s+(\w+)\s*=\s*(?![=>{(])',
      multiLine: true);

  static Set<AutocompleteItem> _extractJs(String text) {
    final items = <AutocompleteItem>{};
    for (final m in _jsFn.allMatches(text)) {
      final name = m.group(1) ?? m.group(2);
      if (name != null) {
        items.add(AutocompleteItem(
          label: '$name()',
          insertText: name,
          kind: AutocompleteKind.function_,
          detail: 'function',
        ));
      }
    }
    for (final m in _jsClass.allMatches(text)) {
      final name = m.group(1)!;
      items.add(AutocompleteItem(
        label: name,
        insertText: name,
        kind: AutocompleteKind.class_,
        detail: 'class',
      ));
    }
    for (final m in _jsVar.allMatches(text)) {
      final name = m.group(1)!;
      if (name.length > 1) {
        items.add(AutocompleteItem(
          label: name,
          insertText: name,
          kind: AutocompleteKind.variable,
          detail: 'variable',
        ));
      }
    }
    return items;
  }

  static final _javaMethod =
      RegExp(r'(?:public|private|protected|static|void|[\w<>]+)\s+(\w+)\s*\(', multiLine: true);
  static final _javaClass = RegExp(r'\bclass\s+(\w+)', multiLine: true);

  static Set<AutocompleteItem> _extractJava(String text) {
    final items = <AutocompleteItem>{};
    for (final m in _javaClass.allMatches(text)) {
      items.add(AutocompleteItem(
        label: m.group(1)!,
        insertText: m.group(1)!,
        kind: AutocompleteKind.class_,
        detail: 'class',
      ));
    }
    for (final m in _javaMethod.allMatches(text)) {
      final name = m.group(1)!;
      if (name.length > 2 && !_javaKeywords.contains(name)) {
        items.add(AutocompleteItem(
          label: '$name()',
          insertText: name,
          kind: AutocompleteKind.function_,
          detail: 'method',
        ));
      }
    }
    return items;
  }

  static const _javaKeywords = {'if', 'else', 'for', 'while', 'do', 'switch', 'try', 'catch', 'new', 'return', 'class', 'void', 'int', 'long', 'double', 'boolean', 'String'};

  // `[^;]*` between the name and `)`, retried from every start position, is
  // O(n^2) on a long `;`-free line. The bounded repetition is enough to capture
  // a parameter list and parses in linear time.
  static final _cFn = RegExp(
      r'(?:int|void|char|float|double|long|short|unsigned|auto|[\w*]+)\s+(\w+)\s*\([^;]{0,120}\)\s*\{',
      multiLine: true);

  static Set<AutocompleteItem> _extractC(String text) {
    final items = <AutocompleteItem>{};
    for (final m in _cFn.allMatches(text)) {
      final name = m.group(1)!;
      if (!_cKeywords.contains(name)) {
        items.add(AutocompleteItem(
          label: '$name()',
          insertText: name,
          kind: AutocompleteKind.function_,
          detail: 'function',
        ));
      }
    }
    return items;
  }

  static const _cKeywords = {'if', 'else', 'for', 'while', 'do', 'switch', 'return', 'main', 'int', 'void', 'char'};

  static final _dartFn = RegExp(r'(?:Future|void|[\w<>?]+)\s+(\w+)\s*\(', multiLine: true);
  static final _dartClass = RegExp(r'\bclass\s+(\w+)', multiLine: true);
  static final _dartVar = RegExp(r'(?:var|final|late|const)\s+(?:\w+\s+)?(\w+)\s*=', multiLine: true);

  static Set<AutocompleteItem> _extractDart(String text) {
    final items = <AutocompleteItem>{};
    for (final m in _dartClass.allMatches(text)) {
      items.add(AutocompleteItem(
        label: m.group(1)!,
        insertText: m.group(1)!,
        kind: AutocompleteKind.class_,
        detail: 'class',
      ));
    }
    for (final m in _dartFn.allMatches(text)) {
      final name = m.group(1)!;
      if (name.length > 2 && !_dartKeywordsSet.contains(name)) {
        items.add(AutocompleteItem(
          label: '$name()',
          insertText: name,
          kind: AutocompleteKind.function_,
          detail: 'function',
        ));
      }
    }
    for (final m in _dartVar.allMatches(text)) {
      final name = m.group(1)!;
      if (name.length > 1) {
        items.add(AutocompleteItem(
          label: name,
          insertText: name,
          kind: AutocompleteKind.variable,
          detail: 'variable',
        ));
      }
    }
    return items;
  }

  static const _dartKeywordsSet = {'if', 'else', 'for', 'while', 'do', 'switch', 'return', 'build', 'void', 'int', 'bool', 'String'};

  static final _genericWord = RegExp(r'\b([a-zA-Z_]\w{2,})\b');

  static Set<AutocompleteItem> _extractGeneric(String text) {
    final seen = <String>{};
    final items = <AutocompleteItem>{};
    for (final m in _genericWord.allMatches(text)) {
      final word = m.group(1)!;
      if (seen.add(word)) {
        items.add(AutocompleteItem(
          label: word,
          insertText: word,
          kind: AutocompleteKind.variable,
          detail: 'word',
        ));
      }
    }
    return items;
  }
}

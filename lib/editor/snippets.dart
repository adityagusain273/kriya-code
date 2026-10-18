import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart';

class Snippet {
  final String prefix;
  final String label;
  final String body;
  final String? description;
  final List<String>? scope;

  const Snippet({
    required this.prefix,
    required this.label,
    required this.body,
    this.description,
    this.scope,
  });

  factory Snippet.fromJson(Map<String, dynamic> json) {
    final body = json['body'];
    String bodyStr;
    if (body is List) {
      bodyStr = body.join('\n');
    } else {
      bodyStr = body.toString();
    }
    return Snippet(
      prefix: json['prefix'] as String? ?? '',
      label: json['label'] as String? ?? json['prefix'] as String? ?? '',
      body: bodyStr,
      description: json['description'] as String?,
      scope: (json['scope'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'prefix': prefix,
    'label': label,
    'body': body.split('\n'),
    if (description != null) 'description': description,
    if (scope != null) 'scope': scope,
  };
}

class SnippetService {
  static final Map<String, List<Snippet>> _builtInSnippets = {
    'c': const [
      Snippet(prefix: 'main', label: 'Main function', body: 'int main() {\n\treturn 0;\n}'),
      Snippet(prefix: 'inc', label: '#include', body: '#include <stdio.h>'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for (int i = 0; i < n; i++) {\n\t\n}'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if (condition) {\n\t\n}'),
      Snippet(prefix: 'while', label: 'While loop', body: 'while (condition) {\n\t\n}'),
      Snippet(prefix: 'printf', label: 'printf', body: 'printf("%s\\n", arg);'),
      Snippet(prefix: 'switch', label: 'Switch', body: 'switch (value) {\n\tcase val:\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}'),
      Snippet(prefix: 'struct', label: 'Struct', body: 'struct Name {\n\tint field;\n};'),
      Snippet(prefix: 'def', label: '#define', body: '#define NAME value'),
    ],
    'cpp': const [
      Snippet(prefix: 'main', label: 'Main function', body: 'int main() {\n\t\n\treturn 0;\n}'),
      Snippet(prefix: 'inc', label: '#include', body: '#include <iostream>'),
      Snippet(prefix: 'cin', label: 'cin', body: 'std::cin >> var;'),
      Snippet(prefix: 'cout', label: 'cout', body: 'std::cout << "text" << std::endl;'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for (int i = 0; i < n; i++) {\n\t\n}'),
      Snippet(prefix: 'forr', label: 'Range for', body: 'for (const auto& item : container) {\n\t\n}'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if (condition) {\n\t\n}'),
      Snippet(prefix: 'class', label: 'Class', body: 'class Name {\npublic:\n\tName() {}\n};'),
      Snippet(prefix: 'vec', label: 'Vector', body: 'std::vector<int> name;'),
      Snippet(prefix: 'map', label: 'Map', body: 'std::map<key, value> name;'),
      Snippet(prefix: 'func', label: 'Function', body: 'void name() {\n\t\n}'),
      Snippet(prefix: 'lambda', label: 'Lambda', body: '[capture](params) { body }'),
      Snippet(prefix: 'switch', label: 'Switch', body: 'switch (value) {\n\tcase val:\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}'),
    ],
    'python': const [
      Snippet(prefix: 'main', label: 'Main guard', body: 'if __name__ == "__main__":\n\tmain()'),
      Snippet(prefix: 'def', label: 'Function', body: 'def name(params):\n\tpass'),
      Snippet(prefix: 'class', label: 'Class', body: 'class Name:\n\tdef __init__(self):\n\t\tpass'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for item in iterable:\n\tpass'),
      Snippet(prefix: 'forr', label: 'Range for', body: 'for i in range(n):\n\tpass'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if condition:\n\tpass'),
      Snippet(prefix: 'ife', label: 'If-else', body: 'if condition:\n\tpass\nelse:\n\tpass'),
      Snippet(prefix: 'while', label: 'While loop', body: 'while condition:\n\tpass'),
      Snippet(prefix: 'try', label: 'Try-except', body: 'try:\n\tpass\nexcept Exception as e:\n\tpass'),
      Snippet(prefix: 'with', label: 'With statement', body: 'with expression as var:\n\tpass'),
      Snippet(prefix: 'print', label: 'Print', body: 'print("text")'),
      Snippet(prefix: 'list', label: 'List comprehension', body: '[expr for x in iterable]'),
    ],
    'dart': const [
      Snippet(prefix: 'main', label: 'Main function', body: 'void main() {\n\t\n}'),
      Snippet(prefix: 'stless', label: 'StatelessWidget', body: 'class Name extends StatelessWidget {\n\tconst Name({super.key});\n\n\t@override\n\tWidget build(BuildContext context) {\n\t\treturn SizedBox();\n\t}\n}'),
      Snippet(prefix: 'stful', label: 'StatefulWidget', body: 'class Name extends StatefulWidget {\n\tconst Name({super.key});\n\n\t@override\n\tState<Name> createState() => _NameState();\n}\n\nclass _NameState extends State<Name> {\n\t@override\n\tWidget build(BuildContext context) {\n\t\treturn SizedBox();\n\t}\n}'),
      Snippet(prefix: 'class', label: 'Class', body: 'class Name {\n\tName();\n}'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for (var i = 0; i < n; i++) {\n\t\n}'),
      Snippet(prefix: 'forin', label: 'For-in loop', body: 'for (final item in list) {\n\t\n}'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if (condition) {\n\t\n}'),
      Snippet(prefix: 'ife', label: 'If-else', body: 'if (condition) {\n\t\n} else {\n\t\n}'),
      Snippet(prefix: 'async', label: 'Async function', body: 'Future<void> name() async {\n\t\n}'),
      Snippet(prefix: 'try', label: 'Try-catch', body: 'try {\n\t\n} on Exception catch (e) {\n\t\n}'),
    ],
    'java': const [
      Snippet(prefix: 'main', label: 'Main method', body: 'public static void main(String[] args) {\n\t\n}'),
      Snippet(prefix: 'class', label: 'Class', body: 'public class Name {\n\t\n}'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for (int i = 0; i < n; i++) {\n\t\n}'),
      Snippet(prefix: 'foreach', label: 'For-each', body: 'for (Type item : list) {\n\t\n}'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if (condition) {\n\t\n}'),
      Snippet(prefix: 'sout', label: 'System.out.println', body: 'System.out.println("text");'),
      Snippet(prefix: 'try', label: 'Try-catch', body: 'try {\n\t\n} catch (Exception e) {\n\t\n}'),
    ],
    'javascript': const [
      Snippet(prefix: 'func', label: 'Function', body: 'function name() {\n\t\n}'),
      Snippet(prefix: 'afunc', label: 'Arrow function', body: 'const name = () => {\n\t\n};'),
      Snippet(prefix: 'const', label: 'Const', body: 'const name = value;'),
      Snippet(prefix: 'let', label: 'Let', body: 'let name = value;'),
      Snippet(prefix: 'for', label: 'For loop', body: 'for (let i = 0; i < n; i++) {\n\t\n}'),
      Snippet(prefix: 'foreach', label: 'For-each', body: 'array.forEach((item) => {\n\t\n});'),
      Snippet(prefix: 'if', label: 'If statement', body: 'if (condition) {\n\t\n}'),
      Snippet(prefix: 'ife', label: 'If-else', body: 'if (condition) {\n\t\n} else {\n\t\n}'),
      Snippet(prefix: 'async', label: 'Async function', body: 'async function name() {\n\t\n}'),
      Snippet(prefix: 'await', label: 'Await', body: 'const result = await promise;'),
    ],
    'typescript': const [
      Snippet(prefix: 'func', label: 'Function', body: 'function name(): void {\n\t\n}'),
      Snippet(prefix: 'afunc', label: 'Arrow function', body: 'const name = (): void => {\n\t\n};'),
      Snippet(prefix: 'interface', label: 'Interface', body: 'interface Name {\n\tproperty: type;\n}'),
      Snippet(prefix: 'type', label: 'Type alias', body: 'type Name = type;'),
      Snippet(prefix: 'class', label: 'Class', body: 'class Name {\n\tconstructor() {\n\t\t\n\t}\n}'),
    ],
    'html': const [
      Snippet(prefix: 'html5', label: 'HTML5 Boilerplate', body: '<!DOCTYPE html>\n<html lang="en">\n<head>\n\t<meta charset="UTF-8">\n\t<meta name="viewport" content="width=device-width, initial-scale=1.0">\n\t<title>\${1:Document}</title>\n</head>\n<body>\n\t\${0}\n</body>\n</html>'),
      Snippet(prefix: 'div', label: 'Div', body: '<div>\n\t\${0}\n</div>'),
      Snippet(prefix: 'script', label: 'Script', body: '<script>\n\t\${0}\n</script>'),
    ],
    'css': const [
      Snippet(prefix: 'rule', label: 'CSS Rule', body: 'selector {\n\tproperty: value;\n}'),
      Snippet(prefix: 'flex', label: 'Flexbox', body: 'display: flex;\njustify-content: center;\nalign-items: center;'),
      Snippet(prefix: 'grid', label: 'Grid', body: 'display: grid;\ngrid-template-columns: repeat(auto-fit, minmax(200px, 1fr));\ngap: 1rem;'),
    ],
  };

  static final Map<String, List<Snippet>> _loadedSnippets = {};
  static bool _assetsLoaded = false;

  static Future<void> loadAssets() async {
    if (_assetsLoaded) return;
    final manifest = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = jsonDecode(manifest);
    
    for (final key in manifestMap.keys) {
      if (key.startsWith('assets/snippets/') && key.endsWith('.json')) {
        final languageId = key.split('/').last.replaceAll('.json', '');
        try {
          final content = await rootBundle.loadString(key);
          final Map<String, dynamic> json = jsonDecode(content);
          final snippets = <Snippet>[];
          
          for (final entry in json.entries) {
            final snippetData = Map<String, dynamic>.from(entry.value);
            snippetData['prefix'] = entry.key;
            snippets.add(Snippet.fromJson(snippetData));
          }
          
          _loadedSnippets[languageId] = snippets;
        } catch (e) {
          log('Failed to load snippets for $languageId: $e');
        }
      }
    }
    _assetsLoaded = true;
  }

  static List<Snippet> forLanguage(String? languageId) {
    if (languageId == null) return [];
    
    final assetSnippets = _loadedSnippets[languageId] ?? [];
    final builtInSnippets = _builtInSnippets[languageId] ?? [];
    
    // Merge, with asset snippets taking precedence
    final map = <String, Snippet>{};
    for (final s in builtInSnippets) {
      map[s.prefix] = s;
    }
    for (final s in assetSnippets) {
      map[s.prefix] = s;
    }
    
    return map.values.toList();
  }

  static List<Snippet> search(String? languageId, String query) {
    final all = forLanguage(languageId);
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return all.where((s) =>
      s.prefix.toLowerCase().contains(q) ||
      s.label.toLowerCase().contains(q) ||
      (s.description?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  static String applySnippet(String template, {Map<String, String>? variables}) {
    String result = template;
    
    // Handle tab stops: \${1:default}, \${2}, etc.
    while (result.contains('\$')) {
      final regex = RegExp(r'\$\{(\d+)(?::([^}]*))?\}');
      final match = regex.firstMatch(result);
      if (match == null) break;
      
      final placeholder = variables?[match.group(1)] ?? match.group(2) ?? '';
      result = result.replaceFirst(regex, placeholder);
    }
    
    // Handle \$0 (final cursor position)
    result = result.replaceAll(r'$0', '');
    
    // Handle \$1, \$2, etc. (mirrored tab stops)
    for (int i = 1; i <= 10; i++) {
      result = result.replaceAll('\$$i', '');
    }
    
    return result;
  }

  /// Find snippet matching the prefix at cursor position
  static Snippet? findMatchingSnippet(String? languageId, String text, int cursorOffset) {
    final snippets = forLanguage(languageId);
    if (snippets.isEmpty) return null;
    
    // Find the word before cursor
    int start = cursorOffset - 1;
    while (start >= 0 && _isWordChar(text[start])) {
      start--;
    }
    final prefix = text.substring(start + 1, cursorOffset);
    
    if (prefix.isEmpty) return null;
    
    // Find snippet with matching prefix
    for (final snippet in snippets) {
      if (snippet.prefix == prefix) {
        return snippet;
      }
    }
    return null;
  }

  static bool _isWordChar(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // A-Z
           (code >= 97 && code <= 122) || // a-z
           (code >= 48 && code <= 57) || // 0-9
           code == 95; // _
  }
}
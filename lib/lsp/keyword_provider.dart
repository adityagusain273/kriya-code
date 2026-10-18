import 'autocomplete_item.dart';

class KeywordProvider {
  static List<AutocompleteItem> forLanguage(String? languageId) {
    final kws = _keywords[languageId] ?? [];
    final snips = _snippets[languageId] ?? [];
    return [
      ...kws.map((k) => AutocompleteItem(
            label: k,
            insertText: k,
            kind: AutocompleteKind.keyword,
            detail: 'keyword',
          )),
      ...snips.map((s) => AutocompleteItem(
            label: s.label,
            insertText: s.insertText,
            kind: AutocompleteKind.snippet,
            detail: 'snippet',
          )),
    ];
  }

  static const _keywords = <String, List<String>>{
    'python': [
      'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
      'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
      'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
      'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return',
      'try', 'while', 'with', 'yield',
      'print', 'len', 'range', 'enumerate', 'zip', 'map', 'filter',
      'sorted', 'reversed', 'list', 'dict', 'set', 'tuple', 'str', 'int',
      'float', 'bool', 'type', 'isinstance', 'hasattr', 'getattr', 'setattr',
      'open', 'super', 'property', 'staticmethod', 'classmethod',
    ],
    'javascript': [
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'finally',
      'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new',
      'of', 'return', 'static', 'super', 'switch', 'this', 'throw', 'try',
      'typeof', 'var', 'void', 'while', 'yield', 'async', 'await',
      'undefined', 'null', 'true', 'false',
      'console', 'window', 'document', 'JSON', 'Math', 'Date', 'Array',
      'Object', 'Promise', 'fetch', 'setTimeout', 'setInterval', 'require',
      'module', 'exports', 'process',
    ],
    'typescript': [
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'finally',
      'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new',
      'of', 'return', 'static', 'super', 'switch', 'this', 'throw', 'try',
      'typeof', 'var', 'void', 'while', 'yield', 'async', 'await',
      'interface', 'type', 'enum', 'namespace', 'abstract', 'implements',
      'declare', 'readonly', 'private', 'protected', 'public', 'as', 'is',
      'keyof', 'infer', 'never', 'unknown', 'any', 'string', 'number',
      'boolean', 'symbol', 'object', 'undefined', 'null',
    ],
    'java': [
      'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
      'char', 'class', 'const', 'continue', 'default', 'do', 'double',
      'else', 'enum', 'extends', 'final', 'finally', 'float', 'for',
      'goto', 'if', 'implements', 'import', 'instanceof', 'int',
      'interface', 'long', 'native', 'new', 'package', 'private',
      'protected', 'public', 'return', 'short', 'static', 'strictfp',
      'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
      'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
      'String', 'System', 'Integer', 'Double', 'Boolean', 'ArrayList',
      'HashMap', 'List', 'Map', 'Set', 'Optional',
    ],
    'c': [
      'auto', 'break', 'case', 'char', 'const', 'continue', 'default',
      'do', 'double', 'else', 'enum', 'extern', 'float', 'for', 'goto',
      'if', 'inline', 'int', 'long', 'register', 'restrict', 'return',
      'short', 'signed', 'sizeof', 'static', 'struct', 'switch', 'typedef',
      'union', 'unsigned', 'void', 'volatile', 'while', 'NULL',
      'printf', 'scanf', 'malloc', 'free', 'memcpy', 'strlen', 'strcmp',
      '#include', '#define', '#ifndef', '#endif', '#pragma',
    ],
    'cpp': [
      'alignas', 'alignof', 'and', 'asm', 'auto', 'bitand', 'bitor',
      'bool', 'break', 'case', 'catch', 'char', 'class', 'compl',
      'const', 'constexpr', 'continue', 'decltype', 'default', 'delete',
      'do', 'double', 'dynamic_cast', 'else', 'enum', 'explicit',
      'extern', 'false', 'float', 'for', 'friend', 'goto', 'if',
      'inline', 'int', 'long', 'mutable', 'namespace', 'new',
      'noexcept', 'not', 'nullptr', 'operator', 'or', 'private',
      'protected', 'public', 'register', 'reinterpret_cast', 'return',
      'short', 'signed', 'sizeof', 'static', 'static_cast', 'struct',
      'switch', 'template', 'this', 'throw', 'true', 'try', 'typedef',
      'typeid', 'typename', 'union', 'unsigned', 'using', 'virtual',
      'void', 'volatile', 'while', 'xor', 'override', 'final',
      'std', 'cout', 'cin', 'endl', 'string', 'vector', 'map',
    ],
    'dart': [
      'abstract', 'as', 'assert', 'async', 'await', 'break', 'case',
      'catch', 'class', 'const', 'continue', 'covariant', 'default',
      'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
      'extension', 'external', 'factory', 'false', 'final', 'finally',
      'for', 'Function', 'get', 'hide', 'if', 'implements', 'import',
      'in', 'interface', 'is', 'late', 'library', 'mixin', 'new',
      'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return',
      'sealed', 'set', 'show', 'static', 'super', 'switch', 'this',
      'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with',
      'yield', 'String', 'int', 'double', 'bool', 'List', 'Map', 'Set',
      'Future', 'Stream', 'Widget', 'BuildContext', 'setState',
    ],
    'html': [
      'html', 'head', 'body', 'title', 'meta', 'link', 'script', 'style',
      'div', 'span', 'p', 'a', 'img', 'ul', 'ol', 'li', 'table', 'tr',
      'td', 'th', 'form', 'input', 'button', 'label', 'select', 'option',
      'textarea', 'header', 'footer', 'nav', 'main', 'section', 'article',
      'aside', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'em',
      'br', 'hr', 'canvas', 'video', 'audio', 'source', 'iframe',
      'class', 'id', 'style', 'href', 'src', 'alt', 'type', 'name',
      'value', 'placeholder', 'required', 'disabled', 'checked',
    ],
    'css': [
      'color', 'background', 'background-color', 'background-image',
      'border', 'border-radius', 'margin', 'padding', 'display', 'flex',
      'grid', 'width', 'height', 'min-width', 'max-width', 'min-height',
      'max-height', 'font-size', 'font-weight', 'font-family', 'line-height',
      'text-align', 'text-decoration', 'position', 'top', 'left', 'right',
      'bottom', 'z-index', 'overflow', 'opacity', 'transform', 'transition',
      'animation', 'box-shadow', 'cursor', 'pointer-events', 'outline',
      'list-style', 'content', 'white-space', 'word-break', 'align-items',
      'justify-content', 'flex-direction', 'flex-wrap', 'gap', 'grid-template',
      'none', 'auto', 'inherit', 'initial', 'unset', 'block', 'inline',
      'inline-block', 'relative', 'absolute', 'fixed', 'sticky',
    ],
  };

  static const _snippets = <String, List<_Snippet>>{
    'python': [
      _Snippet('def fn():', 'def \${1:name}(\${2:args}):\n    \${3:pass}'),
      _Snippet('class Cls:', 'class \${1:Name}:\n    def __init__(self):\n        \${2:pass}'),
      _Snippet('if __main__', 'if __name__ == "__main__":\n    \${1:main()}'),
      _Snippet('for i in range', 'for \${1:i} in range(\${2:10}):\n    \${3:pass}'),
      _Snippet('try/except', 'try:\n    \${1:pass}\nexcept \${2:Exception} as e:\n    \${3:print(e)}'),
      _Snippet('with open', 'with open(\${1:"file.txt"}, \${2:"r"}) as f:\n    \${3:data = f.read()}'),
    ],
    'javascript': [
      _Snippet('function fn()', 'function \${1:name}(\${2:args}) {\n    \${3}\n}'),
      _Snippet('arrow fn', 'const \${1:name} = (\${2:args}) => {\n    \${3}\n};'),
      _Snippet('async function', 'async function \${1:name}(\${2:args}) {\n    \${3}\n}'),
      _Snippet('class Cls', 'class \${1:Name} {\n    constructor(\${2:args}) {\n        \${3}\n    }\n}'),
      _Snippet('fetch()', 'fetch(\${1:url})\n    .then(r => r.json())\n    .then(data => {\n        \${2}\n    });'),
      _Snippet('try/catch', 'try {\n    \${1}\n} catch (\${2:err}) {\n    console.error(\${2:err});\n}'),
    ],
    'java': [
      _Snippet('public class', 'public class \${1:Name} {\n    public static void main(String[] args) {\n        \${2}\n    }\n}'),
      _Snippet('System.out.println', 'System.out.println(\${1:"Hello"});'),
      _Snippet('for loop', 'for (int \${1:i} = 0; \${1:i} < \${2:n}; \${1:i}++) {\n    \${3}\n}'),
    ],
    'dart': [
      _Snippet('StatelessWidget', 'class \${1:Name} extends StatelessWidget {\n  const \${1:Name}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}'),
      _Snippet('StatefulWidget', 'class \${1:Name} extends StatefulWidget {\n  const \${1:Name}({super.key});\n\n  @override\n  State<\${1:Name}> createState() => _\${1:Name}State();\n}\n\nclass _\${1:Name}State extends State<\${1:Name}> {\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}'),
      _Snippet('Future<void>', 'Future<void> \${1:name}() async {\n  \${2}\n}'),
    ],
    'html': [
      _Snippet('<!DOCTYPE html>', '<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>\${1:Document}</title>\n</head>\n<body>\n    \${2}\n</body>\n</html>'),
      _Snippet('<div class="">', '<div class="\${1}">\n    \${2}\n</div>'),
      _Snippet('<script>', '<script>\n    \${1}\n</script>'),
    ],
  };
}

class _Snippet {
  final String label;
  final String insertText;
  const _Snippet(this.label, this.insertText);
}

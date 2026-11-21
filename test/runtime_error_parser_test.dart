import 'package:kriya_code/execution/runner_service.dart';
import 'package:kriya_code/lsp/runtime_error_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeErrorParser', () {
    test('parses Python ZeroDivisionError traceback', () {
      const code = 'def div():\n    a = 1\n    return a / 0\n\ndiv()\n';
      final lines = [
        const ConsoleLine('Traceback (most recent call last):', isStderr: true),
        const ConsoleLine('  File "main.py", line 3, in div', isStderr: true),
        const ConsoleLine('    return a / 0', isStderr: true),
        const ConsoleLine('ZeroDivisionError: division by zero', isStderr: true),
      ];

      final diags = RuntimeErrorParser.parse(
        lines: lines,
        activeFilePath: '/workspace/main.py',
        fileContent: code,
      );

      expect(diags, hasLength(1));
      final d = diags.first;
      expect(d.line, 2); // 0-based line 2 (line 3 in file)
      expect(d.message, 'ZeroDivisionError: division by zero');
      expect(code.substring(d.offset, d.offset + d.length), 'return a / 0');
    });

    test('parses Python SyntaxError with caret', () {
      const code = 'print "hello"\n';
      final lines = [
        const ConsoleLine('  File "main.py", line 1', isStderr: true),
        const ConsoleLine('    print "hello"', isStderr: true),
        const ConsoleLine('          ^', isStderr: true),
        const ConsoleLine('SyntaxError: Missing parentheses in call to \'print\'.', isStderr: true),
      ];

      final diags = RuntimeErrorParser.parse(
        lines: lines,
        activeFilePath: 'main.py',
        fileContent: code,
      );

      expect(diags, hasLength(1));
      final d = diags.first;
      expect(d.line, 0);
      expect(d.column, 10);
      expect(d.message, contains('SyntaxError'));
    });

    test('parses GCC/Clang syntax errors with column', () {
      const code = '#include <stdio.h>\nint main() {\n    printf("hi")\n    return 0;\n}\n';
      final lines = [
        const ConsoleLine('main.c:3:17: error: expected \';\' before \'return\'', isStderr: true),
      ];

      final diags = RuntimeErrorParser.parse(
        lines: lines,
        activeFilePath: '/home/user/project/main.c',
        fileContent: code,
      );

      expect(diags, hasLength(1));
      final d = diags.first;
      expect(d.line, 2);
      expect(d.column, 16);
      expect(d.message, contains('error: expected \';\' before \'return\''));
    });

    test('parses Node.js runtime errors', () {
      const code = 'const x = 1;\nconsole.log(y);\n';
      final lines = [
        const ConsoleLine('ReferenceError: y is not defined', isStderr: true),
        const ConsoleLine('    at Object.<anonymous> (/workspace/app.js:2:13)', isStderr: true),
      ];

      final diags = RuntimeErrorParser.parse(
        lines: lines,
        activeFilePath: 'app.js',
        fileContent: code,
      );

      expect(diags, hasLength(1));
      final d = diags.first;
      expect(d.line, 1);
      expect(d.message, contains('ReferenceError'));
    });

    test('ignores errors from unrelated files', () {
      const code = 'import math\n';
      final lines = [
        const ConsoleLine('  File "/usr/lib/python3.10/math.py", line 12', isStderr: true),
        const ConsoleLine('ValueError: invalid', isStderr: true),
      ];

      final diags = RuntimeErrorParser.parse(
        lines: lines,
        activeFilePath: 'main.py',
        fileContent: code,
      );

      expect(diags, isEmpty);
    });
  });
}

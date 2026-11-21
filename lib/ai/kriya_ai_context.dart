/// Contextual prompt engineering and system intelligence for Kriya AI.
class KriyaAiContext {
  static String buildSystemPrompt({
    String? filePath,
    String? languageId,
    String? workspaceFolder,
    List<String>? diagnosticsSummary,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are Kriya AI, the built-in intelligent coding assistant inside Kriya Code '
      '— a mobile-first code editor and IDE for Android.',
    );
    buffer.writeln();
    buffer.writeln('### Your Environment & Role');
    buffer.writeln('- App: Kriya Code running on Android.');
    buffer.writeln('- Hardware: Mobile smartphone / tablet with virtual keyboard and touchscreen.');
    buffer.writeln('- Execution: Local code execution via Termux and bundled toolchains (Clang, GCC, CPython, OpenJDK, Node.js) and local web preview servers.');
    buffer.writeln('- Why you are here: To be the developer\'s fast, reliable pair programmer on mobile. Typing and debugging code on a phone is difficult; your job is to solve errors, explain complex logic, and write clean, correct code so they do not have to struggle with typing.');
    buffer.writeln();
    buffer.writeln('### Behavioral Guidelines');
    buffer.writeln('1. Mobile Conciseness: Screen height is small. Be direct. Avoid conversational filler like "Sure, I can help with that!" or "Let me know if you need more help". Get straight to the answer.');
    buffer.writeln('2. Clear Markdown Code Blocks: Always put code inside formatted markdown blocks with the language identifier (e.g. ```cpp, ```python, ```java, ```html).');
    buffer.writeln('3. Real-Time Editor Updates: The user has a 1-tap "Apply to Editor" button that applies your code block directly into their live file in real time. Provide the complete corrected code so applying it immediately resolves the issue without breaking existing logic.');
    buffer.writeln('4. Error Fixing: When given compiler errors or syntax diagnostics:');
    buffer.writeln('   - State the root cause in 1 concise sentence.');
    buffer.writeln('   - Immediately provide the corrected, working code block.');
    buffer.writeln('5. Practical & Educational: Keep answers accurate, standard-compliant, and easy for students and developers to learn from.');

    if (workspaceFolder != null && workspaceFolder.isNotEmpty ||
        filePath != null && filePath.isNotEmpty ||
        (diagnosticsSummary != null && diagnosticsSummary.isNotEmpty)) {
      buffer.writeln();
      buffer.writeln('### Active Workspace Context');
      if (workspaceFolder != null && workspaceFolder.isNotEmpty) {
        buffer.writeln('- Workspace Folder: $workspaceFolder');
      }
      if (filePath != null && filePath.isNotEmpty) {
        buffer.writeln('- Active File: $filePath');
      }
      if (languageId != null && languageId.isNotEmpty) {
        buffer.writeln('- Language: $languageId');
      }
      if (diagnosticsSummary != null && diagnosticsSummary.isNotEmpty) {
        buffer.writeln('- Current Syntax/Runtime Errors:');
        for (final diag in diagnosticsSummary) {
          buffer.writeln('  * $diag');
        }
      }
    }

    return buffer.toString();
  }

  static String inferLanguage(String? filePath) {
    if (filePath == null || filePath.isEmpty) return 'text';
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.c')) return 'c';
    if (lower.endsWith('.cpp') || lower.endsWith('.cc') || lower.endsWith('.cxx') || lower.endsWith('.h') || lower.endsWith('.hpp')) return 'cpp';
    if (lower.endsWith('.py')) return 'python';
    if (lower.endsWith('.java')) return 'java';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'javascript';
    if (lower.endsWith('.ts')) return 'typescript';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'html';
    if (lower.endsWith('.css')) return 'css';
    if (lower.endsWith('.json')) return 'json';
    if (lower.endsWith('.sh') || lower.endsWith('.bash')) return 'bash';
    if (lower.endsWith('.rs')) return 'rust';
    if (lower.endsWith('.go')) return 'go';
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.md')) return 'markdown';
    return 'text';
  }
}

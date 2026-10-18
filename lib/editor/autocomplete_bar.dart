import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../lsp/autocomplete_engine.dart';
import '../lsp/autocomplete_item.dart';

class AutocompleteBar extends StatelessWidget {
  final AutocompleteEngine engine;
  final CodeController controller;

  const AutocompleteBar({
    super.key,
    required this.engine,
    required this.controller,
  });

  static const _kindIcon = <int, IconData>{
    AutocompleteKind.function_: Icons.functions_rounded,
    AutocompleteKind.class_: Icons.category_rounded,
    AutocompleteKind.variable: Icons.data_object_rounded,
    AutocompleteKind.keyword: Icons.key_rounded,
    AutocompleteKind.snippet: Icons.code_rounded,
    AutocompleteKind.module: Icons.folder_rounded,
  };

  static const _kindColor = <int, Color>{
    AutocompleteKind.function_: Color(0xFF64B5F6),
    AutocompleteKind.class_: Color(0xFFA5D6A7),
    AutocompleteKind.variable: Color(0xFFFFCC80),
    AutocompleteKind.keyword: Color(0xFFCE93D8),
    AutocompleteKind.snippet: Color(0xFF80CBC4),
    AutocompleteKind.module: Color(0xFFEF9A9A),
  };

  void _apply(AutocompleteItem item) {
    final text = controller.text;
    final sel = controller.selection;
    if (sel.baseOffset < 0) return;

    final cursorPos = sel.baseOffset;
    int start = cursorPos - 1;
    while (start >= 0 && _isWordChar(text[start])) {
      start--;
    }
    start++;

    final newText = text.replaceRange(start, cursorPos, item.insertText);
    final newCursor = start + item.insertText.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  bool _isWordChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final suggestions = engine.suggestions;
        if (suggestions.isEmpty) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, i) {
                    final item = suggestions[i];
                    final color = _kindColor[item.kind] ?? cs.onSurface;
                    final icon = _kindIcon[item.kind] ?? Icons.circle;
                    return InkWell(
                      onTap: () => _apply(item),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 12, color: color),
                            const SizedBox(width: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: cs.onSurface,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                onPressed: engine.dismiss,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        );
      },
    );
  }
}

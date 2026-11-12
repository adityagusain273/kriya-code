import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import 'snippets.dart';

class EditorShortcutBar extends StatefulWidget {
  final CodeController controller;
  final int indentWidth;
  final VoidCallback onFind;
  final VoidCallback onSave;
  final VoidCallback? onToggle;
  final String? languageId;

  const EditorShortcutBar({
    super.key,
    required this.controller,
    required this.indentWidth,
    required this.onFind,
    required this.onSave,
    this.onToggle,
    this.languageId,
  });

  @override
  State<EditorShortcutBar> createState() => ShortcutBarState();
}

class ShortcutBarState extends State<EditorShortcutBar> {
  static const _pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};

  List<List<String>> get _rows => [
    ['TAB', 'UNDO', 'REDO', 'FIND', 'SNIP', 'SAVE', if (widget.onToggle != null) 'HIDE'],
    ['(', ')', '{', '}', '[', ']', '<', '>', '"', "'", ';', ':', '=', '&', '|', '/'],
  ];

  void _onKey(String key) {
    switch (key) {
      case 'TAB':
        _insert(' ' * widget.indentWidth);
        return;
      case 'UNDO':
        widget.controller.historyController.undo();
        return;
      case 'REDO':
        widget.controller.historyController.redo();
        return;
      case 'FIND':
        widget.onFind();
        return;
      case 'SAVE':
        widget.onSave();
        return;
      case 'SNIP':
        _showSnippets();
        return;
      case 'HIDE':
        widget.onToggle?.call();
        return;
    }
    final close = _pairs[key];
    if (close == null) {
      _insert(key);
    } else {
      _wrapOrInsert(key, close);
    }
  }

  void _wrapOrInsert(String open, String close) {
    final selection = widget.controller.selection;
    final value = widget.controller.value;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end =
        (selection.end < 0 || selection.end < start) ? start : selection.end;
    if (end > start) {
      final newText = value.text
          .replaceRange(end, end, close)
          .replaceRange(start, start, open);
      final caret = start + (end - start) + open.length + close.length;
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: caret),
      );
    } else {
      _insert('$open$close', cursorOffset: -1);
    }
  }

  void _insert(String text, {int cursorOffset = 0}) {
    final selection = widget.controller.selection;
    final value = widget.controller.value;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final newText = value.text.replaceRange(start, end, text);
    final caret = (start + text.length + cursorOffset).clamp(0, newText.length);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  void _showSnippets() {
    final snippets = SnippetService.forLanguage(widget.languageId);
    if (snippets.isEmpty) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Snippets',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final snippet in snippets)
            ListTile(
              dense: true,
              leading: Text(
                snippet.prefix,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
              title: Text(snippet.label),
              subtitle: snippet.description != null
                  ? Text(snippet.description!)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                final body = SnippetService.applySnippet(snippet.body);
                widget.controller.insertStr(body);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in _rows)
              Row(
                children: [
                  for (final key in row)
                    Expanded(
                      child: _Key(
                        label: key,
                        onTap: () => _onKey(key),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Key({required this.label, required this.onTap});

  static const _controlKeys = {'TAB', 'UNDO', 'REDO', 'FIND', 'SAVE', 'SNIP', 'HIDE'};

  static const _icons = <String, IconData>{
    'TAB': Icons.keyboard_tab,
    'UNDO': Icons.undo,
    'REDO': Icons.redo,
    'FIND': Icons.search,
    'SAVE': Icons.save_outlined,
    'SNIP': Icons.data_object,
    'HIDE': Icons.keyboard_hide_outlined,
  };

  static const _captions = <String, String>{
    'TAB': 'Tab',
    'UNDO': 'Undo',
    'REDO': 'Redo',
    'FIND': 'Find',
    'SAVE': 'Save',
    'SNIP': 'Snippets',
    'HIDE': 'Hide',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isControl = _controlKeys.contains(label);
    final icon = _icons[label];
    final color = cs.onSurface.withValues(alpha: 0.85);
    final semanticLabel = label == 'SNIP'
        ? 'Code Snippets'
        : label == 'HIDE'
            ? 'Hide shortcut bar'
            : isControl
                ? _captions[label]
                : 'Insert $label';
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: icon == null
              ? Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'monospace',
                      color: color,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: color),
                    Text(
                      _captions[label] ?? '',
                      style: TextStyle(fontSize: 9, color: color, height: 1.1),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

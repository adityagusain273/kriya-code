import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import 'snippets.dart';

class EditorShortcutBar extends StatefulWidget {
  final CodeController controller;
  final int indentWidth;
  final VoidCallback onFind;
  final VoidCallback onSave;
  final String? languageId;

  const EditorShortcutBar({
    super.key,
    required this.controller,
    required this.indentWidth,
    required this.onFind,
    required this.onSave,
    this.languageId,
  });

  @override
  State<EditorShortcutBar> createState() => ShortcutBarState();
}

class ShortcutBarState extends State<EditorShortcutBar> {
  static bool ctrlActive = false;

  static void deactivateCtrl() {
    ctrlActive = false;
  }

  static const _pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};

  static const _rows = <List<String>>[
    ['CTRL', 'TAB', 'UNDO', 'REDO', 'FIND', 'SNIP', 'SAVE', '{', '}', '('],
    [')', '[', ']', '<', '>', '"', "'", ';'],
    [':', '=', '&', '|', '/', '!', ',', '.'],
  ];

  void _onKey(String key) {
    if (key == 'CTRL') {
      setState(() => ctrlActive = !ctrlActive);
      return;
    }

    if (ctrlActive) {
      ctrlActive = false;
      setState(() {});
      return;
    }

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
            child: Text('Snippets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final snippet in snippets)
            ListTile(
              dense: true,
              leading: Text(
                snippet.prefix,
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
              title: Text(snippet.label),
              subtitle: snippet.description != null ? Text(snippet.description!) : null,
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
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF171C23),
        border: Border(top: BorderSide(color: Colors.white10)),
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
                        isCtrlActive: key == 'CTRL' && ctrlActive,
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
  final bool isCtrlActive;

  const _Key({
    required this.label,
    required this.onTap,
    this.isCtrlActive = false,
  });

  static const _controlKeys = {'CTRL', 'TAB', 'UNDO', 'REDO', 'FIND', 'SAVE', 'SNIP'};

  @override
  Widget build(BuildContext context) {
    final isControl = _controlKeys.contains(label);
    final semanticLabel = switch (label) {
      'CTRL' => 'Control key${isCtrlActive ? ', active' : ''}',
      'TAB' => 'Tab key',
      'UNDO' => 'Undo',
      'REDO' => 'Redo',
      'FIND' => 'Find',
      'SAVE' => 'Save file',
      'SNIP' => 'Snippets',
      _ => 'Insert $label',
    };
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 36,
            alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCtrlActive ? const Color(0xFF2A5DB0) : null,
            border: const Border(
              right: BorderSide(color: Colors.white10, width: 0.5),
              bottom: BorderSide(color: Colors.white10, width: 0.5),
            ),
          ),
          child: switch (label) {
            'CTRL' => Text('CTRL',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isCtrlActive
                        ? Colors.white
                        : const Color(0xFF5B9BF5))),
            'TAB' => const Text('TAB',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
            'UNDO' => const Icon(Icons.undo, size: 16, color: Colors.white70),
            'REDO' => const Icon(Icons.redo, size: 16, color: Colors.white70),
            'FIND' =>
                const Icon(Icons.search, size: 16, color: Colors.white70),
            'SAVE' => const Icon(Icons.save_outlined,
                size: 16, color: Colors.white70),
            'SNIP' => const Icon(Icons.code,
                size: 16, color: Colors.white70),
            _ => Text(label,
                style: TextStyle(
                  fontSize: isControl ? 12 : 16,
                  fontFamily: 'monospace',
                  color: Colors.white,
                )),
          },
        ),
      ),
    ),
  );
}
}

import 'package:flutter/material.dart';

class KeyboardHelpPage extends StatelessWidget {
  const KeyboardHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyboard Shortcuts'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'File',
            shortcuts: const [
              _Shortcut('Ctrl + S', 'Save file'),
              _Shortcut('Ctrl + Shift + S', 'Save all files'),
              _Shortcut('Ctrl + W', 'Close active tab'),
              _Shortcut('Ctrl + N', 'New file'),
            ],
          ),
          _Section(
            title: 'Navigation',
            shortcuts: const [
              _Shortcut('Ctrl + P', 'Quick Open (file search)'),
              _Shortcut('Ctrl + Shift + P', 'Command Palette'),
              _Shortcut('Ctrl + Shift + F', 'Global Search'),
              _Shortcut('Ctrl + Tab', 'Next tab'),
              _Shortcut('Ctrl + Shift + Tab', 'Previous tab'),
              _Shortcut('Ctrl + G', 'Go to Line'),
              _Shortcut('Ctrl + B', 'Toggle File Explorer'),
              _Shortcut('Home', 'Move to line start'),
              _Shortcut('End', 'Move to line end'),
              _Shortcut('Ctrl + Home', 'Move to document start'),
              _Shortcut('Ctrl + End', 'Move to document end'),
            ],
          ),
          _Section(
            title: 'Editing',
            shortcuts: const [
              _Shortcut('Ctrl + A', 'Select all'),
              _Shortcut('Ctrl + Z', 'Undo'),
              _Shortcut('Ctrl + Y', 'Redo'),
              _Shortcut('Ctrl + C', 'Copy selection, or the current line'),
              _Shortcut('Ctrl + X', 'Cut selection, or the current line'),
              _Shortcut('Ctrl + V', 'Paste'),
              _Shortcut('Ctrl + D', 'Duplicate line'),
              _Shortcut('Ctrl + L', 'Delete current line'),
              _Shortcut('Alt + Up', 'Move line up'),
              _Shortcut('Alt + Down', 'Move line down'),
              _Shortcut('Ctrl + /', 'Toggle line comment'),
            ],
          ),
          _Section(
            title: 'Run & Tools',
            shortcuts: const [
              _Shortcut('F5', 'Run current file'),
              _Shortcut('Ctrl + F', 'Find / Replace'),
              _Shortcut('Ctrl + `', 'Open Terminal'),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These shortcuts work with any Bluetooth or USB keyboard. On-screen shortcut bar is shown automatically when a software keyboard is active.',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Shortcut> shortcuts;

  const _Section({required this.title, required this.shortcuts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: cs.primary,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: cs.surfaceContainer,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (int i = 0; i < shortcuts.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                _ShortcutRow(shortcut: shortcuts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Shortcut {
  final String keys;
  final String description;
  const _Shortcut(this.keys, this.description);
}

class _ShortcutRow extends StatelessWidget {
  final _Shortcut shortcut;
  const _ShortcutRow({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parts = shortcut.keys.split('+').map((s) => s.trim()).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortcut.description,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 4,
            children: parts.map((key) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/di.dart';
import '../execution/console_panel.dart';
import '../execution/ui/downloads_page.dart';
import '../github/ui/github_page.dart';
import '../plugins/ui/extensions_page.dart';
import '../settings/settings_page.dart';
import '../settings/settings_store.dart';
import 'quick_open.dart';
import 'tab_manager.dart';

VoidCallback? _runWithArgsCallback;
VoidCallback? _runCallback;

void setRunWithArgsCallback(VoidCallback callback) {
  _runWithArgsCallback = callback;
}

void setRunCallback(VoidCallback callback) {
  _runCallback = callback;
}

class CommandPaletteAction {
  final String label;
  final String category;
  final IconData? icon;
  final VoidCallback? onExecute;
  final String? shortcut;

  const CommandPaletteAction({
    required this.label,
    required this.category,
    this.icon,
    this.onExecute,
    this.shortcut,
  });
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<CommandPaletteAction> _filtered = [];
  int _selectedIndex = 0;

  late final List<CommandPaletteAction> _actions;

  @override
  void initState() {
    super.initState();
    _actions = _buildActions();
    _filtered = _actions;
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<CommandPaletteAction> _buildActions() {
    final tabs = sl<TabManager>();
    final tab = tabs.active;
    return [
      CommandPaletteAction(
        label: 'Save',
        category: 'File',
        icon: Icons.save_outlined,
        shortcut: 'Ctrl+S',
        onExecute: () => tabs.save(),
      ),
      CommandPaletteAction(
        label: 'Save All',
        category: 'File',
        icon: Icons.save,
        onExecute: () => tabs.saveAll(),
      ),
      CommandPaletteAction(
        label: 'Close Tab',
        category: 'File',
        icon: Icons.close,
        onExecute: () {
          if (tab != null) tabs.close(tabs.activeIndex);
        },
      ),
      CommandPaletteAction(
        label: 'Close All',
        category: 'File',
        icon: Icons.close_fullscreen,
        onExecute: () => tabs.closeAll(),
      ),
      CommandPaletteAction(
        label: 'Open Explorer',
        category: 'View',
        icon: Icons.folder_open,
        onExecute: () {},
      ),
      CommandPaletteAction(
        label: 'Quick Open',
        category: 'View',
        icon: Icons.search,
        shortcut: 'Ctrl+P',
        onExecute: () {
          QuickOpen.show(context);
        },
      ),
      CommandPaletteAction(
        label: 'Find & Replace',
        category: 'Edit',
        icon: Icons.find_replace,
        shortcut: 'Ctrl+F',
        onExecute: () {},
      ),
      CommandPaletteAction(
        label: 'Go to Line',
        category: 'Edit',
        icon: Icons.numbers,
        shortcut: 'Ctrl+G',
        onExecute: () {},
      ),
      CommandPaletteAction(
        label: 'Run',
        category: 'Execution',
        icon: Icons.play_arrow,
        shortcut: 'Ctrl+R',
        onExecute: () {
          _runCallback?.call();
        },
      ),
      CommandPaletteAction(
        label: 'Run with Arguments',
        category: 'Execution',
        icon: Icons.play_circle_outline,
        shortcut: 'Ctrl+Shift+R',
        onExecute: () {
          _runWithArgsCallback?.call();
        },
      ),
      CommandPaletteAction(
        label: 'Show Console',
        category: 'Execution',
        icon: Icons.terminal,
        onExecute: () {
          ConsolePanel.show(context);
        },
      ),
      CommandPaletteAction(
        label: 'Extensions',
        category: 'Tools',
        icon: Icons.extension,
        onExecute: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtensionsPage()));
        },
      ),
      CommandPaletteAction(
        label: 'Downloads',
        category: 'Tools',
        icon: Icons.download,
        onExecute: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage()));
        },
      ),
      CommandPaletteAction(
        label: 'GitHub',
        category: 'Tools',
        icon: Icons.code,
        onExecute: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const GitHubPage()));
        },
      ),
      CommandPaletteAction(
        label: 'Settings',
        category: 'Preferences',
        icon: Icons.settings,
        onExecute: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => SettingsPage(store: sl<SettingsStore>())));
        },
      ),
      CommandPaletteAction(
        label: 'Select All',
        category: 'Edit',
        icon: Icons.select_all,
        shortcut: 'Ctrl+A',
        onExecute: () {
          if (tab != null) {
            tab.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: tab.controller.text.length,
            );
          }
        },
      ),
      CommandPaletteAction(
        label: 'Undo',
        category: 'Edit',
        icon: Icons.undo,
        shortcut: 'Ctrl+Z',
        onExecute: () {
          if (tab != null) tab.controller.historyController.undo();
        },
      ),
      CommandPaletteAction(
        label: 'Redo',
        category: 'Edit',
        icon: Icons.redo,
        shortcut: 'Ctrl+Y',
        onExecute: () {
          if (tab != null) tab.controller.historyController.redo();
        },
      ),
      CommandPaletteAction(
        label: 'Toggle Comment',
        category: 'Edit',
        icon: Icons.comment,
        shortcut: 'Ctrl+/',
        onExecute: () {},
      ),
      CommandPaletteAction(
        label: 'Duplicate Line',
        category: 'Edit',
        icon: Icons.content_copy,
        shortcut: 'Ctrl+D',
        onExecute: () {},
      ),
    ];
  }

  void _filter(String query) {
    setState(() {
      _selectedIndex = 0;
      if (query.isEmpty) {
        _filtered = _actions;
      } else {
        final q = query.toLowerCase();
        _filtered = _actions.where((a) {
          return a.label.toLowerCase().contains(q) ||
              a.category.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  void _execute(CommandPaletteAction action) {
    Navigator.pop(context);
    action.onExecute?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.6;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Type a command...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (_) {
                if (_filtered.isNotEmpty) _execute(_filtered[_selectedIndex]);
              },
            ),
          ),
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) return;
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() {
                    _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                  if (_filtered.isNotEmpty) _execute(_filtered[_selectedIndex]);
                }
              },
              child: ListView.builder(
                itemCount: _filtered.length,
                padding: const EdgeInsets.only(bottom: 8),
                itemBuilder: (ctx, i) {
                  final action = _filtered[i];
                  final selected = i == _selectedIndex;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
                    leading: Icon(action.icon ?? Icons.chevron_right, size: 18),
                    title: Text(action.label, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(action.category, style: const TextStyle(fontSize: 11)),
                    trailing: action.shortcut != null
                        ? Text(action.shortcut!,
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))
                        : null,
                    onTap: () => _execute(action),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

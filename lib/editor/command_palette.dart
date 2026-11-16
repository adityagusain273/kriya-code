import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/di.dart';
import '../execution/console_panel.dart';
import '../github/auth/token_store.dart';
import '../github/ui/cloud_build_sheet.dart';
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

/// Drops the registered callbacks.
///
/// The callbacks are process-global closures over the editor's State. After
/// EditorPage is disposed (folder change, onboarding), the palette's Run entry
/// would invoke a dead State.
void clearRunCallbacks() {
  _runWithArgsCallback = null;
  _runCallback = null;
  _editCallbacks.clear();
}

// Same pattern as the run callbacks: the palette is built outside the editor's
// State, but several actions operate on the active document.
final Map<Key, VoidCallback> _editCallbacks = {};

void setEditCallback(Key key, VoidCallback callback) => _editCallbacks[key] = callback;

/// Whether a callback is registered for [key].
///
/// The palette resolves its actions from this map at build time, so a key that was
/// never registered produces an action that silently does nothing when chosen. That
/// is exactly the failure this exists to make visible to a test.
bool hasEditCallback(Key key) => _editCallbacks.containsKey(key);

/// Opens the cloud build sheet for a repository the user picks.
///
/// The palette dismisses itself before running an action, so the sheet cannot be
/// shown from the palette's own context — it is unmounted by then. The root
/// navigator outlives it.
Future<void> _openCloudBuild(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  String? token;
  try {
    token = await sl<TokenStore>().read();
  } catch (_) {
    token = null;
  }
  if (!navigator.mounted) return;
  if (token == null || token.isEmpty) {
    navigator.push(MaterialPageRoute(builder: (_) => const GitHubPage()));
    return;
  }
  await CloudBuildSheet.pickRepo(navigator.context, token: token);
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
  final _listFocusNode = FocusNode();
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
    _listFocusNode.dispose();
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
        onExecute: _editCallbacks[Key('close_tab')],
      ),
      CommandPaletteAction(
        label: 'Close All',
        category: 'File',
        icon: Icons.close_fullscreen,
        onExecute: _editCallbacks[Key('close_all')],
      ),
      CommandPaletteAction(
        label: 'Open Explorer',
        category: 'View',
        icon: Icons.folder_open,
        onExecute: _editCallbacks[Key('open_explorer')],
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
        onExecute: _editCallbacks[Key('find_replace')],
      ),
      CommandPaletteAction(
        label: 'Go to Line',
        category: 'Edit',
        icon: Icons.numbers,
        shortcut: 'Ctrl+G',
        onExecute: _editCallbacks[Key('goto_line')],
      ),
      CommandPaletteAction(
        label: 'Go to Symbol',
        category: 'Navigate',
        icon: Icons.list_alt_outlined,
        onExecute: _editCallbacks[Key('go_to_symbol')],
      ),
      CommandPaletteAction(
        label: 'Go to Definition',
        category: 'Navigate',
        icon: Icons.my_location,
        onExecute: _editCallbacks[Key('goto_definition')],
      ),
      CommandPaletteAction(
        label: 'Move Line Up',
        category: 'Edit',
        icon: Icons.keyboard_arrow_up,
        shortcut: 'Alt+Up',
        onExecute: _editCallbacks[Key('move_line_up')],
      ),
      CommandPaletteAction(
        label: 'Move Line Down',
        category: 'Edit',
        icon: Icons.keyboard_arrow_down,
        shortcut: 'Alt+Down',
        onExecute: _editCallbacks[Key('move_line_down')],
      ),
      CommandPaletteAction(
        label: 'Copy Line',
        category: 'Edit',
        icon: Icons.content_copy,
        onExecute: _editCallbacks[Key('copy_line')],
      ),
      CommandPaletteAction(
        label: 'Cut Line',
        category: 'Edit',
        icon: Icons.content_cut,
        onExecute: _editCallbacks[Key('cut_line')],
      ),
      CommandPaletteAction(
        label: 'Run',
        category: 'Execution',
        icon: Icons.play_arrow,
        // F5 is the key that is actually handled. The palette used to advertise
        // Ctrl+R, which did nothing, so the one binding a user could rely on to
        // run code was not discoverable.
        shortcut: 'F5',
        onExecute: () {
          _runCallback?.call();
        },
      ),
      CommandPaletteAction(
        label: 'Run with Arguments',
        category: 'Execution',
        icon: Icons.play_circle_outline,
        shortcut: '',
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
        label: 'Language Runtimes',
        category: 'Tools',
        icon: Icons.memory_outlined,
        onExecute: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ExtensionsPage(initialTab: 1)));
        },
      ),
      CommandPaletteAction(
        label: 'Cloud Build (CI)',
        category: 'Tools',
        icon: Icons.cloud_upload_outlined,
        onExecute: () => _openCloudBuild(context),
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
        onExecute: _editCallbacks[Key('toggle_comment')],
      ),
      CommandPaletteAction(
        label: 'Duplicate Line',
        category: 'Edit',
        icon: Icons.content_copy,
        shortcut: 'Ctrl+D',
        onExecute: _editCallbacks[Key('duplicate_line')],
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
              focusNode: _listFocusNode,
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

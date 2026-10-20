import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/di.dart';
import '../core/haptics.dart';
import '../core/network_helper.dart';
import 'autocomplete_bar.dart';
import 'highlighting/syntax_themes.dart';
import 'highlighting/highlight_service.dart';
import '../execution/console_panel.dart';
import '../execution/models.dart';
import '../execution/runner_service.dart';
import '../execution/ui/downloads_page.dart';
import '../github/ui/github_page.dart';
import '../lsp/autocomplete_engine.dart';
import '../plugins/api/run_config.dart';
import '../plugins/host/extension_install_store.dart';
import '../plugins/host/language_registry.dart';
import '../plugins/ui/extensions_page.dart';
import '../servers/server_panel.dart';
import '../settings/settings_page.dart';
import '../settings/settings_store.dart';
import '../workspace/explorer_prefs.dart';
import 'find_replace.dart';
import 'keyboard_help_page.dart';
import 'preview/preview_page.dart';
import 'preview/preview_server.dart';
import 'preview/live_server.dart';
import 'recent_files_service.dart';
import 'tab_manager.dart';
import '../workspace/import_actions.dart';
import '../workspace/file_explorer.dart';
import '../workspace/file_icons.dart';
import '../workspace/fs_service.dart';
import 'command_palette.dart';
import 'line_commands.dart';
import 'zoom_viewer.dart';
import 'global_search.dart';
import 'quick_open.dart';
import 'shortcut_bar.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showFind = false;
  TabController? _tabController;
  int _tabControllerLength = -1;
  final AutocompleteEngine _autocomplete = AutocompleteEngine();

  /// Attached to the visible editor so a global-search result can pull focus and
  /// let the field scroll its caret into view.
  final FocusNode _editorFocus = FocusNode();
  final FileExplorerController _explorerController = FileExplorerController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setRunWithArgsCallback(_showRunWithArgsDialog);
    setRunCallback(_run);
    setEditCallback(const Key('find_replace'), () {
      final tab = sl<TabManager>().active;
      if (tab != null) setState(() => _showFind = true);
    });
    setEditCallback(const Key('goto_line'), () {
      _goToLine();
    });
    setEditCallback(const Key('toggle_comment'), () {
      final tab = sl<TabManager>().active;
      if (tab != null) _toggleComment(tab.controller, tab.languageId);
    });
    setEditCallback(const Key('duplicate_line'), () {
      final tab = sl<TabManager>().active;
      if (tab != null) _duplicateLine(tab.controller);
    });
    // Registered as palette commands, not just shortcuts: Alt+arrow is unreachable
    // without a hardware keyboard, which most people editing on a phone do not have.
    setEditCallback(const Key('move_line_up'), () {
      final tab = sl<TabManager>().active;
      if (tab != null && tab.controller.moveLine(-1)) Haptics.selection();
    });
    setEditCallback(const Key('move_line_down'), () {
      final tab = sl<TabManager>().active;
      if (tab != null && tab.controller.moveLine(1)) Haptics.selection();
    });
    setEditCallback(const Key('copy_line'), () {
      sl<TabManager>().active?.controller.copyLines();
      Haptics.selection();
    });
    setEditCallback(const Key('cut_line'), () {
      sl<TabManager>().active?.controller.cutLines();
      Haptics.selection();
    });
    setEditCallback(const Key('open_explorer'), () {
      _scaffoldKey.currentState?.openDrawer();
    });
    setEditCallback(const Key('close_tab'), () {
      final tabs = sl<TabManager>();
      if (tabs.activeIndex >= 0) _closeTabWithConfirm(tabs.activeIndex);
    });
    setEditCallback(const Key('close_all'), _closeAllWithConfirm);
    sl<TabManager>().addListener(_onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sl<TabManager>().restoreSession();
    });
  }

  void _onTabsChanged() {
    if (!mounted) return;
    final tab = sl<TabManager>().active;
    _autocomplete.setLanguage(tab?.languageId);
    if (tab != null) {
      _autocomplete.onTextChanged(
          tab.controller.text, tab.controller.selection.baseOffset);
    } else {
      _autocomplete.dismiss();
    }
    setState(() {});
    // A search result can arrive while its tab is already the active one, so the
    // tab-index listener is not the only place this has to be honoured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealPendingMatch();
    });
  }

  void _syncTabController(int length) {
    if (length == _tabControllerLength && _tabController != null) return;
    final manager = sl<TabManager>();
    _tabController?.removeListener(_onTabTapped);
    _tabController?.dispose();
    final ctrlLength = length > 0 ? length : 1;
    _tabController = TabController(length: ctrlLength, vsync: this);
    _tabController!.addListener(_onTabTapped);
    _tabControllerLength = length;
    if (manager.activeIndex >= 0 && manager.activeIndex < length) {
      _tabController!.index = manager.activeIndex;
    }
  }

  /// Brings a pending search match into view once the tab is on screen.
  ///
  /// The reveal is requested by a different screen (global search) and consumed
  /// here, after the frame that lays the editor out, because scrolling a field that
  /// has not been measured yet does nothing.
  void _revealPendingMatch() {
    final tab = sl<TabManager>().active;
    if (tab == null) return;
    final offset = tab.takePendingReveal();
    if (offset == null) return;
    _editorFocus.requestFocus();
    // The caret position is already set on the controller; giving the field focus
    // makes it scroll that caret into view, which is the behaviour the user expects
    // from a search result.
    tab.controller.selection = TextSelection.collapsed(offset: offset);
  }

  void _onTabTapped() {
    if (_tabController!.indexIsChanging) return;
    final manager = sl<TabManager>();
    final i = _tabController!.index;
    if (i >= 0 && i < manager.tabs.length && i != manager.activeIndex) {
      manager.activate(i);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealPendingMatch();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editorFocus.dispose();
    _explorerController.dispose();
    sl<TabManager>().removeListener(_onTabsChanged);
    clearRunCallbacks();
    _tabController?.dispose();
    _autocomplete.dispose();
    unawaited(_previewServer.stop().catchError((Object _) {}));
    final liveServer = _liveServer;
    if (liveServer != null) {
      unawaited(liveServer.stop().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Autosave used to fire only on the timer; process-kill mid-debounce left a
    // truncated file. Flush on every pause so no dirty buffer outlives the UI.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(sl<TabManager>().saveAll());
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // Checked before the bare-key navigation below, which would otherwise swallow
    // the arrow keys before a modifier ever got a look in.
    if (alt && !ctrl) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        final tab = sl<TabManager>().active;
        if (tab == null) return KeyEventResult.ignored;
        final moved = tab.controller.moveLine(
          key == LogicalKeyboardKey.arrowUp ? -1 : 1,
        );
        if (moved) Haptics.selection();
        return moved ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }

    if (!ctrl) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.f5) {
        _run();
        Haptics.onRun();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.home) {
        final tab = sl<TabManager>().active;
        if (tab != null) {
          final text = tab.controller.text;
          final sel = tab.controller.selection;
          if (sel.start >= 0) {
            int lineStart = sel.start;
            while (lineStart > 0 && text[lineStart - 1] != '\n') {
              lineStart--;
            }
            tab.controller.selection = TextSelection.collapsed(offset: lineStart);
          }
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.end) {
        final tab = sl<TabManager>().active;
        if (tab != null) {
          final text = tab.controller.text;
          final sel = tab.controller.selection;
          if (sel.start >= 0) {
            int lineEnd = sel.start;
            while (lineEnd < text.length && text[lineEnd] != '\n') {
              lineEnd++;
            }
            tab.controller.selection = TextSelection.collapsed(offset: lineEnd);
          }
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (!mounted) return KeyEventResult.ignored;

    final tabs = sl<TabManager>();
    final tab = tabs.active;

    if (shift && key == LogicalKeyboardKey.keyP) {
      CommandPalette.show(context);
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyP) {
      QuickOpen.show(context);
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (shift && key == LogicalKeyboardKey.keyF) {
      GlobalSearchPage.show(context);
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyW) {
      if (tab != null) {
        final idx = tabs.tabs.indexOf(tab);
        if (idx >= 0) _closeTabWithConfirm(idx);
      }
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.tab) {
      if (tabs.tabs.length > 1) {
        final idx = tabs.activeIndex;
        final next = shift
            ? (idx - 1 + tabs.tabs.length) % tabs.tabs.length
            : (idx + 1) % tabs.tabs.length;
        tabs.activate(next);
        _tabController?.animateTo(next);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyN) {
      _createNewFile();
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyB) {
      _scaffoldKey.currentState?.openDrawer();
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.backquote) {
      ConsolePanel.show(context);
      Haptics.selection();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.home) {
      if (tab != null) {
        tab.controller.selection = const TextSelection.collapsed(offset: 0);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.end) {
      if (tab != null) {
        tab.controller.selection =
            TextSelection.collapsed(offset: tab.controller.text.length);
      }
      return KeyEventResult.handled;
    }

    if (tab == null) return KeyEventResult.handled;
    final controller = tab.controller;

    if (shift && key == LogicalKeyboardKey.keyS) {
      tabs.saveAll();
      Haptics.onSave();
    } else if (key == LogicalKeyboardKey.keyA) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyZ) {
      controller.historyController.undo();
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyY) {
      controller.historyController.redo();
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyS) {
      tabs.save();
      Haptics.onSave();
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _showFind = true);
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyD) {
      _duplicateLine(controller);
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyL) {
      _deleteCurrentLine(controller);
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyC) {
      // With a selection this is a plain copy; without one it copies the caret's
      // whole line, which is what every editor does and what a bare cursor
      // otherwise makes impossible.
      final sel = controller.selection;
      if (sel.isCollapsed) {
        controller.copyLines();
        Haptics.selection();
      } else if (sel.start >= 0) {
        Clipboard.setData(ClipboardData(
            text: controller.text.substring(sel.start, sel.end)));
      }
    } else if (key == LogicalKeyboardKey.keyX) {
      final sel = controller.selection;
      if (sel.isCollapsed) {
        controller.cutLines();
        Haptics.selection();
      } else if (sel.start >= 0) {
        Clipboard.setData(ClipboardData(
            text: controller.text.substring(sel.start, sel.end)));
        _deleteSelection(controller);
      }
    } else if (key == LogicalKeyboardKey.keyV) {
      _pasteFromClipboard(controller);
    } else if (key == LogicalKeyboardKey.slash) {
      _toggleComment(controller, tab.languageId);
      Haptics.selection();
    } else if (key == LogicalKeyboardKey.keyG) {
      _goToLine();
      Haptics.selection();
    }
    return KeyEventResult.handled;
  }

  void _pasteFromClipboard(CodeController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _deleteSelection(controller);
      _insertText(controller, data.text!);
    }
  }

  void _deleteCurrentLine(CodeController ctrl) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (sel.start < 0) return;
    final lines = text.split('\n');
    int lineStart = 0;
    int lineIdx = 0;
    for (int i = 0; i < lines.length; i++) {
      final end = lineStart + lines[i].length;
      if (end >= sel.start || i == lines.length - 1) {
        lineIdx = i;
        break;
      }
      lineStart = end + 1;
    }
    final deleteFrom = lineStart;
    final lineEnd = lineStart + lines[lineIdx].length;
    final deleteTo = lineEnd < text.length ? lineEnd + 1 : lineEnd;
    final newText = text.replaceRange(deleteFrom, deleteTo, '');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: deleteFrom.clamp(0, newText.length)),
    );
  }

  Future<void> _createNewFile() async {
    final name = await _promptForNewFileName(context);
    if (name == null || !mounted) return;

    final relative = _safeRelativeFileName(name);
    if (relative == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That is not a valid file name. Use a plain name with no path separators.',
          ),
        ),
      );
      return;
    }

    await sl<FsService>().writeFile(relative, '');
    if (!mounted) return;
    await sl<TabManager>().open(relative);
  }

  void _duplicateLine(CodeController ctrl) {
    ctrl.duplicateLine();
  }

  void _deleteSelection(CodeController ctrl) {
    final sel = ctrl.selection;
    if (sel.isCollapsed || sel.start < 0) return;
    final newText =
        ctrl.text.replaceRange(sel.start, sel.end, '');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start),
    );
  }

  void _insertText(CodeController ctrl, String text) {
    ctrl.insertStr(text);
  }

  String _commentPrefix(String? languageId) {
    switch (languageId) {
      case 'python':
      case 'yaml':
      case 'ruby':
      case 'toml':
      case 'ini':
        return '#';
      case 'java':
      case 'javascript':
      case 'typescript':
      case 'c':
      case 'cpp':
      case 'csharp':
      case 'go':
      case 'rust':
      case 'swift':
      case 'kotlin':
      case 'dart':
      case 'scala':
      case 'groovy':
      case 'php':
      case 'json':
        return '//';
      case 'html':
      case 'xml':
      case 'svg':
        return '<!--';
      case 'css':
      case 'scss':
      case 'less':
        return '/*';
      case 'sql':
        return '--';
      case 'lua':
      case 'r':
        return '--';
      default:
        return '//';
    }
  }

  String _commentSuffix(String? languageId) {
    switch (languageId) {
      case 'html':
      case 'xml':
      case 'svg':
        return '-->';
      case 'css':
      case 'scss':
      case 'less':
        return '*/';
      default:
        return '';
    }
  }

  String _langName(String? id, String ext) {
    if (id != null && id.isNotEmpty) return id;
    switch (ext) {
      case 'c':
      case 'h':
        return 'C';
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'hpp':
        return 'C++';
      case 'py':
        return 'Python';
      case 'js':
        return 'JavaScript';
      case 'ts':
        return 'TypeScript';
      case 'dart':
        return 'Dart';
      case 'java':
        return 'Java';
      case 'go':
        return 'Go';
      case 'rs':
        return 'Rust';
      case 'rb':
        return 'Ruby';
      case 'php':
        return 'PHP';
      case 'html':
      case 'htm':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'json':
        return 'JSON';
      case 'md':
        return 'Markdown';
      case 'sh':
      case 'bash':
        return 'Shell';
      case 'sql':
        return 'SQL';
      default:
        return 'Plain Text';
    }
  }

  void _toggleComment(CodeController ctrl, String? languageId) {
    ctrl.toggleComment(_commentPrefix(languageId), _commentSuffix(languageId));
  }

  Future<void> _goToLine() async {
    final tab = sl<TabManager>().active;
    if (tab == null) return;
    final controller = tab.controller;
    final text = controller.text;
    final totalLines = text.split('\n').length;
    final lineCtrl = TextEditingController();

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Go to Line (1-$totalLines)'),
        content: TextField(
          controller: lineCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Line number',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final num = int.tryParse(lineCtrl.text);
            if (num != null && num >= 1 && num <= totalLines) {
              Navigator.pop(ctx, num);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final num = int.tryParse(lineCtrl.text);
              if (num != null && num >= 1 && num <= totalLines) {
                Navigator.pop(ctx, num);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    lineCtrl.dispose();

    if (result == null) return;

    int pos = 0;
    final lines = text.split('\n');
    for (int i = 0; i < result - 1 && i < lines.length; i++) {
      pos += lines[i].length + 1;
    }
    controller.selection = TextSelection.collapsed(offset: pos);
  }

  static const _langToExtId = <String, String>{
    'python': 'bcode.lang.python',
    'java': 'bcode.lang.java',
    'c': 'bcode.lang.c',
    'cpp': 'bcode.lang.cpp',
    'javascript': 'bcode.lang.javascript',
    'typescript': 'bcode.lang.typescript',
    'html': 'bcode.lang.html',
    'css': 'bcode.lang.css',
    'json': 'bcode.lang.json',
  };
  Future<void> _run() async {
    await _runWithArgs(null);
  }

  Future<void> _runWithArgs(List<String>? args) async {
    Haptics.onRun();
    final tabs = sl<TabManager>();
    final registry = sl<LanguageRegistry>();
    final runner = sl<RunnerService>();
    final tab = tabs.active;
    if (tab == null) return;

    final langId = tab.languageId ?? '';
    final extId = _langToExtId[langId];
    if (extId != null && !sl<ExtensionInstallStore>().isInstalled(extId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Install the ${langId.toUpperCase()} extension to run code.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Extensions',
              textColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExtensionsPage()),
              ),
            ),
          ),
        );
      }
      return;
    }

    final online = await NetworkHelper.isOnline;
    if (!online && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No internet connection. Code will run offline if a runtime is installed.'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Downloads',
            textColor: Colors.white,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsPage()),
            ),
          ),
        ),
      );
    }

    await tabs.save();
    final contribution = registry.byId(langId);
    final config = contribution?.runConfig;
    await runner.run(
      request: RunRequest(mainFile: tab.filePath, source: tab.controller.text, args: args ?? []),
      config: config ?? const RunConfig(),
      workDir: _workDir(),
    );
    if (mounted) {
      ConsolePanel.show(context);
      if (runner.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(runner.lastError!, maxLines: 2, overflow: TextOverflow.ellipsis),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(store: sl<SettingsStore>()),
                ),
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showRunWithArgsDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run with Arguments'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter command line arguments',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      final args = result.split(' ').where((s) => s.isNotEmpty).toList();
      await _runWithArgs(args);
    }
  }

  Widget _buildCodeView(dynamic tab) {
    return ListenableBuilder(
      // Installed extensions matter here: pinch-to-zoom is switched on by installing
      // an extension, and without listening to that store the editor was never
      // rebuilt, so installing it appeared to do nothing until some unrelated
      // settings change or a restart.
      listenable: Listenable.merge([
        sl<SettingsStore>(),
        sl<ExtensionInstallStore>(),
      ]),
      builder: (context, _) {
        final settings = sl<SettingsStore>();
        final fontFamily = settings.fontFamily;
        final showLineNumbers = settings.showLineNumbers;
        final wordWrap = settings.wordWrap;

        final baseTheme = SyntaxThemes.fromId(settings.syntaxThemeId).styles;
        
        // flutter_code_editor completely replaces text styles for tokens instead of merging.
        // We inject the font family and size into every token style to prevent them from reverting to default.
        final syntaxTheme = <String, TextStyle>{};
        baseTheme.forEach((key, style) {
          syntaxTheme[key] = style.copyWith(
            fontFamily: fontFamily,
            fontSize: settings.fontSize,
          );
        });

        final codeField = NotificationListener<ScrollNotification>(
          onNotification: (_) => false,
          child: ListenableBuilder(
            listenable: tab.controller,
            builder: (_, __) {
              _autocomplete.setLanguage(tab.languageId);
              _autocomplete.onTextChanged(
                tab.controller.text,
                tab.controller.selection.baseOffset,
              );
              return const SizedBox.shrink();
            },
          ),
        );

        final editor = CodeTheme(
          data: CodeThemeData(styles: syntaxTheme),
          child: CodeField(
            controller: tab.controller,
            focusNode: _editorFocus,
            wrap: wordWrap,
            expands: true,
            background: syntaxTheme['root']?.backgroundColor ?? Colors.transparent,
            gutterStyle: GutterStyle(
              background: syntaxTheme['root']?.backgroundColor ?? Colors.transparent,
              showLineNumbers: showLineNumbers,
              showFoldingHandles: false,
              showErrors: false,
              width: showLineNumbers ? 48 : 0,
              margin: showLineNumbers ? 8 : 0,
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white38,
              ),
            ),
            textStyle: TextStyle(
              fontFamily: fontFamily,
              fontSize: settings.fontSize,
            ),
          ),
        );

        final combined = Stack(
          children: [
            editor,
            Positioned.fill(child: IgnorePointer(child: codeField)),
          ],
        );

        if (sl<ExtensionInstallStore>().isInstalled('bcode.zoom')) {
          // Wraps `combined`, not `editor`: the syntax-highlighting overlay is a
          // sibling of the text field, and returning only the editor dropped it, so
          // turning the extension on made the file lose all its colours.
          return BCodeZoomView(
            key: ValueKey('zoom_${tab.filePath}'),
            child: combined,
          );
        }

        return combined;
      },
    );
  }


  String _workDir() => sl<FsService>().rootPath;

  late final PreviewServer _previewServer =
      PreviewServer(sl<FsService>().rootPath);

  LiveServer? _liveServer;

  bool _isPreviewable(String? path) {
    if (path == null) return false;
    final ext = path.split('.').last.toLowerCase();
    return ext == 'html' || ext == 'htm';
  }

  Future<void> _openPreview() async {
    final tab = sl<TabManager>().active;
    if (tab == null) return;
    await sl<TabManager>().save();
    final baseUrl = await _previewServer.start();
    final rel = p.relative(tab.filePath, from: sl<FsService>().rootPath);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          baseUrl: baseUrl,
          relativePath: rel,
          title: tab.name,
        ),
      ),
    );
  }

  Future<void> _toggleLiveServer() async {
    if (_liveServer?.isRunning == true) {
      await _liveServer!.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live Server stopped.'),
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {});
      }
      return;
    }
    _liveServer = LiveServer(sl<FsService>().rootPath);
    final url = await _liveServer!.start();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Live Server running at $url'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () => _openLivePreview(),
          ),
        ),
      );
      setState(() {});
    }
  }

  void _openLivePreview() {
    final url = _liveServer?.urlFor('');
    if (url == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          baseUrl: url,
          relativePath: '',
          title: 'Live Server',
        ),
      ),
    );
  }

  /// Opens a file from anywhere on the device by importing it into the
  /// workspace first.
  ///
  /// The workspace is app-private and B Code requests no storage permission, so there
  /// is nothing to browse directly: the Storage Access Framework hands us a stream,
  /// and the copy lands inside the workspace where the explorer can see it.
  Future<void> _importAndOpenFile() async {
    final imported = await importFileFromDevice(context);
    if (imported == null || !mounted) return;
    await sl<TabManager>().open(imported.path);
  }

  /// Copies a whole project folder off the device into the workspace, then shows the
  /// explorer with that folder opened.
  Future<void> _importFolder() async {
    final imported = await importFolderFromDevice(context);
    if (imported == null || !mounted) return;
    _revealImported(imported.path);
  }

  /// Picks an archive off the device, copies it in, and unpacks it.
  Future<void> _importAndExtractArchive() async {
    final imported = await importArchiveFromDevice(context);
    if (imported == null || !mounted) return;
    _revealImported(imported.path);
  }

  /// Opens the explorer with [absolutePath] expanded, so a freshly imported folder is
  /// not left collapsed at the root behind a row the user has to go and find.
  void _revealImported(String absolutePath) {
    final relative = sl<FsService>().relativeToRoot(absolutePath);
    if (relative.isNotEmpty && relative != '.') {
      _explorerController.reveal(relative);
    }
    _scaffoldKey.currentState?.openDrawer();
  }

  String? _indentLangId;
  Future<int>? _indentFuture;

  /// Cached so the shortcut bar's indent width is not rebuilt from scratch on every
  /// keystroke.
  ///
  /// The future used to be constructed inline in `build`. A `FutureBuilder` handed a
  /// brand new future restarts in `ConnectionState.none`, so its `data` was null —
  /// and the bar fell back to a hardcoded 2 — for at least one frame on every
  /// rebuild, and the lookup was reissued each time the user typed.
  Future<int> _indentFutureFor(String? languageId) {
    if (_indentLangId != languageId) {
      _indentLangId = languageId;
      _indentFuture = sl<HighlightService>().indentWidthFor(languageId);
    }
    return _indentFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<TabManager>();
    final tab = tabs.active;
    _syncTabController(tabs.tabs.length);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final tabs = sl<TabManager>();
        if (tabs.hasUnsavedChanges) {
          final save = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Unsaved changes'),
              content: const Text('You have unsaved changes. Save before exiting?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'discard'),
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (save == 'save') {
            await tabs.saveAll();
            if (mounted && context.mounted) Navigator.pop(context);
          } else if (save == 'discard') {
            if (mounted && context.mounted) Navigator.pop(context);
          }
        } else {
          if (mounted && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          tab == null ? 'B Code' : '${tab.name}${tab.dirty ? " •" : ""}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(_showFind ? Icons.search_off : Icons.search),
            tooltip: 'Find / Replace',
            onPressed: tab == null
                ? null
                : () => setState(() {
                      _showFind = !_showFind;
                    }),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Downloads',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage()));
            },
          ),
          IconButton(icon: const Icon(Icons.save_outlined), tooltip: 'Save', onPressed: tabs.save),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Run (Long press for arguments)',
            onPressed: tab == null ? null : _run,
            onLongPress: tab == null ? null : _showRunWithArgsDialog,
          ),
          if (_isPreviewable(tab?.filePath))
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Preview',
              onPressed: tab == null ? null : _openPreview,
            ),
          IconButton(
            icon: const Icon(Icons.code),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GitHubPage())),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'github':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GitHubPage()));
                  break;
                case 'extensions':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ExtensionsPage()));
                  break;
                case 'downloads':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DownloadsPage()));
                  break;
                case 'settings':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SettingsPage(store: sl<SettingsStore>())));
                  break;
                case 'save_all':
                  await tabs.saveAll();
                  break;
                case 'close_all':
                  await _closeAllWithConfirm();
                  break;
                case 'go_to_line':
                  _goToLine();
                  break;
                case 'command_palette':
                  CommandPalette.show(context);
                  break;
                case 'global_search':
                  GlobalSearchPage.show(context);
                  break;
                case 'open_file':
                  _importAndOpenFile();
                  break;
                case 'open_folder':
                  _importFolder();
                  break;
                case 'extract_archive':
                  _importAndExtractArchive();
                  break;
                case 'terminal':
                  ConsolePanel.show(context);
                  break;
                case 'live_server':
                  _toggleLiveServer();
                  break;
                case 'dev_servers':
                  ServerPanel.show(context);
                  break;
                case 'keyboard_help':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const KeyboardHelpPage()));
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'command_palette', child: Text('Command Palette')),
              const PopupMenuItem(value: 'terminal', child: Text('Terminal')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'github', child: Text('GitHub')),
              const PopupMenuItem(value: 'extensions', child: Text('Extensions')),
              const PopupMenuItem(value: 'downloads', child: Text('Downloads')),
              PopupMenuItem(
                value: 'live_server',
                child: Text(_liveServer?.isRunning == true
                    ? 'Stop Live Server'
                    : 'Start Live Server'),
              ),
              const PopupMenuItem(value: 'dev_servers', child: Text('Dev Servers')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'open_file',
                child: Text('Open File...'),
              ),
              const PopupMenuItem(
                value: 'open_folder',
                child: Text('Open Folder...'),
              ),
              const PopupMenuItem(
                value: 'extract_archive',
                child: Text('Extract Project Archive...'),
              ),
              const PopupMenuItem(
                value: 'global_search',
                child: Text('Global Search'),
              ),
              PopupMenuItem(
                value: 'go_to_line',
                enabled: tab != null,
                child: const Text('Go to Line'),
              ),
              PopupMenuItem(
                value: 'save_all',
                enabled: tabs.hasUnsavedChanges,
                child: const Text('Save All'),
              ),
              PopupMenuItem(
                value: 'close_all',
                enabled: tabs.tabs.isNotEmpty,
                child: const Text('Close All'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'keyboard_help', child: Text('Keyboard Shortcuts')),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        width: 300,
        child: FileExplorer(
          key: ValueKey(sl<FsService>().rootPath),
          fs: sl(),
          prefs: sl<ExplorerPrefs>(),
          controller: _explorerController,
          onFileTap: (path) {
            Navigator.pop(context);
            sl<TabManager>().open(path);
          },
          onChanged: () {},
          activeFile: tab?.filePath,
        ),
      ),
      body: Column(
        children: [
          if (tabs.tabs.isNotEmpty)
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (var i = 0; i < tabs.tabs.length; i++)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tabIcon(tabs.tabs[i].filePath),
                        const SizedBox(width: 4),
                        Text(tabs.tabs[i].name),
                        if (tabs.tabs[i].dirty) const Text(' •'),
                        GestureDetector(
                          onTap: () => _closeTabWithConfirm(i),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: const Icon(Icons.close, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (_showFind && tab != null)
            FindReplaceBar(controller: tab.findController),
          Expanded(
            child: tab == null
                ? _EmptyState(
                    onOpenFile: _importAndOpenFile,
                    onOpenFolder: _importFolder,
                    onExtractArchive: _importAndExtractArchive,
                  )
                : Focus(
                    onKeyEvent: _onKeyEvent,
                    child: _buildCodeView(tab),
                  ),
          ),
          if (tab != null)
            _StatusBar(tab: tab, langName: _langName(tab.languageId, tab.name.contains('.') ? tab.name.split('.').last.toLowerCase() : '')),
          if (tab != null)
            AutocompleteBar(
              engine: _autocomplete,
              controller: tab.controller,
            ),
          if (tab != null)
            FutureBuilder<int>(
              future: _indentFutureFor(tab.languageId),
              builder: (context, snapshot) => EditorShortcutBar(
                controller: tab.controller,
                indentWidth: snapshot.data ?? 2,
                onFind: () => setState(() => _showFind = true),
                onSave: tabs.save,
                languageId: tab.languageId,
              ),
            ),
        ],
      ),

    ),
    );
  }

  Widget _tabIcon(String path) {
    return FileTypeIcon(spec: fileSpec(path), size: 14);
  }

  Future<void> _closeAllWithConfirm() async {
    final tabs = sl<TabManager>();
    if (tabs.hasUnsavedChanges) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text('Some files have unsaved changes. Save all before closing?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard all'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save all'),
            ),
          ],
        ),
      );
      if (result == 'save') {
        await tabs.saveAll();
        await tabs.closeAll();
      } else if (result == 'discard') {
        await tabs.closeAll();
      }
    } else {
      await tabs.closeAll();
    }
  }

  Future<void> _closeTabWithConfirm(int index) async {    Haptics.onTabClose();
    final tabs = sl<TabManager>();
    final tab = tabs.tabs[index];
    if (tab.dirty) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text('"${tab.name}" has unsaved changes. What would you like to do?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result == 'save') {
        await tabs.save(tab);
        await tabs.close(index);
      } else if (result == 'discard') {
        await tabs.close(index);
      }
    } else {
      await tabs.close(index);
    }
  }
}

class _StatusBar extends StatefulWidget {
  final EditorTab tab;
  final String langName;
  const _StatusBar({required this.tab, required this.langName});

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder: rebuild when the document or selection actually
    // changes. Previously the status bar only re-ran when the dirty flag flipped,
    // so the Ln/Col and line/word counts froze for the whole editing session.
    return ListenableBuilder(
      listenable: widget.tab.controller,
      builder: (context, _) => _buildStatus(context),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final tab = widget.tab;
    final sel = tab.controller.selection;
    final text = tab.controller.text;
    final pos = sel.start >= 0 ? sel.start : 0;
    int line = 1, col = 1;
    int count = 0;
    for (int i = 0; i < pos && i < text.length; i++) {
      count++;
      if (text[i] == '\n') {
        line++;
        count = 0;
      }
    }
    col = count + 1;

    final langName = widget.langName;

    final wordCount = text.isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final charCount = text.length;
    final lineCount = text.isEmpty ? 1 : text.split('\n').length;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        child: Row(
          children: [
            Text('Ln $line, Col $col'),
            const SizedBox(width: 16),
            Text('$lineCount lines'),
            const SizedBox(width: 16),
            Flexible(child: Text(langName, overflow: TextOverflow.ellipsis)),
            const Spacer(),
            Flexible(child: Text('$wordCount words', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            Flexible(child: Text('$charCount chars', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
            // Read-only, because there is nothing to change: files are read and
            // written as UTF-8, and the line ending in use is whatever the file
            // already contains. These used to be dropdowns that looked editable and
            // silently did nothing, which is worse than not offering the choice --
            // picking a different encoding gave no hint that the bytes on disk were
            // still UTF-8.
            Text(detectLineEnding(widget.tab.controller.text)),
            const SizedBox(width: 12),
            const Text('UTF-8'),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatefulWidget {
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onExtractArchive;
  const _EmptyState({
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onExtractArchive,
  });

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  List<String> _recentFiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await RecentFilesService.instance.getAll();
    if (mounted) setState(() => _recentFiles = files);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabs = sl<TabManager>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.code_rounded, size: 72, color: cs.onSurface.withValues(alpha: 0.12)),
            const SizedBox(height: 20),
            Text(
              'B Code',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Open a file or folder to start editing',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: widget.onOpenFile,
                  icon: const Icon(Icons.file_open_rounded, size: 18),
                  label: const Text('Open File'),
                ),
                FilledButton.tonalIcon(
                  onPressed: widget.onOpenFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open Folder'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onExtractArchive,
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
                  label: const Text('Unzip Project'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final name = await _promptForNewFileName(context);
                    if (name == null || !context.mounted) return;
                    final relative = _safeRelativeFileName(name);
                    if (relative == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'That is not a valid file name. Use a plain name with no path separators.',
                          ),
                        ),
                      );
                      return;
                    }
                    await sl<FsService>().writeFile(relative, '');
                    if (!context.mounted) return;
                    await tabs.open(relative);
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New File'),
                ),
              ],
            ),
            if (_recentFiles.isNotEmpty) ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'RECENT FILES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...(_recentFiles.take(8).map((path) {
                final name = path.split('/').last;
                final dir = path.contains('/')
                    ? path.substring(0, path.lastIndexOf('/'))
                    : path;
                final shortDir = dir.length > 40
                    ? '…${dir.substring(dir.length - 38)}'
                    : dir;
                return Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    dense: true,
                    leading: FileTypeIcon(spec: fileSpec(path), size: 18),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(shortDir, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    onTap: () => tabs.open(path),
                  ),
                );
              })),
            ],
          ],
        ),
      ),
    );
  }
}


/// Prompts for a new file name. Shared by the editor toolbar and the empty state
/// so both validate identically.
Future<String?> _promptForNewFileName(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _NewFileDialog(),
  );
}

/// Owns its own [TextEditingController].
///
/// The controller cannot be disposed by the caller as soon as `showDialog`
/// returns: the route is still animating out and the [TextField] still has a
/// dependency on it, which trips a framework assertion
/// (`'_dependents.isEmpty': is not true`). Disposing inside the dialog's own
/// `dispose` happens after the subtree is gone.
class _NewFileDialog extends StatefulWidget {
  const _NewFileDialog();

  @override
  State<_NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<_NewFileDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New File'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'filename.dart',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

/// Reduces user input to a single, safe path component.
///
/// The New File dialog used to build `'${fs.rootPath}/$name'` and hand that to
/// `writeFile`. Because the result is an *absolute* path, it bypassed the
/// workspace containment check, so typing `../../databases/app.db` created and
/// truncated a file outside the workspace. Returning a bare name and letting
/// `FsService.resolve` treat it as workspace-relative closes that.
///
/// Returns null when the input is not a plain file name.
String? _safeRelativeFileName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return null;
  if (name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\\')) return null;
  if (name.contains('\u0000')) return null;
  return name;
}

/// Reports the line ending a buffer actually uses.
///
/// Mixed files report `Mixed`: claiming LF for a file that also contains CRLF would
/// send the reader hunting for a problem that is not there.
String detectLineEnding(String text) {
  final crlf = '\r\n'.allMatches(text).length;
  final lf = RegExp(r'(?<!\r)\n').allMatches(text).length;
  final cr = RegExp(r'\r(?!\n)').allMatches(text).length;
  final kinds = [crlf, lf, cr].where((n) => n > 0).length;
  if (kinds == 0) return 'LF';
  if (kinds > 1) return 'Mixed';
  if (crlf > 0) return 'CRLF';
  if (cr > 0) return 'CR';
  return 'LF';
}

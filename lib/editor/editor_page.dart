import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/constants.dart';
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
import '../workspace/file_explorer.dart';
import '../workspace/file_icons.dart';
import '../workspace/fs_service.dart';
import 'command_palette.dart';
import 'global_search.dart';
import 'quick_open.dart';
import 'shortcut_bar.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showFind = false;
  TabController? _tabController;
  int _tabControllerLength = -1;
  final AutocompleteEngine _autocomplete = AutocompleteEngine();

  @override
  void initState() {
    super.initState();
    setRunWithArgsCallback(_showRunWithArgsDialog);
    setRunCallback(_run);
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

  void _onTabTapped() {
    if (_tabController!.indexIsChanging) return;
    final manager = sl<TabManager>();
    final i = _tabController!.index;
    if (i >= 0 && i < manager.tabs.length && i != manager.activeIndex) {
      manager.activate(i);
    }
  }

  @override
  void dispose() {
    sl<TabManager>().removeListener(_onTabsChanged);
    _tabController?.dispose();
    _autocomplete.dispose();
    _previewServer.stop();
    _liveServer?.stop();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
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
      final sel = controller.selection;
      if (!sel.isCollapsed && sel.start >= 0) {
        Clipboard.setData(ClipboardData(
            text: controller.text.substring(sel.start, sel.end)));
      }
    } else if (key == LogicalKeyboardKey.keyX) {
      final sel = controller.selection;
      if (!sel.isCollapsed && sel.start >= 0) {
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
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New File'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'filename.dart',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
      final fs = sl<FsService>();
      final path = '${fs.rootPath}/$name';
      await fs.writeFile(path, '');
      await sl<TabManager>().open(path);
    }
  }

  void _duplicateLine(CodeController ctrl) {
    final text = ctrl.text;
    final selection = ctrl.selection;
    if (selection.start < 0) return;
    final lines = text.split('\n');
    int lineIndex = 0;
    int pos = 0;
    for (int i = 0; i < lines.length; i++) {
      final end = pos + lines[i].length;
      if (end >= selection.start || i == lines.length - 1) {
        lineIndex = i;
        break;
      }
      pos = end + 1;
    }
    final line = lines[lineIndex];
    final insertAt = pos + line.length;
    final suffix = insertAt >= text.length ? '' : '\n';
    final newText = text.replaceRange(insertAt, insertAt, '$suffix$line');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: insertAt + suffix.length + line.length),
    );
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
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (sel.start < 0) return;

    final prefix = _commentPrefix(languageId);
    final suffix = _commentSuffix(languageId);

    // Handle block comments (CSS, HTML, etc.)
    final isBlockComment = suffix.isNotEmpty;

    if (isBlockComment) {
      _toggleBlockComment(ctrl, text, sel, prefix, suffix);
      return;
    }

    // Line comment logic (existing)
    final lines = text.split('\n');
    int lineStart = 0;
    int lineIdx = 0;
    for (int i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      if (sel.start <= lineEnd || i == lines.length - 1) {
        lineIdx = i;
        break;
      }
      lineStart = lineEnd + 1;
    }

    final line = lines[lineIdx];
    final trimmed = line.trimLeft();
    final leading = line.substring(0, line.length - trimmed.length);

    if (trimmed.startsWith('$prefix ') || trimmed.startsWith(prefix)) {
      final stripped = trimmed.startsWith('$prefix ')
          ? trimmed.substring(prefix.length + 1)
          : trimmed.substring(prefix.length);
      lines[lineIdx] = '$leading$stripped';
    } else {
      lines[lineIdx] = '$leading$prefix $trimmed';
    }

    final newText = lines.join('\n');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start),
    );
  }

  void _toggleBlockComment(CodeController ctrl, String text, TextSelection sel, String prefix, String suffix) {
    // If there's a selection, wrap it
    if (!sel.isCollapsed && sel.start >= 0 && sel.end <= text.length) {
      final selectedText = text.substring(sel.start, sel.end);
      final trimmed = selectedText.trim();
      
      // Check if already wrapped
      if (trimmed.startsWith(prefix) && trimmed.endsWith(suffix)) {
        // Unwrap
        final unwrapped = trimmed.substring(prefix.length, trimmed.length - suffix.length);
        final newText = text.replaceRange(sel.start, sel.end, unwrapped);
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + unwrapped.length),
        );
      } else {
        // Wrap
        final wrapped = '$prefix $trimmed $suffix';
        final newText = text.replaceRange(sel.start, sel.end, wrapped);
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + wrapped.length),
        );
      }
      return;
    }

    // No selection - toggle comment on current line
    final lines = text.split('\n');
    int lineStart = 0;
    int lineIdx = 0;
    for (int i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      if (sel.start <= lineEnd || i == lines.length - 1) {
        lineIdx = i;
        break;
      }
      lineStart = lineEnd + 1;
    }

    final line = lines[lineIdx];
    final trimmed = line.trim();
    final leading = line.substring(0, line.length - trimmed.length);

    if (trimmed.startsWith(prefix) && trimmed.endsWith(suffix)) {
      // Uncomment
      final unwrapped = trimmed.substring(prefix.length, trimmed.length - suffix.length).trim();
      lines[lineIdx] = '$leading$unwrapped';
    } else {
      // Comment
      lines[lineIdx] = '$leading$prefix $trimmed $suffix';
    }

    final newText = lines.join('\n');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start),
    );
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
      listenable: sl<SettingsStore>(),
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
          return InteractiveViewer(
            key: ValueKey('zoom_${tab.filePath}'),
            minScale: 0.5,
            maxScale: 4.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            clipBehavior: Clip.none,
            child: editor,
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
    final url = _liveServer?.baseUrl;
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

  Future<void> _openFileBrowser({bool pickFolder = false}) async {
    const safChannel = MethodChannel(AppConstants.safChannel);
    const storageChannel = MethodChannel(AppConstants.storageChannel);
    try {
      final granted = await safChannel.invokeMethod<bool>('requestStoragePermission');
      if (granted != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission required to browse files.')),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Permission error: $e');
    }

    String current;
    try {
      current = await storageChannel.invokeMethod<String>('getExternalStorageDirectory') ?? '/storage/emulated/0';
    } catch (_) {
      current = '/storage/emulated/0';
    }
    List<FileSystemEntity> entries = [];

    void loadEntries() {
      try {
        entries = Directory(current).listSync()
          ..sort((a, b) {
            if (a is Directory && b is! Directory) return -1;
            if (a is! Directory && b is Directory) return 1;
            return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          });
      } catch (_) {
        entries = [];
      }
    }

    loadEntries();

    if (!mounted) return;

    // Get external storage directory for comparison in dialog
    String externalStorageRoot;
    try {
      externalStorageRoot = await storageChannel.invokeMethod<String>('getExternalStorageDirectory') ?? '/storage/emulated/0';
    } catch (_) {
      externalStorageRoot = '/storage/emulated/0';
    }

    if (!mounted) return;

    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              if (current != externalStorageRoot)
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    final parent = p.dirname(current);
                    if (parent != current) {
                      ss(() {
                        current = parent;
                        loadEntries();
                      });
                    }
                  },
                ),
              Expanded(
                child: Text(
                  p.basename(current).isEmpty ? 'Storage' : p.basename(current),
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            height: 420,
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'Empty or no permission',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final name = p.basename(e.path);
                      final isDir = e is Directory;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isDir
                              ? Icons.folder_rounded
                              : Icons.insert_drive_file_outlined,
                          color: isDir ? const Color(0xFFFFCA28) : null,
                          size: 22,
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 14)),
                        onTap: () {
                          if (isDir) {
                            ss(() {
                              current = e.path;
                              loadEntries();
                            });
                          } else {
                            Navigator.pop(ctx, e.path);
                          }
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (pickFolder)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: const Text('Select Folder'),
              ),
          ],
        ),
      ),
    );

    if (path != null && mounted) {
      if (pickFolder) {
        await sl<FsService>().setCustomRoot(path);
        setState(() {});
      } else {
        sl<TabManager>().open(path);
      }
    }
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
                  final hasUnsaved = tabs.hasUnsavedChanges;
                  if (hasUnsaved) {
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
                case 'open_folder':
                  _openFileBrowser(pickFolder: true);
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
                value: 'open_folder',
                child: Text('Open Folder'),
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
                ? _EmptyState(onOpenFile: (pickFolder) {
                    _openFileBrowser(pickFolder: pickFolder);
                  })
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
              future: sl<HighlightService>().indentWidthFor(tab.languageId),
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

  Future<void> _closeTabWithConfirm(int index) async {
    Haptics.onTabClose();
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
  String _encoding = 'UTF-8';
  static const _encodings = ['UTF-8', 'UTF-16', 'ISO-8859-1', 'Windows-1252'];

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              initialValue: _encoding,
              onSelected: (value) => setState(() => _encoding = value),
              itemBuilder: (_) => _encodings.map((e) => PopupMenuItem(value: e, child: Text(e))).toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_encoding),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _LineEndingSelector(),
          ],
        ),
      ),
    );
  }
}

class _LineEndingSelector extends StatefulWidget {
  @override
  State<_LineEndingSelector> createState() => _LineEndingSelectorState();
}

class _LineEndingSelectorState extends State<_LineEndingSelector> {
  String _lineEnding = 'LF';
  static const _endings = ['LF', 'CRLF', 'CR'];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: _lineEnding,
      onSelected: (value) => setState(() => _lineEnding = value),
      itemBuilder: (_) => _endings.map((e) => PopupMenuItem(value: e, child: Text(e))).toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_lineEnding),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatefulWidget {
  final void Function(bool pickFolder) onOpenFile;
  const _EmptyState({required this.onOpenFile});

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
              'Open a file to start editing',
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
                  onPressed: () => widget.onOpenFile(false),
                  icon: const Icon(Icons.file_open_rounded, size: 18),
                  label: const Text('Open File'),
                ),
                FilledButton.icon(
                  onPressed: () => widget.onOpenFile(true),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open Folder'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('New File'),
                        content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'filename.dart',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create')),
                        ],
                      ),
                    );
                    ctrl.dispose();
                    if (name != null && name.isNotEmpty) {
                      final fs = sl<FsService>();
                      final path = '${fs.rootPath}/$name';
                      await fs.writeFile(path, '');
                      await tabs.open(path);
                    }
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


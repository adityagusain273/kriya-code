import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';

import '../core/constants.dart';
import '../core/di.dart';
import '../execution/local/local_runner.dart';
import '../execution/termux_runner.dart';

/// Resolves `cd` inside Termux's filesystem.
///
/// Termux's shell cannot confirm the path for us — a stat from this UID is
/// denied — so the path is normalised and handed to the next command; bash
/// reports the real error then.
String resolveTermuxCwd(String cwd, String arg, {required String home}) {
  var target = arg.trim();
  if (target.isEmpty || target == '~') target = home;
  if (target.startsWith('~/')) target = '$home/${target.substring(2)}';
  if (!target.startsWith('/')) target = '$cwd/$target';

  final parts = <String>[];
  for (final segment in target.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return '/${parts.join('/')}';
}

List<String> parsePastedCommands(String text) {
  final rawLines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final commands = <String>[];
  for (final raw in rawLines) {
    final line = raw.trim();
    if (line.isNotEmpty) {
      commands.add(line);
    }
  }
  return commands;
}

class _TerminalSession {
  static final _TerminalSession instance = _TerminalSession._();

  final Terminal terminal = Terminal(maxLines: 10000);
  Pty? pty;
  bool isRunning = false;
  bool termuxInstalled = false;
  bool useTermux = false;
  bool useStandalone = false;
  String? standalonePath;
  StreamSubscription<String>? outputSub;
  bool initialized = false;

  String termuxCwd = '/data/data/com.termux/files/home';
  final StringBuffer line = StringBuffer();
  bool termuxBusy = false;
  bool inEscape = false;

  _TerminalSession._();

  void clear() {
    terminal.buffer.clear();
    terminal.setCursor(0, 0);
    terminal.notifyListeners();
  }

  void reset() {
    pty?.kill();
    pty = null;
    outputSub?.cancel();
    outputSub = null;
    terminal.buffer.clear();
    terminal.setCursor(0, 0);
    terminal.notifyListeners();
    initialized = false;
    isRunning = false;
    useTermux = false;
    useStandalone = false;
    standalonePath = null;
    termuxCwd = '/data/data/com.termux/files/home';
    line.clear();
    termuxBusy = false;
    inEscape = false;
  }
}

class TerminalWidget extends StatefulWidget {
  final String? workDir;
  final bool showToolbar;
  final ScrollController? scrollController;

  const TerminalWidget({
    super.key,
    this.workDir,
    this.showToolbar = false,
    this.scrollController,
  });

  static void resetSessionForTesting() {
    _TerminalSession.instance.reset();
  }

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  final _TerminalSession _session = _TerminalSession.instance;
  late final TerminalController terminalController;
  final ScrollController _terminalScrollController = ScrollController();
  bool _disposed = false;
  bool _cancelBatch = false;
  double _fontSize = 11.0;
  Offset _lastTapPosition = Offset.zero;

  static const termuxHome = '/data/data/com.termux/files/home';
  static const _termuxPrefix = '/data/data/com.termux/files/usr';

  Terminal get terminal => _session.terminal;
  Pty? get pty => _session.pty;
  set pty(Pty? val) => _session.pty = val;
  bool get _isRunning => _session.isRunning;
  set _isRunning(bool val) => _session.isRunning = val;
  bool get _termuxInstalled => _session.termuxInstalled;
  set _termuxInstalled(bool val) => _session.termuxInstalled = val;
  bool get _useTermux => _session.useTermux;
  set _useTermux(bool val) => _session.useTermux = val;
  bool get _useStandalone => _session.useStandalone;
  set _useStandalone(bool val) => _session.useStandalone = val;
  String? get _standalonePath => _session.standalonePath;
  set _standalonePath(String? val) => _session.standalonePath = val;
  StreamSubscription<String>? get _outputSub => _session.outputSub;
  set _outputSub(StreamSubscription<String>? val) => _session.outputSub = val;
  String get _termuxCwd => _session.termuxCwd;
  set _termuxCwd(String val) => _session.termuxCwd = val;
  StringBuffer get _line => _session.line;
  bool get _termuxBusy => _session.termuxBusy;
  set _termuxBusy(bool val) => _session.termuxBusy = val;
  bool get _inEscape => _session.inEscape;
  set _inEscape(bool val) => _session.inEscape = val;

  @override
  void initState() {
    super.initState();
    terminalController = TerminalController();
    terminal.onOutput = (data) {
      if (_useTermux) {
        _onTermuxInput(data);
        return;
      }
      pty?.write(Utf8Encoder().convert(data));
    };

    if (!_session.initialized) {
      _initShell();
    }
  }

  /// Picks how commands are executed.
  ///
  /// The old code checked `File('/data/data/com.termux/files/usr/bin/bash')
  /// .existsSync()`. Android denies one app even stat-ing another app's private
  /// directory, so `existsSync` was always false and Termux was never used. The
  /// only reliable signal is the package manager, reached through
  /// [TermuxRunner.isInstalled], plus the RUN_COMMAND grant.
  Future<void> _initShell() async {
    _termuxInstalled = await TermuxRunner.isInstalled();
    if (_disposed) return;
    if (_termuxInstalled) {
      // The grant dialog can hold this await for up to a minute; say something
      // instead of leaving a black screen behind the dialog.
      terminal.write('Termux detected — checking RUN_COMMAND permission…\r\n');
    }
    if (_termuxInstalled && await TermuxRunner.checkAvailability()) {
      if (_disposed) return;
      _useTermux = true;
      _startTermux();
      return;
    }
    if (_disposed) return;

    try {
      final runner = sl<LocalRunner>();
      if (await runner.hasRuntime('bash')) {
        if (_disposed) return;
        final root = await runner.runtimeRoot();
        if (_disposed) return;
        if (root != null) {
          final bashPrefix = '$root/bash';
          if (File('$bashPrefix/bin/bash').existsSync()) {
            _useStandalone = true;
            _standalonePath = bashPrefix;
          }
        }
      }
    } catch (_) {}
    _startShell();
  }

  /// App-private scratch directory the standalone shell treats as its home.
  ///
  /// HOME must not be the project directory: a user running `git credential
  /// store` or `npm login` in the terminal would otherwise drop
  /// `~/.git-credentials` / `~/.npmrc` into their project, where commit-all
  /// would push them to GitHub.
  Future<String> _terminalHome() async {
    final support = await getApplicationSupportDirectory();
    final home = '${support.path}/term-home';
    await Directory(home).create(recursive: true);
    return home;
  }

  Future<void> _startShell() async {
    if (_disposed) return;
    final shellPath = _findShell();
    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = 'xterm-256color';
    env['COLORTERM'] = 'truecolor';

    if (_useStandalone && _standalonePath != null) {
      final home = await _terminalHome();
      if (_disposed) return;
      env['HOME'] = home;
      env['PATH'] = '$_standalonePath/bin:${env['PATH'] ?? ''}';
      env['PREFIX'] = _standalonePath!;
      env['TMPDIR'] = home;

      final libPath = '$_standalonePath/lib';
      final currentLd = env['LD_LIBRARY_PATH'];
      env['LD_LIBRARY_PATH'] = currentLd != null ? '$libPath:$currentLd' : libPath;
    }

    final String cyan = '\x1B[1;36m';
    final String green = '\x1B[1;32m';
    final String reset = '\x1B[0m';
    final String welcome = _useStandalone
        ? '${cyan}Welcome to BCode Terminal!$reset\r\n\r\n${green}Available tools:$reset\r\n  - Version Control: git\r\n  - Node.js:         node, npm, npx\r\n  - Network:         curl, wget\r\n  - Archives:        tar, unzip, zip\r\n\r\n'
        : '${cyan}Welcome to BCode Terminal!$reset\r\n\r\n'
            '${green}Layer 1 — device shell:$reset app-private storage only.\r\n'
            '${green}Layer 2 — Termux:$reset install Termux and grant RUN_COMMAND\r\n'
            'to run npm, node, python and git against a full POSIX prefix.\r\n\r\n';

    terminal.write(welcome);
    if (_termuxInstalled) {
      terminal.write(
        '${cyan}Termux is installed but RUN_COMMAND is not granted.$reset\r\n'
        'Grant it in Settings → Termux Integration to switch this terminal to\r\n'
        'a Termux shell.\r\n\r\n',
      );
    }

    _session.initialized = true;
    pty = Pty.start(
      shellPath,
      columns: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
      rows: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      environment: env,
      workingDirectory: widget.workDir,
    );

    if (mounted) setState(() => _isRunning = true);

    // allowMalformed is essential. A chunked PTY stream routinely splits a
    // multi-byte UTF-8 sequence across two reads; the strict decoder threw
    // FormatException, the subscription had no onError, and the terminal simply
    // stopped updating.
    _outputSub?.cancel();
    _outputSub = pty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (data) {
        terminal.write(data);
      },
      onDone: () {
        _isRunning = false;
        if (mounted) setState(() {});
        terminal.write('\r\n[process exited]\r\n');
      },
      onError: (_) {
        _isRunning = false;
        if (mounted) setState(() {});
        terminal.write('\r\n[stream error]\r\n');
      },
    );

    pty!.exitCode.then((code) {
      _isRunning = false;
      if (mounted) setState(() {});
      terminal.write('\r\n[exited with code $code]\r\n');
    });
  }

  void _printTermuxIntro() {
    terminal.write(
      '\x1B[1;36mWelcome to Termux in BCode!\x1B[0m\r\n\r\n'
      '\x1B[1;32mRunning commands in Termux\x1B[0m\r\n'
      '  - npm / node / python / git all work here\r\n'
      '  - cd, clear and exit are handled locally\r\n'
      '  - type a command and press Enter; output returns when it finishes\r\n'
      '  - full-screen apps (vim, htop) need the Termux app button above\r\n\r\n',
    );
    if (widget.workDir != null) {
      terminal.write(
        '\x1B[33mNote:\x1B[0m project files edited in Kriya live in app storage,\r\n'
        'which Termux cannot read. Use the Run button for those projects.\r\n\r\n',
      );
    }
  }

  void _startTermux() {
    _session.initialized = true;
    _termuxCwd = termuxHome;
    _line.clear();
    _termuxBusy = false;
    _printTermuxIntro();
    if (mounted) setState(() => _isRunning = true);
    _prompt();

    // Ensure showcase suite is synced to Termux home if available in storage
    TermuxRunner.runCommand(
      command: '$_termuxPrefix/bin/bash',
      args: ['-c', 'if [ ! -d ~/showcase_suite ] && [ -d /sdcard/showcase_suite ]; then cp -rf /sdcard/showcase_suite ~/showcase_suite; fi'],
    );
  }

  void _prompt() {
    final shown = _termuxCwd == termuxHome
        ? '~'
        : (_termuxCwd.startsWith('$termuxHome/')
            ? '~${_termuxCwd.substring(termuxHome.length)}'
            : _termuxCwd);
    terminal.write('\x1B[1;32m$shown\x1B[0m \$ ');
  }

  void _onTermuxInput(String data) {
    if (data.contains('\n') || data.contains('\r')) {
      _handlePastedText(data);
      return;
    }

    for (final rune in data.runes) {
      // Arrow keys, Home/End and friends arrive as ESC sequences; inserting
      // their payload would type `[A` into the command line.
      if (_inEscape) {
        if (rune >= 0x40 && rune <= 0x7e) _inEscape = false;
        continue;
      }
      if (rune == 0x1b) {
        _inEscape = true;
        continue;
      }
      if (_termuxBusy) {
        if (rune == 0x03) {
          terminal.write(
            '^C\r\n\x1B[2m[RUN_COMMAND cannot signal a running command; '
            'it finishes in the background]\x1B[0m\r\n',
          );
        }
        continue;
      }

      final ch = String.fromCharCode(rune);
      if (ch == '\r' || ch == '\n') {
        terminal.write('\r\n');
        _runTermuxLine();
        continue;
      }
      if (ch == '\x7f' || ch == '\b') {
        final current = _line.toString();
        if (current.isEmpty) continue;
        _line
          ..clear()
          ..write(current.substring(0, current.length - 1));
        terminal.write('\b \b');
        continue;
      }
      if (ch == '\x03') {
        _line.clear();
        terminal.write('^C\r\n');
        _prompt();
        continue;
      }
      if (rune < 0x20) continue;

      _line.write(ch);
      terminal.write(ch);
    }
  }

  Future<void> _handlePastedText(String text) async {
    if (_termuxBusy) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Termux is busy running a command'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    final allCommands = parsePastedCommands(text);
    if (allCommands.isEmpty) return;

    final executable = allCommands.where((c) => !c.startsWith('#')).toList();

    if (executable.isEmpty) {
      for (final comment in allCommands) {
        terminal.write('\x1B[2m$comment\x1B[0m\r\n');
      }
      if (_useTermux) _prompt();
      return;
    }

    if (executable.length == 1) {
      final cmd = executable.first;
      if (_useTermux) {
        _line.write(cmd);
        terminal.write(cmd);
      } else {
        pty?.write(utf8.encode(cmd));
      }
      return;
    }

    final confirmed = await _confirmMultilinePaste(executable);
    if (!confirmed || !mounted || _disposed) return;

    if (!_useTermux) {
      pty?.write(utf8.encode(text.replaceAll('\r\n', '\n')));
      return;
    }

    _cancelBatch = false;
    for (final cmd in allCommands) {
      if (_cancelBatch || !mounted || _disposed) break;
      if (cmd.startsWith('#')) {
        terminal.write('\x1B[2m$cmd\x1B[0m\r\n');
        _prompt();
        continue;
      }
      terminal.write('$cmd\r\n');
      _line.clear();
      _line.write(cmd);
      await _runTermuxLine();
    }
  }

  Future<bool> _confirmMultilinePaste(List<String> commands) async {
    final count = commands.length;
    final isLarge = count > 5;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF21262D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF30363D)),
        ),
        title: Row(
          children: [
            Icon(
              isLarge ? Icons.warning_amber_rounded : Icons.content_paste_go,
              color: isLarge ? const Color(0xFFE3B341) : const Color(0xFF58A6FF),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Run $count commands?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLarge
                  ? 'Clipboard contains $count lines. Do you want to run them in Termux?'
                  : 'Execute these commands in Termux sequentially?',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  commands.take(8).join('\n') +
                      (commands.length > 8 ? '\n... and ${commands.length - 8} more lines' : ''),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF7EE787),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isLarge ? const Color(0xFFD29922) : const Color(0xFF238636),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isLarge ? 'Run Anyway' : 'Run Commands'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clipboard is empty'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    await _handlePastedText(text);
  }

  Future<void> _runCommandDirectly(String cmd) async {
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return;
    if (_useTermux) {
      terminal.write('$trimmed\r\n');
      _line.clear();
      _line.write(trimmed);
      await _runTermuxLine();
    } else {
      _line.clear();
      terminal.write('$trimmed\r\n');
      pty?.write(utf8.encode('$trimmed\n'));
    }
  }

  Future<void> _runTermuxLine() async {
    final raw = _line.toString().trim();
    _line.clear();

    if (raw.isEmpty) {
      _prompt();
      return;
    }

    if (raw == 'clear') {
      _clear();
      return;
    }

    if (raw == 'exit') {
      terminal.write('[Termux mode has no session to exit; press Restart to reset]\r\n');
      _prompt();
      return;
    }

    if (raw == 'cd' || raw.startsWith('cd ')) {
      _termuxCwd = resolveTermuxCwd(_termuxCwd, raw.substring(2), home: termuxHome);
      _prompt();
      return;
    }

    _termuxBusy = true;
    final result = await TermuxRunner.runCommand(
      command: '$_termuxPrefix/bin/bash',
      args: ['-lc', raw],
      workDir: _termuxCwd,
    );
    if (_disposed) return;
    _termuxBusy = false;

    _writeTermuxOutput(result.stdout);
    _writeTermuxOutput(result.stderr, color: '\x1B[31m');
    if (result.exitCode != 0 && result.exitCode != -1) {
      terminal.write('\x1B[2m[exit ${result.exitCode}]\x1B[0m\r\n');
    }
    _prompt();
  }

  /// Writes command output line by line, keeping blank lines.
  ///
  /// xterm needs CRLF, and skipping empty entries (the obvious loop) collapsed
  /// every blank line in a build log.
  void _writeTermuxOutput(String text, {String? color}) {
    if (text.isEmpty) return;
    final lines = text.replaceAll('\r\n', '\n').split('\n').toList();
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    for (final line in lines) {
      terminal.write(color == null ? '$line\r\n' : '$color$line\x1B[0m\r\n');
    }
  }

  String _findShell() {
    if (Platform.isAndroid) {
      if (_useStandalone && _standalonePath != null) {
        final bash = '$_standalonePath/bin/bash';
        if (File(bash).existsSync()) return bash;
      }
      for (final shell in [AppConstants.bashPath, AppConstants.androidShPath]) {
        if (File(shell).existsSync()) return shell;
      }
      return AppConstants.androidShPath;
    }
    return AppConstants.posixBashPath;
  }

  void _restart() {
    _cancelBatch = true;
    _session.reset();
    if (_terminalScrollController.hasClients) {
      _terminalScrollController.jumpTo(0.0);
    }
    _initShell();
  }

  void _clear() {
    _cancelBatch = true;
    _line.clear();
    _session.clear();
    if (_terminalScrollController.hasClients) {
      _terminalScrollController.jumpTo(0.0);
    }
    if (_useTermux) {
      _printTermuxIntro();
      _prompt();
    } else {
      _prompt();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelBatch = true;
    _terminalScrollController.dispose();
    terminalController.dispose();
    super.dispose();
  }

  Future<void> _showAndroidContextMenu() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final target = _lastTapPosition != Offset.zero
        ? _lastTapPosition
        : Offset(overlay.size.width / 2, overlay.size.height / 2);

    final position = RelativeRect.fromRect(
      Rect.fromCenter(center: target, width: 48, height: 48),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF21262D),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF30363D), width: 1),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'paste',
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.content_paste, size: 16, color: Color(0xFF58A6FF)),
              SizedBox(width: 10),
              Text('Paste', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.content_copy, size: 16, color: Colors.white70),
              SizedBox(width: 10),
              Text('Copy', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'select_all',
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.select_all, size: 16, color: Colors.white70),
              SizedBox(width: 10),
              Text('Select All', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'clear',
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.delete_outline, size: 16, color: Colors.white54),
              SizedBox(width: 10),
              Text('Clear', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'paste':
        await _pasteFromClipboard();
        break;
      case 'copy':
      case 'select_all':
        final text = terminal.buffer.toString();
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied terminal output to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        break;
      case 'clear':
        _clear();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showToolbar) _buildToolbar(),
        Expanded(
          child: Listener(
            onPointerDown: (e) => _lastTapPosition = e.position,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: _showAndroidContextMenu,
              child: TerminalView(
                terminal,
                controller: terminalController,
                scrollController: _terminalScrollController,
                autofocus: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                theme: const TerminalTheme(
                  cursor: Colors.white,
                  selection: Colors.white24,
                  foreground: Colors.white,
                  background: Color(0xFF0D1117),
                  black: Color(0xFF484f58),
                  red: Color(0xFFff7b72),
                  green: Color(0xFF7ee787),
                  yellow: Color(0xFFe3b341),
                  blue: Color(0xFF79c0ff),
                  magenta: Color(0xFFd2a8ff),
                  cyan: Color(0xFF79c0ff),
                  white: Color(0xFFc9d1d9),
                  brightBlack: Color(0xFF6e7681),
                  brightRed: Color(0xFFffa198),
                  brightGreen: Color(0xFF56d364),
                  brightYellow: Color(0xFFe3b341),
                  brightBlue: Color(0xFF58a6ff),
                  brightMagenta: Color(0xFFbc8cff),
                  brightCyan: Color(0xFF56d364),
                  brightWhite: Colors.white,
                  searchHitBackground: Colors.yellow,
                  searchHitBackgroundCurrent: Colors.orange,
                  searchHitForeground: Colors.black,
                ),
                textStyle: TerminalStyle(
                  fontSize: _fontSize,
                  fontFamily: 'monospace',
                ),
                keyboardAppearance: Brightness.dark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 38,
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _useTermux ? Icons.phone_android : Icons.terminal,
              size: 15,
              color: Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              _useTermux ? 'Termux' : (_useStandalone ? 'Bash' : 'Terminal'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_isRunning)
              Container(
                margin: const EdgeInsets.only(left: 6),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF56D364),
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Text('A-', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 18.0)),
              tooltip: 'Decrease font size',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
            ),
            Text('${_fontSize.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
            IconButton(
              icon: const Text('A+', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 18.0)),
              tooltip: 'Increase font size',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.paste, size: 16),
              color: const Color(0xFF58A6FF),
              onPressed: _pasteFromClipboard,
              tooltip: 'Paste from clipboard',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.play_circle_outline, size: 16, color: Color(0xFF58A6FF)),
              tooltip: 'Showcase & Tools',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
              onSelected: (cmd) => _runCommandDirectly(cmd),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'go run showcase_suite/08_go/main.go',
                  child: Text('Run Go: go run .../main.go'),
                ),
                PopupMenuItem(
                  value: 'rustc showcase_suite/09_rust/main.rs -o rust_app && ./rust_app',
                  child: Text('Run Rust: rustc ... && ./rust_app'),
                ),
                PopupMenuItem(
                  value: 'ruby showcase_suite/11_ruby/main.rb',
                  child: Text('Run Ruby: ruby .../main.rb'),
                ),
                PopupMenuItem(
                  value: 'node showcase_suite/03_typescript/main.ts',
                  child: Text('Run TypeScript: node .../main.ts'),
                ),
                PopupMenuItem(
                  value: 'pkill -9 node 2>/dev/null; node showcase_suite/15_fullstack_project/server.js',
                  child: Text('Run Fullstack: node .../server.js'),
                ),
                PopupMenuItem(
                  value: 'pkill -9 node',
                  child: Text('⚡ Free Port 3000 (pkill -9 node)', style: TextStyle(color: Color(0xFFE3B341))),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'pkg install -y golang rust ruby',
                  child: Text('⚡ Install Go, Rust & Ruby in Termux', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF58A6FF))),
                ),
                PopupMenuItem(
                  value: 'pkg install -y golang',
                  child: Text('Install Go in Termux'),
                ),
                PopupMenuItem(
                  value: 'pkg install -y rust',
                  child: Text('Install Rust in Termux'),
                ),
                PopupMenuItem(
                  value: 'pkg install -y ruby',
                  child: Text('Install Ruby in Termux'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.content_copy, size: 15),
              color: Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
              onPressed: () {
                final text = terminal.buffer.toString();
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Terminal output copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: 'Copy output',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 15),
              color: Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
              onPressed: _clear,
              tooltip: 'Clear terminal',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 15),
              color: Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
              onPressed: _restart,
              tooltip: 'Restart shell',
            ),
            if (_termuxInstalled)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 15),
                color: Colors.white54,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                onPressed: TermuxRunner.openTermux,
                tooltip: 'Open Termux app',
              ),
          ],
        ),
      ),
    );
  }
}

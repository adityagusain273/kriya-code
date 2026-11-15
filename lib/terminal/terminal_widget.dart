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

class TerminalWidget extends StatefulWidget {
  final String? workDir;
  final bool showToolbar;

  const TerminalWidget({super.key, this.workDir, this.showToolbar = false});

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late Terminal terminal;
  Pty? pty;
  bool _isRunning = false;
  bool _termuxInstalled = false;
  bool _useTermux = false;
  bool _useStandalone = false;
  String? _standalonePath;
  StreamSubscription<String>? _outputSub;
  bool _disposed = false;

  static const termuxHome = '/data/data/com.termux/files/home';
  static const _termuxPrefix = '/data/data/com.termux/files/usr';

  /// Termux mode state. There is no PTY here: RUN_COMMAND is a one-shot
  /// broadcast protocol, so the terminal echoes what is typed and sends complete
  /// lines to Termux.
  String _termuxCwd = termuxHome;
  final StringBuffer _line = StringBuffer();
  bool _termuxBusy = false;
  bool _inEscape = false;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        if (_useTermux) {
          _onTermuxInput(data);
          return;
        }
        pty?.write(Utf8Encoder().convert(data));
      },
    );
    _initShell();
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

    pty = Pty.start(
      shellPath,
      columns: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
      rows: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      environment: env,
      workingDirectory: widget.workDir,
    );

    setState(() => _isRunning = true);

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
        if (_disposed) return;
        terminal.write(data);
      },
      onDone: () {
        if (_disposed) return;
        setState(() => _isRunning = false);
        terminal.write('\r\n[process exited]\r\n');
      },
      onError: (_) {
        if (_disposed) return;
        setState(() => _isRunning = false);
        terminal.write('\r\n[stream error]\r\n');
      },
    );

    pty!.exitCode.then((code) {
      if (_disposed) return;
      setState(() => _isRunning = false);
      terminal.write('\r\n[exited with code $code]\r\n');
    });
  }

  void _startTermux() {
    _termuxCwd = termuxHome;
    _line.clear();
    _termuxBusy = false;
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
        '\x1B[33mNote:\x1B[0m project files edited in B Code live in app storage,\r\n'
        'which Termux cannot read. Use the Run button for those projects.\r\n\r\n',
      );
    }
    setState(() => _isRunning = true);
    _prompt();
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

  Future<void> _runTermuxLine() async {
    final raw = _line.toString().trim();
    _line.clear();

    if (raw.isEmpty) {
      _prompt();
      return;
    }

    if (raw == 'clear') {
      terminal.buffer.clear();
      terminal.notifyListeners();
      _prompt();
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
    pty?.kill();
    pty = null;
    terminal.buffer.clear();
    terminal.notifyListeners();
    if (_useTermux) {
      _startTermux();
    } else {
      _startShell();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _outputSub?.cancel();
    pty?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showToolbar) _buildToolbar(),
        Expanded(
          child: TerminalView(
            terminal,
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
            textStyle: const TerminalStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            keyboardAppearance: Brightness.dark,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            _useTermux ? Icons.phone_android : Icons.terminal,
            size: 16,
            color: Colors.white70,
          ),
          const SizedBox(width: 8),
          Text(
            _isRunning
                ? (_useTermux ? 'Termux — running' : _useStandalone ? 'Bash — running' : 'Terminal — running')
                : (_useTermux ? 'Termux' : _useStandalone ? 'Bash' : 'Terminal'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_termuxInstalled)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 16),
              color: Colors.white54,
              onPressed: TermuxRunner.openTermux,
              tooltip: 'Open Termux app',
            ),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 16),
            color: Colors.white54,
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
            icon: const Icon(Icons.delete_outline, size: 16),
            color: Colors.white54,
            onPressed: () {
              terminal.buffer.clear();
              terminal.notifyListeners();
            },
            tooltip: 'Clear terminal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white54,
            onPressed: _restart,
            tooltip: 'Restart shell',
          ),
        ],
      ),
    );
  }
}

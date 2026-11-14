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

  static const _termuxBash = '/data/data/com.termux/files/usr/bin/bash';

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        pty?.write(Utf8Encoder().convert(data));
      },
    );
    _initShell();
  }

  Future<void> _initShell() async {
    _termuxInstalled = await TermuxRunner.isInstalled();
    if (_termuxInstalled && File(_termuxBash).existsSync()) {
      _useTermux = true;
    } else {
      try {
        final runner = sl<LocalRunner>();
        if (await runner.hasRuntime('bash')) {
          final root = await runner.runtimeRoot();
          if (root != null) {
            final bashPrefix = '$root/bash';
            if (File('$bashPrefix/bin/bash').existsSync()) {
              _useStandalone = true;
              _standalonePath = bashPrefix;
            }
          }
        }
      } catch (_) {}
    }
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

    if (_useTermux) {
      env['HOME'] = '/data/data/com.termux/files/home';
      env['PATH'] = '/data/data/com.termux/files/usr/bin:${env['PATH'] ?? ''}';
      env['PREFIX'] = '/data/data/com.termux/files/usr';
      env['TMPDIR'] = '/data/data/com.termux/files/usr/tmp';
    } else if (_useStandalone && _standalonePath != null) {
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
    final String welcome = _useTermux 
        ? '${cyan}Welcome to Termux in BCode!$reset\r\n\r\n${green}Working with packages:$reset\r\n  - Search:    pkg search <query>\r\n  - Install:   pkg install <package>\r\n  - Uninstall: pkg uninstall <package>\r\n  - Upgrade:   pkg upgrade\r\n\r\n'
        : '${cyan}Welcome to BCode Terminal!$reset\r\n\r\n${green}Available tools:$reset\r\n  - Version Control: git\r\n  - Node.js:         node, npm, npx\r\n  - Network:         curl, wget\r\n  - Archives:        tar, unzip, zip\r\n\r\n';
    
    terminal.write(welcome);

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

  String _findShell() {
    if (Platform.isAndroid) {
      if (_useTermux && File(_termuxBash).existsSync()) {
        return _termuxBash;
      }
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
            onPressed: () {
              pty?.kill();
              _startShell();
            },
            tooltip: 'Restart shell',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/di.dart';
import '../terminal/terminal_widget.dart' show TerminalWidget;
import '../workspace/fs_service.dart';
import '../ai/ui/ai_assist_sheet.dart';
import 'runner_service.dart';

class ConsolePanel extends StatefulWidget {
  static const int tabOutput = 0;
  static const int tabTerminal = 1;

  final VoidCallback? onClose;

  const ConsolePanel({super.key, this.onClose});

  static void show(BuildContext context, {int initialIndex = tabOutput}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConsoleSheet(initialIndex: initialIndex),
    );
  }

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final ScrollController _scrollController = ScrollController();
  int _lastLineCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<RunnerService>();
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    if (runner.lines.length != _lastLineCount) {
      _lastLineCount = runner.lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: 220,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 36,
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Text('Output',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (runner.running)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF66BB6A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF66BB6A).withValues(alpha: 0.35),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF66BB6A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Running',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF66BB6A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (runner.running)
                    IconButton(
                      icon: const Icon(Icons.stop_circle, size: 18),
                      onPressed: runner.cancel,
                      tooltip: 'Stop execution',
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: runner.clear,
                    tooltip: 'Clear console',
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: widget.onClose,
                      tooltip: 'Hide console',
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: runner.lines.length,
                itemBuilder: (context, i) {
                  final line = runner.lines[i];
                  final color = line.isStderr
                      ? theme.colorScheme.error
                      : (line.isInput ? theme.colorScheme.primary : null);
                  return SelectableText(
                    line.text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: color,
                      fontWeight: line.isInput ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),
            if (runner.running)
              ConsoleInputBar(runner: runner),
          ],
        ),
      ),
    );
  }
}

class _ConsoleSheet extends StatefulWidget {
  final int initialIndex;

  const _ConsoleSheet({this.initialIndex = ConsolePanel.tabOutput});

  @override
  State<_ConsoleSheet> createState() => _ConsoleSheetState();
}

class _ConsoleSheetState extends State<_ConsoleSheet>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _animController;
  late double _heightFraction;
  bool _isFullScreen = false;

  double get _defaultHeightFraction =>
      widget.initialIndex == ConsolePanel.tabTerminal ? 0.75 : 0.6;

  @override
  void initState() {
    super.initState();
    _heightFraction = _defaultHeightFraction;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final start = _heightFraction;
    final anim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.reset();
    anim.addListener(() {
      if (mounted) {
        setState(() {
          _heightFraction = start + (target - start) * anim.value;
          _isFullScreen = _heightFraction >= 0.96;
        });
      }
    });
    _animController.forward();
  }

  void _toggleFullScreen() {
    if (_isFullScreen) {
      _animateTo(_defaultHeightFraction);
    } else {
      _animateTo(1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final totalHeight = media.size.height;
    final viewInsetBottom = media.viewInsets.bottom;
    final availableHeight = (totalHeight - viewInsetBottom).clamp(150.0, totalHeight);
    final sheetHeight = _isFullScreen
        ? availableHeight
        : (availableHeight * _heightFraction).clamp(150.0, availableHeight);
    final topInset = _isFullScreen ? media.padding.top : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsetBottom),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!_isFullScreen)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
            Container(
              key: const Key('console_sheet_container'),
              height: sheetHeight,
              padding: EdgeInsets.only(top: topInset),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: _isFullScreen
                    ? BorderRadius.zero
                    : const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      final delta = -details.primaryDelta! / availableHeight;
                      setState(() {
                        _heightFraction = (_heightFraction + delta).clamp(0.2, 1.0);
                        _isFullScreen = _heightFraction >= 0.96;
                      });
                    },
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -300 || _heightFraction > 0.85) {
                        _animateTo(1.0);
                      } else if (velocity > 300 && _heightFraction < 0.45) {
                        Navigator.of(context).pop();
                      } else if (_heightFraction < 0.25) {
                        Navigator.of(context).pop();
                      } else {
                        _animateTo(_defaultHeightFraction);
                      }
                    },
                    child: Container(
                      height: 28,
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            tabs: const [
                              Tab(text: 'Output'),
                              Tab(text: 'Terminal'),
                            ],
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white54,
                            indicatorColor: Colors.white,
                            dividerColor: Colors.transparent,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            size: 20,
                            color: Colors.white70,
                          ),
                          onPressed: _toggleFullScreen,
                          tooltip: _isFullScreen ? 'Exit full screen' : 'Full screen',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Close',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: const [
                        _OutputTab(),
                        _TerminalTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputTab extends StatefulWidget {
  const _OutputTab();

  @override
  State<_OutputTab> createState() => _OutputTabState();
}

class _OutputTabState extends State<_OutputTab> {
  final ScrollController _scrollController = ScrollController();
  int _lastLineCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<RunnerService>();
    final theme = Theme.of(context);

    if (runner.lines.length != _lastLineCount) {
      _lastLineCount = runner.lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 36,
          color: theme.colorScheme.surfaceContainerHigh,
          child: Row(
            children: [
              Text('Output',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (runner.running)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF66BB6A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF66BB6A).withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF66BB6A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Running',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF66BB6A),
                        ),
                      ),
                    ],
                  ),
                ),
              if (runner.running)
                IconButton(
                  icon: const Icon(Icons.stop_circle, size: 18),
                  onPressed: runner.cancel,
                  tooltip: 'Stop execution',
                ),
              IconButton(
                icon: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF00E676)),
                onPressed: () {
                  final text = runner.lines.map((l) => l.text).join('\n');
                  final err = runner.lastError;
                  final content = err != null ? 'Error: $err\nOutput:\n$text' : text;
                  AiAssistSheet.show(
                    context,
                    initialCode: content.isNotEmpty ? content : null,
                    contextDescription: 'Execution Output / Error',
                    defaultPrompt: 'Explain this output or error and show how to fix any issues.',
                  );
                },
                tooltip: 'Explain with AI',
              ),
              IconButton(
                icon: const Icon(Icons.content_copy, size: 18),
                onPressed: () {
                  final text = runner.lines.map((l) => l.text).join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                },
                tooltip: 'Copy output',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: runner.clear,
                tooltip: 'Clear console',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close console',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Builder(
          builder: (context) {
            ConsoleLine? stderrError;
            for (final l in runner.lines) {
              if (l.isStderr && (l.text.contains('Error') || l.text.contains('Exception') || l.text.contains('Traceback') || l.text.contains('SyntaxError'))) {
                stderrError = l;
                break;
              }
            }
            final errorText = runner.lastError ?? stderrError?.text;
            if (errorText == null) return const SizedBox.shrink();

            return _OutputErrorBot(
              errorText: errorText,
              onFix: () {
                final text = runner.lines.map((l) => l.text).join('\n');
                AiAssistSheet.show(
                  context,
                  initialCode: text.isNotEmpty ? text : null,
                  contextDescription: 'Execution Output / Error',
                  diagnosticsSummary: [errorText],
                  defaultPrompt: 'Fix this error:\n$errorText\nExplain the cause and provide the corrected working code.',
                );
              },
            );
          },
        ),
        Expanded(
          child: runner.lines.isEmpty
              ? Center(
                  child: Text(
                    runner.running
                        ? 'Running...'
                        : (runner.lastError == null ? 'No output yet' : 'Execution failed'),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: runner.lines.length,
                  itemBuilder: (context, i) {
                    final line = runner.lines[i];
                    final color = line.isStderr
                        ? theme.colorScheme.error
                        : (line.isInput ? theme.colorScheme.primary : null);
                    return SelectableText(
                      line.text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: color,
                        fontWeight: line.isInput ? FontWeight.w600 : FontWeight.normal,
                      ),
                    );
                  },
                ),
        ),
        if (runner.running)
          ConsoleInputBar(
            runner: runner,
            onInputSent: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients &&
                    _scrollController.position.maxScrollExtent > 0) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                  );
                }
              });
            },
          ),
      ],
    );
  }
}

class ConsoleInputBar extends StatefulWidget {
  final RunnerService runner;
  final VoidCallback? onInputSent;

  const ConsoleInputBar({
    super.key,
    required this.runner,
    this.onInputSent,
  });

  @override
  State<ConsoleInputBar> createState() => _ConsoleInputBarState();
}

class _ConsoleInputBarState extends State<ConsoleInputBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final text = value ?? _controller.text;
    widget.runner.sendStdin(text);
    _controller.clear();
    _focusNode.requestFocus();
    widget.onInputSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.primary.withValues(alpha: 0.8),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: _submit,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: cs.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter input...',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, size: 18),
              color: cs.primary,
              tooltip: 'Send input',
              onPressed: () => _submit(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalTab extends StatelessWidget {
  const _TerminalTab();

  @override
  Widget build(BuildContext context) {
    final workDir = sl<FsService>().rootPath;
    return TerminalWidget(
      workDir: workDir,
      showToolbar: true,
    );
  }
}

class _OutputErrorBot extends StatefulWidget {
  final String errorText;
  final VoidCallback onFix;

  const _OutputErrorBot({required this.errorText, required this.onFix});

  @override
  State<_OutputErrorBot> createState() => _OutputErrorBotState();
}

class _OutputErrorBotState extends State<_OutputErrorBot>
    with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  late final AnimationController _waveController;
  late final Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _waveAnimation = Tween<double>(begin: -0.25, end: 0.25).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOutSine),
    );

    _slideController.forward();
    _waveController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _slideController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E1903), Color(0xFF161F2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onFix,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF372005), Color(0xFF1E1303)],
                            ),
                            border: Border.all(
                              color: const Color(0xFFFFB300),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.smart_toy_rounded,
                            size: 18,
                            color: Color(0xFFFFB300),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: _waveAnimation,
                            builder: (context, _) => Transform.rotate(
                              angle: _waveAnimation.value,
                              alignment: Alignment.bottomLeft,
                              child: const Icon(
                                Icons.waving_hand_rounded,
                                size: 14,
                                color: Color(0xFFFFD54F),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          children: [
                            Text(
                              'Click me to fix this',
                              style: TextStyle(
                                color: Color(0xFFFFB300),
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: Color(0xFFFFB300),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.errorText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFFFFB300),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

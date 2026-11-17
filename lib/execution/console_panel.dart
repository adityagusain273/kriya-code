import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/di.dart';
import '../terminal/terminal_widget.dart' show TerminalWidget;
import '../workspace/fs_service.dart';
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
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                if (notification.extent <= 0.16) {
                  Navigator.of(context).pop();
                  return true;
                }
                return false;
              },
              child: DraggableScrollableSheet(
                initialChildSize: 0.6,
                minChildSize: 0.15,
                maxChildSize: 0.9,
                builder: (context, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 40,
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
                      const Divider(height: 1),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _OutputTab(scrollController: scrollController),
                            const _TerminalTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputTab extends StatefulWidget {
  final ScrollController scrollController;

  const _OutputTab({required this.scrollController});

  @override
  State<_OutputTab> createState() => _OutputTabState();
}

class _OutputTabState extends State<_OutputTab> {
  int _lastLineCount = 0;

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<RunnerService>();
    final theme = Theme.of(context);

    if (runner.lines.length != _lastLineCount) {
      _lastLineCount = runner.lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.scrollController.hasClients &&
            widget.scrollController.position.maxScrollExtent > 0) {
          widget.scrollController.animateTo(
            widget.scrollController.position.maxScrollExtent,
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
        if (runner.lastError != null)
          Container(
            padding: const EdgeInsets.all(8.0),
            color: theme.colorScheme.errorContainer,
            child: Text(
              runner.lastError!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12),
            ),
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
                  controller: widget.scrollController,
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
                if (widget.scrollController.hasClients &&
                    widget.scrollController.position.maxScrollExtent > 0) {
                  widget.scrollController.animateTo(
                    widget.scrollController.position.maxScrollExtent,
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

class _TerminalTab extends StatefulWidget {
  const _TerminalTab();

  @override
  State<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<_TerminalTab> {
  @override
  Widget build(BuildContext context) {
    final workDir = sl<FsService>().rootPath;
    return TerminalWidget(workDir: workDir);
  }
}

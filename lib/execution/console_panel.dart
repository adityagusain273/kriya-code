import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/di.dart';
import '../terminal/terminal_widget.dart' show TerminalWidget;
import '../workspace/fs_service.dart';
import 'runner_service.dart';

class ConsolePanel extends StatelessWidget {
  final VoidCallback? onClose;

  const ConsolePanel({super.key, this.onClose});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ConsoleSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<RunnerService>();
    final theme = Theme.of(context);
    return Container(
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
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                    tooltip: 'Hide console',
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: runner.lines.length,
              itemBuilder: (context, i) {
                final line = runner.lines[i];
                final color = line.isStderr ? theme.colorScheme.error : null;
                return SelectableText(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                    color: color,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleSheet extends StatefulWidget {
  const _ConsoleSheet();

  @override
  State<_ConsoleSheet> createState() => _ConsoleSheetState();
}

class _ConsoleSheetState extends State<_ConsoleSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
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
    );
  }
}

class _OutputTab extends StatelessWidget {
  final ScrollController scrollController;

  const _OutputTab({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<RunnerService>();
    final theme = Theme.of(context);
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
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
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
                    runner.lastError == null ? 'No output yet' : 'Execution failed',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: runner.lines.length,
                  itemBuilder: (context, i) {
                    final line = runner.lines[i];
                    final color = line.isStderr ? theme.colorScheme.error : null;
                    return SelectableText(
                      line.text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: color,
                      ),
                    );
                  },
                ),
        ),
      ],
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

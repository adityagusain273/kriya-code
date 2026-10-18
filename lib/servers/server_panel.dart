import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/di.dart';
import '../editor/preview/preview_page.dart';
import 'dev_server.dart';
import 'server_monitor.dart';

class ServerPanel extends StatefulWidget {
  const ServerPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ServerPanel(),
    );
  }

  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await sl<ServerMonitor>().refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _addManual() async {
    final portCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Dev Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '3000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'My Server',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    portCtrl.dispose();
    nameCtrl.dispose();
    if (result == true) {
      final port = int.tryParse(portCtrl.text.trim());
      if (port != null && port > 0 && port < 65536) {
        sl<ServerMonitor>().addServer(
          port,
          name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        );
      }
    }
  }

  void _openPreview(BuildContext context, DevServer server) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          baseUrl: server.url,
          relativePath: '',
          title: server.name,
        ),
      ),
    );
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ChangeNotifierProvider.value(
      value: sl<ServerMonitor>(),
      child: Consumer<ServerMonitor>(
        builder: (context, monitor, _) {
          final servers = monitor.servers;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (context, scrollCtrl) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.dns_rounded, size: 20, color: cs.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Dev Servers',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      if (_refreshing)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Probe ports',
                          onPressed: _refresh,
                        ),
                      IconButton(
                        icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: cs.primary),
                        tooltip: 'Add server',
                        onPressed: _addManual,
                      ),
                    ],
                  ),
                ),
                if (servers.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_tethering_off_rounded, size: 48,
                              color: cs.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            'No dev servers detected',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Start a server in the terminal, then tap refresh.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.35),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: servers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _ServerCard(
                            server: servers[i],
                            onOpenPreview: () => _openPreview(context, servers[i]),
                            onCopyUrl: () => _copyUrl(servers[i].url),
                            onRemove: () => monitor.removeServer(servers[i].port),
                          ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13,
                          color: cs.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Servers on ports 3000, 4000, 5000, 8000, 8080, 8888 are auto-detected.',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final DevServer server;
  final VoidCallback onOpenPreview;
  final VoidCallback onCopyUrl;
  final VoidCallback onRemove;

  const _ServerCard({
    required this.server,
    required this.onOpenPreview,
    required this.onCopyUrl,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alive = server.isAlive;
    final statusColor = alive ? const Color(0xFF66BB6A) : cs.onSurface.withValues(alpha: 0.3);

    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: alive
                        ? [BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 6)]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    server.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  alive ? 'Running' : 'Offline',
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                  onSelected: (v) {
                    if (v == 'remove') onRemove();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onCopyUrl,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 5),
                    Text(
                      server.url,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(Icons.copy_rounded, size: 12, color: cs.onSurface.withValues(alpha: 0.3)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: alive ? onOpenPreview : null,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                  label: const Text('Open Preview'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onCopyUrl,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy URL'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

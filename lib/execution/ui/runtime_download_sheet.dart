import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../runtime_catalog.dart';
import '../runtime_download_service.dart';

/// Shows a bottom sheet offering to download the required runtime before execution.
///
/// Returns true when the runtime is successfully installed, false if the user
/// cancels or dismisses.
Future<bool> showRuntimeDownloadSheet(
  BuildContext context, {
  required String runtimeId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => RuntimeDownloadSheet(runtimeId: runtimeId),
  );
  return result ?? false;
}

class RuntimeDownloadSheet extends StatefulWidget {
  final String runtimeId;

  const RuntimeDownloadSheet({super.key, required this.runtimeId});

  @override
  State<RuntimeDownloadSheet> createState() => _RuntimeDownloadSheetState();
}

class _RuntimeDownloadSheetState extends State<RuntimeDownloadSheet> {
  late final RuntimeDownloadService _downloads = sl<RuntimeDownloadService>();

  RuntimePreview? _preview;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_onStateChange);
    _loadPreview();
  }

  @override
  void dispose() {
    _downloads.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (!mounted) return;
    final state = _downloads.stateFor(widget.runtimeId);
    if (state.phase == RuntimeDownloadPhase.installed) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  Future<void> _loadPreview() async {
    final preview = await _downloads.inspect(widget.runtimeId);
    if (mounted) setState(() => _preview = preview);
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  IconData _iconForRuntime(String id) {
    switch (id) {
      case 'cpython':
        return Icons.terminal_rounded;
      case 'clang':
        return Icons.memory_rounded;
      case 'openjdk':
        return Icons.coffee_rounded;
      case 'nodejs':
        return Icons.javascript_rounded;
      case 'bash':
        return Icons.code_rounded;
      default:
        return Icons.play_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = specForRuntime(widget.runtimeId);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = _downloads.stateFor(widget.runtimeId);
    final phase = state.phase;

    final versionStr = _preview?.version ?? spec?.approxVersion ?? '';
    final sizeStr = _preview != null
        ? _formatBytes(_preview!.sizeBytes)
        : '≈${spec?.defaultSizeMb ?? 25} MB';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconForRuntime(widget.runtimeId),
                    size: 26,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec?.title ?? 'Runtime Required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (versionStr.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'v$versionStr',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            sizeStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              spec?.description ??
                  'This runtime is required to execute your code offline.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (phase == RuntimeDownloadPhase.resolving) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Connecting to package repository…'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _downloads.cancel(widget.runtimeId),
                child: const Text('Cancel'),
              ),
            ] else if (phase == RuntimeDownloadPhase.downloading) ...[
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    state.currentPackage.isNotEmpty
                        ? 'Fetching ${state.currentPackage}…'
                        : 'Downloading…',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '${_formatBytes(state.receivedBytes)} / ${_formatBytes(state.totalBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _downloads.cancel(widget.runtimeId),
                child: const Text('Cancel'),
              ),
            ] else if (phase == RuntimeDownloadPhase.installing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Extracting and verifying packages…',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ] else ...[
              if (phase == RuntimeDownloadPhase.failed && state.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  phase == RuntimeDownloadPhase.failed
                      ? 'Retry & Run ($sizeStr)'
                      : 'Download & Run ($sizeStr)',
                ),
                onPressed: () => _downloads.download(widget.runtimeId),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

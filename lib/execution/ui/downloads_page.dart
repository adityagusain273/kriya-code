import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../../monetization/entitlement_service.dart';
import '../../monetization/pro_paywall_sheet.dart';
import '../../monetization/runtime_unlock_flow.dart';
import '../runtime_catalog.dart';
import '../runtime_download_service.dart';

class DownloadsPage extends StatefulWidget {
  final String? focusRuntimeId;

  const DownloadsPage({super.key, this.focusRuntimeId});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  RuntimeDownloadService get _downloads => sl<RuntimeDownloadService>();

  final Map<String, RuntimePreview?> _previews = {};

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_onChange);
    _loadPreviews();
    final focus = widget.focusRuntimeId;
    if (focus != null) {
      final state = _downloads.stateFor(focus);
      if (state.phase == RuntimeDownloadPhase.idle ||
          state.phase == RuntimeDownloadPhase.failed) {
        _downloads.download(focus);
      }
    }
  }

  @override
  void dispose() {
    _downloads.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  /// Asks the repository what each runtime currently is, so the list can show a
  /// version and a download size before anything is fetched.
  Future<void> _loadPreviews() async {
    for (final spec in runtimeCatalog.values) {
      if (_previews.containsKey(spec.runtimeId)) continue;
      final preview = await _downloads.inspect(spec.runtimeId);
      if (!mounted) return;
      setState(() => _previews[spec.runtimeId] = preview);
    }
  }

  String _sizeLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _requestDownload(RuntimeSpec spec) async {
    final unlocked = await ensureRuntimeUnlocked(
      context,
      runtimeId: spec.runtimeId,
      runtimeTitle: spec.title,
    );
    if (unlocked) {
      _downloads.download(spec.runtimeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final specs = runtimeCatalog.values.toList();
    final entitlements = sl<EntitlementService>();
    final isPro = entitlements.isRuntimeUnlocked('');

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!isPro)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: MissionBanner(
                onGoAdFree: () async {
                  final activated = await showProPaywallSheet(context);
                  if (activated && mounted) setState(() {});
                },
              ),
            ),
          for (final spec in specs)
            _DownloadCard(
              spec: spec,
              state: _downloads.stateFor(spec.runtimeId),
              installed: _downloads.isInstalled(spec.runtimeId),
              unlocked: entitlements.isRuntimeUnlocked(spec.runtimeId),
              onDownload: () => _requestDownload(spec),
              onCancel: () => _downloads.cancel(spec.runtimeId),
              onDelete: () => _downloads.remove(spec.runtimeId),
              sizeLabel: _sizeLabel,
              preview: _previews[spec.runtimeId],
            ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final RuntimeSpec spec;
  final RuntimeDownloadState state;
  final bool installed;
  final bool unlocked;

  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final String Function(int) sizeLabel;

  /// Repository state for this runtime, when it could be read.
  final RuntimePreview? preview;

  const _DownloadCard({
    required this.spec,
    required this.state,
    required this.installed,
    required this.unlocked,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.sizeLabel,
    this.preview,
  });

  /// Version and download weight, so installing a runtime is an informed choice.
  String _previewLabel(RuntimePreview preview) {
    final parts = <String>[];
    if (preview.version != null) parts.add('v${preview.version}');
    parts.add(sizeLabel(preview.sizeBytes));
    parts.add('${preview.packageCount} packages');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final phase = state.phase;
    final downloading = phase == RuntimeDownloadPhase.downloading ||
        phase == RuntimeDownloadPhase.resolving ||
        phase == RuntimeDownloadPhase.installing;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(spec.description,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                      if (preview case final preview? when !installed) ...[
                        const SizedBox(height: 4),
                        Text(
                          _previewLabel(preview),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ],
                  ),
                ),
                if (installed)
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Installed', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  )
                else if (downloading)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      if (phase != RuntimeDownloadPhase.installing) ...[
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.red.shade300,
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  )
                else ...[
                  if (phase == RuntimeDownloadPhase.failed)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Retry',
                      onPressed: onDownload,
                    ),
                  FilledButton.icon(
                    icon: Icon(
                      unlocked
                          ? Icons.download_rounded
                          : Icons.lock_open_rounded,
                      size: 16,
                    ),
                    onPressed: onDownload,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    label: Text(phase == RuntimeDownloadPhase.failed
                        ? 'Retry'
                        : (unlocked ? 'Download' : 'Unlock')),
                  ),
                ],
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: phase == RuntimeDownloadPhase.installing ? null : state.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      phase == RuntimeDownloadPhase.installing
                          ? 'Extracting and verifying packages…'
                          : state.totalBytes > 0
                              ? '${state.currentPackage} — '
                                  '${sizeLabel(state.receivedBytes)} of ${sizeLabel(state.totalBytes)}'
                                  ' (${(state.progress! * 100).toStringAsFixed(0)}%)'
                              : phase == RuntimeDownloadPhase.resolving
                                  ? 'Resolving packages…'
                                  : 'Starting download…',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ),
                  if (phase == RuntimeDownloadPhase.downloading)
                    Text('↓ ${sizeLabel(state.receivedBytes)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white54)),
                ],
              ),
            ],
            if (phase == RuntimeDownloadPhase.failed && state.error != null) ...[
              const SizedBox(height: 8),
              Text('Error: ${state.error}',
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.red.shade300)),
            ],
            if (installed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red.shade300),
                  child: const Text('Delete'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}




import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../workspace/file_icons.dart';

enum ExitChoice { save, discard, exit, cancel }

/// Asks before closing the editor. Returns null when dismissed with back or a
/// barrier tap, which means stay.
Future<ExitChoice?> showExitDialog(
  BuildContext context, {
  required List<String> dirtyFiles,
}) {
  Haptics.light();
  return showDialog<ExitChoice>(
    context: context,
    builder: (_) => _ExitDialog(dirtyFiles: dirtyFiles),
  );
}

class _ExitDialog extends StatelessWidget {
  final List<String> dirtyFiles;

  const _ExitDialog({required this.dirtyFiles});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dirty = dirtyFiles.isNotEmpty;
    final listed = dirtyFiles.take(3).toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: dirty ? cs.errorContainer : cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    dirty
                        ? Icons.warning_amber_rounded
                        : Icons.power_settings_new_rounded,
                    size: 26,
                    color: dirty ? cs.onErrorContainer : cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                dirty ? 'Save before you leave?' : 'Leave B Code?',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                dirty
                    ? dirtyFiles.length == 1
                        ? 'One file has unsaved changes.'
                        : '${dirtyFiles.length} files have unsaved changes.'
                    : 'Your tabs will be waiting.',
                style: text.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
              if (dirty) ...[
                const SizedBox(height: 16),
                _DirtyFileList(
                  files: listed,
                  hidden: dirtyFiles.length - listed.length,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    if (dirty) {
                      Haptics.onSave();
                    } else {
                      Haptics.light();
                    }
                    Navigator.pop(
                      context,
                      dirty ? ExitChoice.save : ExitChoice.exit,
                    );
                  },
                  child: Text(dirty ? 'Save and exit' : 'Exit'),
                ),
              ),
              if (dirty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () {
                      Haptics.medium();
                      Navigator.pop(context, ExitChoice.discard);
                    },
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    child: const Text('Discard changes and exit'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, ExitChoice.cancel),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirtyFileList extends StatelessWidget {
  final List<String> files;
  final int hidden;

  const _DirtyFileList({required this.files, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.bodySmall;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final path in files)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  FileTypeIcon(spec: fileSpec(path), size: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      path.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'and $hidden more',
                style: label?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

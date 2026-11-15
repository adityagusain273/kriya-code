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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: (dirty ? cs.error : cs.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: (dirty ? cs.error : cs.primary).withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  dirty
                      ? Icons.warning_amber_rounded
                      : Icons.power_settings_new_rounded,
                  size: 28,
                  color: dirty ? cs.error : cs.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                dirty ? 'Save before you leave?' : 'Leave B Code?',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dirty
                    ? dirtyFiles.length == 1
                        ? 'One file has unsaved changes.'
                        : '${dirtyFiles.length} files have unsaved changes.'
                    : 'Your tabs will be waiting.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (dirty) ...[
                const SizedBox(height: 18),
                _DirtyFileList(
                  files: listed,
                  hidden: dirtyFiles.length - listed.length,
                ),
              ],
              const SizedBox(height: 24),
              if (!dirty)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton.tonal(
                          onPressed: () =>
                              Navigator.pop(context, ExitChoice.cancel),
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.surfaceContainerHighest,
                            foregroundColor: cs.onSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: () {
                            Haptics.light();
                            Navigator.pop(context, ExitChoice.exit);
                          },
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Exit',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Haptics.onSave();
                      Navigator.pop(context, ExitChoice.save);
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Save and exit',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Haptics.medium();
                      Navigator.pop(context, ExitChoice.discard);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Discard changes and exit',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, ExitChoice.cancel),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < files.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  FileTypeIcon(spec: fileSpec(files[i]), size: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      files[i].split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hidden > 0) ...[
            Divider(
              height: 1,
              thickness: 0.5,
              color: cs.outlineVariant.withValues(alpha: 0.25),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Text(
                'and $hidden more',
                style: label?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

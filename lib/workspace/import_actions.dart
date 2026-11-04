import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/archive_extractor.dart';
import '../core/di.dart';
import 'device_import_service.dart';
import 'fs_service.dart';

/// Brings work into the workspace from the device.
///
/// Android has no "give me a path" API. A path has to come from the Storage Access
/// Framework, whose grant is per-app and expressed as a `content://` URI rather than a
/// filesystem path, while everything else here — run configs, the live server, git,
/// Termux — is built on one plain directory tree. So the URI is resolved natively and
/// the bytes land inside that tree.
///
/// Each entry point owns its progress dialog and its error reporting, and returns null
/// when the user backs out or the import fails. Callers only decide what to do next
/// with the result, which is what let onboarding and the editor page drift into two
/// copies of the same flow — one of which hardcoded `/storage/emulated/0/Download` and
/// so silently found nothing on any device that had not granted storage access.

/// Picks a single file off the device and copies it to the workspace root.
Future<DeviceImport?> importFileFromDevice(BuildContext context) async {
  try {
    return await DeviceImportService.instance.pickFile();
  } catch (e) {
    _toast(context, 'Could not import that file: $e', isError: true);
    return null;
  }
}

/// Picks a folder off the device and copies the whole tree into the workspace.
///
/// Returns the imported folder. A real project is thousands of files, so the dialog
/// reports a running count rather than spinning without moving.
Future<DeviceImport?> importFolderFromDevice(BuildContext context) async {
  final service = DeviceImportService.instance;
  final progress = ValueNotifier<DeviceImportProgress?>(null);
  final dialog = _ProgressDialog(
    context: context,
    notifier: progress,
    render: (v) => v == null
        ? 'Copying your project…'
        : 'Copying ${v.name} · ${v.files} files (${formatBytes(v.bytes)})',
  );

  // Attached before the picker is even answered: the copy starts the instant the user
  // confirms, and subscribing afterwards would miss the opening updates.
  final subscription = service.progress.listen((value) => progress.value = value);

  try {
    final imported = await service.pickFolder();
    if (imported == null || !context.mounted) return null;
    _toast(
      context,
      'Imported ${_relative(imported.path)}'
          '${imported.files > 1 ? ' · ${imported.files} files · ${formatBytes(imported.bytes)}' : ''}'
          '${imported.truncated ? ' · stopped at the size limit, so this is partial' : ''}',
    );
    return imported;
  } catch (e) {
    if (context.mounted) {
      _toast(context, 'Could not open that folder: $e', isError: true);
    }
    return null;
  } finally {
    await subscription.cancel();
    dialog.close();
    progress.dispose();
  }
}

/// Picks an archive off the device, copies it in, and unpacks it in one step.
///
/// Returns the folder it unpacked into, not the archive. Somebody handed a
/// `project.tar.gz` over chat previously had no way in at all: the only unpack entry
/// point lived in onboarding and only listed `.zip` files already inside the
/// workspace.
Future<DeviceImport?> importArchiveFromDevice(BuildContext context) async {
  final picked = await importFileFromDevice(context);
  if (picked == null || !context.mounted) return null;

  final name = p.basename(picked.path);
  if (!ArchiveExtractor.isArchiveName(name)) {
    _toast(context, '$name is not an archive B Code can unpack.', isError: true);
    return null;
  }

  return unpackArchive(context, picked.path);
}

/// Saves [path] to a location the user picks in the system file dialog.
Future<bool> exportFileToDevice(BuildContext context, String path) async {
  try {
    final saved = await DeviceImportService.instance.exportFile(path);
    if (context.mounted && saved) {
      _toast(context, 'Exported ${p.basename(path)}');
    }
    return saved;
  } catch (e) {
    if (context.mounted) {
      _toast(context, 'Could not export that file: $e', isError: true);
    }
    return false;
  }
}

/// Unpacks [archivePath] into a fresh sibling folder, with progress.
///
/// Returns the folder, or null if it was refused. The archive itself is left alone: if
/// extraction fails halfway it is then the only copy of the user's data.
Future<DeviceImport?> unpackArchive(
  BuildContext context,
  String archivePath,
) async {
  final name = p.basename(archivePath);
  final parent = p.dirname(archivePath);
  final target = _unusedFolderIn(parent, ArchiveExtractor.folderNameFor(name));

  final progress = ValueNotifier<DeviceImportProgress?>(null);
  final dialog = _ProgressDialog(
    context: context,
    notifier: progress,
    render: (v) => v == null
        ? 'Unpacking $name…'
        : 'Unpacking $name · ${v.files} files (${formatBytes(v.bytes)})',
  );

  try {
    await ArchiveExtractor.extractWithProgress(
      File(archivePath),
      target,
      (entries, bytes) {
        progress.value =
            DeviceImportProgress(name: name, files: entries, bytes: bytes);
      },
    );
  } catch (e) {
    if (context.mounted) {
      _toast(context, 'Could not unpack $name: $e', isError: true);
    }
    return null;
  } finally {
    dialog.close();
    progress.dispose();
  }

  if (!context.mounted) return null;
  _toast(context, 'Unpacked into ${_relative(target)}');
  return DeviceImport(path: target, files: 0, bytes: 0);
}

/// First path in [parent] of the form `<name>`, `<name>_2`, ... that is free.
///
/// Unpacking into a folder that already exists would merge two projects into one, which
/// is far worse than ending up with `project_2`.
String _unusedFolderIn(String parent, String name) {
  var candidate = p.join(parent, name);
  var counter = 1;
  while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
    candidate = p.join(parent, '${name}_${++counter}');
  }
  return candidate;
}

String _relative(String absolute) {
  try {
    final rel = sl<FsService>().relativeToRoot(absolute);
    return rel.isEmpty || rel == '.' ? p.basename(absolute) : rel;
  } catch (_) {
    return p.basename(absolute);
  }
}

void _toast(BuildContext context, String message, {bool isError = false}) {
  if (!context.mounted) return;
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      backgroundColor: isError ? scheme.error : null,
      duration: const Duration(seconds: 5),
    ));
}

/// Modal progress that cannot be dismissed and is safe to close more than once.
class _ProgressDialog {
  _ProgressDialog({
    required BuildContext context,
    required ValueListenable<DeviceImportProgress?> notifier,
    required String Function(DeviceImportProgress? value) render,
  }) : _navigator = Navigator.of(context, rootNavigator: true) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<DeviceImportProgress?>(
        valueListenable: notifier,
        builder: (_, value, __) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(render(value), style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolved up front: by the time the work finishes the caller's context may have
  /// been deactivated, and looking a navigator up from it then would throw.
  final NavigatorState _navigator;

  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (_navigator.mounted && _navigator.canPop()) _navigator.pop();
  }
}

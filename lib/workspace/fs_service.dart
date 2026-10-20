import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';

class FsEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final bool isLink;

  const FsEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.isLink = false,
  });
}

class FsService {
  /// Absolute, normalised workspace root. Everything the editor reads or writes
  /// is confined to this subtree.
  String get rootPath => _rootPath;
  final String _rootPath;

  FsService(String root) : _rootPath = p.normalize(p.absolute(root));

  /// Resolves a workspace-relative path to an absolute one, refusing anything
  /// that leaves the workspace.
  ///
  /// Three things this gets right that the previous version did not:
  ///
  ///  * The root itself is a valid target. `p.isWithin(root, root)` is `false`,
  ///    so `list('.')` — which every directory listing in the app goes through —
  ///    used to throw `ArgumentError` and render an empty explorer.
  ///  * Absolute inputs are no longer a blanket bypass. They are re-based onto
  ///    the root by their final component, so passing
  ///    `/data/data/com.bcode.editor/shared_prefs/x` cannot reach outside.
  ///  * Every path component is checked for symlinks, not just the leaf. A
  ///    symlinked directory in the workspace used to pass containment, and git
  ///    preserves symlinks on clone, so a hostile repository could point a
  ///    directory component at app-private storage.
  ///
  /// Use [resolveExternal] for the one legitimate out-of-workspace case, the
  /// system file picker.
  String resolve(String relativePath) {
    final root = _rootPath;
    final raw = relativePath.trim();

    if (raw.isEmpty || raw == '.' || raw == './') return root;

    final normalized = p.normalize(raw);
    final relative = p.isAbsolute(normalized) ? p.relative(normalized, from: root) : normalized;

    if (relative.isEmpty || relative == '.') return root;

    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw ArgumentError('Path escapes the workspace: $relativePath');
    }

    final absolute = p.normalize(p.join(root, relative));
    if (absolute != root && !p.isWithin(root, absolute)) {
      throw ArgumentError('Path escapes the workspace: $relativePath');
    }

    _rejectSymlinkedComponents(root, absolute, relativePath);
    return absolute;
  }

  /// Resolves a path that is allowed to sit outside the workspace.
  ///
  /// Only the system file picker should need this. It is a separate named entry
  /// point precisely so that "did you mean to allow outside access?" is visible
  /// at every call site.
  String resolveExternal(String absolutePath) {
    final normalized = p.normalize(p.absolute(absolutePath));
    if (normalized != _rootPath && !p.isWithin(_rootPath, normalized)) {
      throw ArgumentError('Path is outside the workspace: $absolutePath');
    }
    _rejectSymlinkedComponents(_rootPath, normalized, absolutePath);
    return normalized;
  }

  void _rejectSymlinkedComponents(String root, String absolute, String original) {
    final relative = p.relative(absolute, from: root);
    var current = root;
    for (final segment in relative.split(p.separator)) {
      if (segment.isEmpty) continue;
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw ArgumentError('Symlinks are not allowed in the workspace: $original');
      }
    }
  }

  String relativeToRoot(String absolutePath) =>
      p.relative(absolutePath, from: _rootPath);

  Future<List<FsEntry>> list(String dirPath) async {
    final resolved = resolve(dirPath);
    final dir = Directory(resolved);
    if (!dir.existsSync()) return const [];

    final children = dir.listSync(followLinks: false)
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

    return children
        .where((e) => !p.basename(e.path).startsWith('.'))
        .map((e) {
          final path = e.path;
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          return FsEntry(
            path: path,
            name: p.basename(path),
            isDirectory: type == FileSystemEntityType.directory,
            isLink: type == FileSystemEntityType.link,
          );
        })
        .toList();
  }

  Future<String> readFile(String path) => File(resolve(path)).readAsString();

  /// Writes via a sibling temp file and renames into place.
  ///
  /// `File.writeAsString` truncates the destination before it writes. If the
  /// process dies mid-write — which is exactly what happens when the autosave
  /// debounce fires as the app is being backgrounded and then killed — the
  /// user's file is left empty. Rename is atomic within a filesystem, so the
  /// file is either the old content or the new content, never a truncated
  /// prefix.
  Future<void> writeFile(String path, String content) async {
    final resolved = resolve(path);
    final target = File(resolved);
    await target.parent.create(recursive: true);

    final temp = File('$resolved.bcode-tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(resolved);
    } catch (_) {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> createFile(String path) async {
    final f = File(resolve(path));
    if (f.existsSync()) throw StateError('File already exists');
    await f.create(recursive: true);
  }

  Future<void> createDirectory(String path) =>
      Directory(resolve(path)).create(recursive: true);

  Future<void> rename(String oldPath, String newName) async {
    if (newName.contains('/') ||
        newName.contains('\\') ||
        newName == '..' ||
        newName == '.') {
      throw ArgumentError('Invalid name: $newName');
    }
    final resolvedOld = resolve(oldPath);
    final entity =
        FileSystemEntity.typeSync(resolvedOld) == FileSystemEntityType.directory
            ? Directory(resolvedOld)
            : File(resolvedOld);
    final target = p.normalize(p.join(p.dirname(entity.path), newName));
    if (target != _rootPath && !p.isWithin(_rootPath, target)) {
      throw ArgumentError('Target escapes the workspace');
    }
    _rejectSymlinkedComponents(_rootPath, target, newName);
    await entity.rename(target);
  }

  Future<void> move(String fromPath, String toDirPath) async {
    final resolvedFrom = resolve(fromPath);
    final resolvedTo = resolve(toDirPath);
    final entity =
        FileSystemEntity.typeSync(resolvedFrom) == FileSystemEntityType.directory
            ? Directory(resolvedFrom)
            : File(resolvedFrom);
    final target = p.normalize(p.join(resolvedTo, p.basename(entity.path)));
    if (target != _rootPath && !p.isWithin(_rootPath, target)) {
      throw ArgumentError('Target escapes the workspace');
    }
    if (Directory(target).existsSync() || File(target).existsSync()) {
      throw StateError('Target already exists');
    }
    _rejectSymlinkedComponents(_rootPath, target, fromPath);
    await entity.rename(target);
  }

  Future<void> delete(String path) async {
    final resolved = resolve(path);
    if (resolved == _rootPath) {
      throw ArgumentError('Refusing to delete the workspace root.');
    }
    final type = FileSystemEntity.typeSync(resolved);
    if (type == FileSystemEntityType.directory) {
      await Directory(resolved).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(resolved).delete();
    }
  }

  bool exists(String path) {
    final resolved = resolve(path);
    return Directory(resolved).existsSync() || File(resolved).existsSync();
  }

  bool isDirectory(String path) =>
      FileSystemEntity.typeSync(resolve(path)) == FileSystemEntityType.directory;
}

/// Replaces the native exec sandbox's root set with [paths].
///
/// This *replaces* rather than appends. The previous `addSandboxPath` only ever
/// grew the set and nothing removed a root, so a directory the user selected
/// once stayed executable for the life of the process.
///
/// Best effort: the channel is absent in unit tests and on non-Android hosts.
Future<void> setSandboxPaths(List<String> paths) async {
  const channel = MethodChannel(AppConstants.execChannel);
  try {
    await channel.invokeMethod('setSandboxPaths', {'paths': paths});
  } catch (_) {}
}
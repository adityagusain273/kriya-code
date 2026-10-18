import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';

class FsEntry {
  final String path;
  final String name;
  final bool isDirectory;

  const FsEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
  });
}

class FsService {
  String rootPath;

  FsService(this.rootPath);

  Future<void> setCustomRoot(String newRoot) async {
    final dir = Directory(newRoot);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    rootPath = p.normalize(newRoot);
    // Register the custom root with the exec sandbox
    await registerSandboxPath(rootPath);
  }

  Future<void> registerSandboxPath(String path) async {
    const channel = MethodChannel(AppConstants.execChannel);
    try {
      await channel.invokeMethod('addSandboxPath', {'path': path});
    } catch (_) {
      // Ignore errors - sandbox registration is best-effort
    }
  }

  String resolve(String relativePath) {
    final normalized = p.normalize(relativePath);
    final absolute = p.isAbsolute(normalized) ? normalized : p.join(rootPath, normalized);
    final canonical = p.normalize(absolute);
    
    // Reject relative paths that escape the workspace root
    if (!p.isAbsolute(normalized)) {
      if (!p.isWithin(rootPath, canonical)) {
        throw ArgumentError('Relative path escapes workspace root: $relativePath');
      }
    }
    
    // Allow accessing files outside the workspace root when using absolute paths
    // e.g. from the 'Open File' dialog.
    final type = FileSystemEntity.typeSync(canonical, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ArgumentError('Symlinks are not allowed: $relativePath');
    }
    return canonical;
  }

  String relativeToRoot(String absolutePath) => p.relative(absolutePath, from: rootPath);

  Future<List<FsEntry>> list(String dirPath) async {
    final dir = Directory(resolve(dirPath));
    if (!dir.existsSync()) return const [];
    final children = dir.listSync(followLinks: false)
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
    return children
        .where((e) => !p.basename(e.path).startsWith('.'))
        .map((e) => FsEntry(
              path: e.path,
              name: p.basename(e.path),
              isDirectory: e is Directory,
            ))
        .toList();
  }

  Future<String> readFile(String path) => File(resolve(path)).readAsString();

  Future<void> writeFile(String path, String content) async {
    final resolved = resolve(path);
    await File(resolved).create(recursive: true);
    await File(resolved).writeAsString(content);
  }

  Future<void> createFile(String path) async {
    final f = File(resolve(path));
    if (f.existsSync()) throw StateError('File already exists');
    await f.create(recursive: true);
  }

  Future<void> createDirectory(String path) => Directory(resolve(path)).create(recursive: true);

  Future<void> rename(String oldPath, String newName) async {
    if (newName.contains('/') || newName.contains('\\') || newName == '..' || newName == '.') {
      throw ArgumentError('Invalid name: $newName');
    }
    final resolvedOld = resolve(oldPath);
    final entity = FileSystemEntity.typeSync(resolvedOld) == FileSystemEntityType.directory
        ? Directory(resolvedOld)
        : File(resolvedOld);
    final target = p.join(p.dirname(entity.path), newName);
    if (!p.isWithin(rootPath, target)) {
      throw ArgumentError('Target escapes workspace root');
    }
    await entity.rename(target);
  }

  Future<void> move(String fromPath, String toDirPath) async {
    final resolvedFrom = resolve(fromPath);
    final resolvedTo = resolve(toDirPath);
    final entity = FileSystemEntity.typeSync(resolvedFrom) == FileSystemEntityType.directory
        ? Directory(resolvedFrom)
        : File(resolvedFrom);
    final target = p.join(resolvedTo, p.basename(entity.path));
    if (!p.isWithin(rootPath, target)) {
      throw ArgumentError('Target escapes workspace root');
    }
    if (Directory(target).existsSync() || File(target).existsSync()) {
      throw StateError('Target already exists');
    }
    await entity.rename(target);
  }

  Future<void> delete(String path) async {
    final resolved = resolve(path);
    // Allow deleting files outside workspace if explicitly accessed via absolute path
    // but validate it's a legitimate path
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

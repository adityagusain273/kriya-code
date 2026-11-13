import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Builds a `.zip` of a directory tree without reading every file into memory.
///
/// `ZipFileEncoder.zipDirectory` walks and encodes in one call, which leaves no
/// seam for a progress callback or for skipping paths, so the same `Archive`,
/// `ArchiveFile.stream` and `ZipEncoder` used by the extension installer are
/// driven here one entry at a time.
class WorkspaceArchive {
  Future<WorkspaceArchiveResult> build(
    Directory root,
    File output, {
    void Function(int files, int bytes)? onProgress,
    bool Function(String relativePath)? include,
  }) async {
    final rootPath = p.normalize(p.absolute(root.path));
    if (!await root.exists()) {
      throw StateError('The workspace folder does not exist.');
    }

    final outputPath = p.normalize(p.absolute(output.path));
    final outputName = p.isWithin(rootPath, outputPath)
        ? p.posix.joinAll(p.relative(outputPath, from: rootPath).split(p.separator))
        : null;

    await output.parent.create(recursive: true);
    if (outputName != null && await output.exists()) {
      await output.delete();
    }

    final archive = Archive();
    final directories = <String>{};
    var files = 0;
    var bytes = 0;

    void addDirectoryEntry(String relative) {
      final name = '$relative/';
      if (!directories.add(name)) return;
      archive.addFile(ArchiveFile.directory(name));
    }

    addDirectoryEntry(p.basename(rootPath));

    await for (final entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) continue;
      final relative = p.relative(entity.path, from: rootPath);
      final name = p.posix.joinAll(relative.split(p.separator));

      if (entity is Directory) {
        if (include == null || include(name)) addDirectoryEntry(name);
        continue;
      }
      if (entity is! File) continue;
      if (name == outputName) continue;
      if (include != null && !include(name)) continue;

      final parts = name.split('/');
      for (var i = 1; i < parts.length; i++) {
        addDirectoryEntry(parts.sublist(0, i).join('/'));
      }

      final size = await entity.length();
      final stream = InputFileStream(entity.path, bufferSize: 64 * 1024);
      final archiveFile = ArchiveFile.stream(name, stream);
      archiveFile.lastModTime =
          (await entity.lastModified()).millisecondsSinceEpoch ~/ 1000;
      archive.addFile(archiveFile);

      files++;
      bytes += size;
      onProgress?.call(files, bytes);
    }

    final encoded = ZipEncoder().encode(archive, level: 1);
    await output.writeAsBytes(encoded, flush: true);
    return WorkspaceArchiveResult(files: files, bytes: bytes, path: output.path);
  }
}

class WorkspaceArchiveResult {
  final int files;
  final int bytes;
  final String path;

  const WorkspaceArchiveResult({
    required this.files,
    required this.bytes,
    required this.path,
  });
}
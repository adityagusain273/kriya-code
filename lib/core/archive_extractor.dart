import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Archive container formats the editor can unpack.
enum ArchiveFormat { zip, tar, tarGzip, tarBzip2 }

class ArchiveExtractionException implements Exception {
  final String message;

  const ArchiveExtractionException(this.message);

  @override
  String toString() => message;
}

/// Unpacks a project archive into a folder inside the workspace.
///
/// The onboarding "Unzip a GitHub download" flow, the file explorer's per-file
/// action and the new "Extract Project Archive" flow all used to carry their own copy
/// of this loop, and none of them validated the output path. `p.join(extractDir,
/// entry.name)` does not stop `..`, so an archive entry named
/// `../../../../databases/app.db` wrote anywhere the app UID could write — including
/// over the downloaded language runtimes in `files/runtimes/<id>/bin`, which the Run
/// button then executes. That is arbitrary code execution from a file the user was
/// told they could safely unpack.
///
/// Defences applied per entry:
///  * the resolved path must stay inside [extractDir], compared component-wise
///    rather than by string prefix, so `/out-secret` is not reachable from `/out`;
///  * absolute names, backslash separators, and NUL bytes are rejected;
///  * symlink entries are rejected outright;
///  * total extracted bytes and entry count are capped, so a small archive
///    cannot fill the device;
///  * the partially written folder is removed when any entry is refused, so a
///    rejected archive cannot leave half a project behind for the user to trip over.
///
/// ZIP, TAR, TAR.GZ/TGZ and TAR.BZ2/TBZ2 are recognised. The container is identified
/// from its magic bytes rather than its name, because a file picked through the
/// system file chooser routinely arrives called `download` or `project.zip` while
/// actually being a `.tar.gz`.
class ArchiveExtractor {
  const ArchiveExtractor._();

  static const int maxTotalBytes = 512 * 1024 * 1024;
  static const int maxEntries = 20000;

  /// Ceiling on a compressed container that has to be held in memory to be
  /// decompressed at all. Streaming formats are not subject to it.
  static const int maxCompressedBytes = 256 * 1024 * 1024;

  static const _extensions = <String, ArchiveFormat>{
    '.zip': ArchiveFormat.zip,
    '.jar': ArchiveFormat.zip,
    '.apk': ArchiveFormat.zip,
    '.tar': ArchiveFormat.tar,
    '.tar.gz': ArchiveFormat.tarGzip,
    '.tgz': ArchiveFormat.tarGzip,
    '.tar.bz2': ArchiveFormat.tarBzip2,
    '.tbz2': ArchiveFormat.tarBzip2,
  };

  /// Whether [name] looks like an archive the editor can unpack.
  ///
  /// Used to decide whether to offer the action at all. The per-file menu used to
  /// offer "Extract ZIP" on every entry in the tree, so choosing it on a `.dart` file
  /// produced a decoder error rather than a sensible "that is not an archive".
  static bool isArchiveName(String name) {
    final lower = name.toLowerCase();
    for (final ext in _extensions.keys) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  /// Format implied by [name], or null when the name says nothing useful.
  static ArchiveFormat? formatForName(String name) {
    final lower = name.toLowerCase();
    // Longest suffix first: `.tar.gz` has to win over `.gz`-style prefixes.
    final sorted = _extensions.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final ext in sorted) {
      if (lower.endsWith(ext)) return _extensions[ext];
    }
    return null;
  }

  /// Folder name to unpack [archiveName] into: `app.tar.gz` becomes `app`.
  static String folderNameFor(String archiveName) {
    var name = p.basename(archiveName).toLowerCase();
    for (final ext in _extensions.keys) {
      if (name.endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    name = name.replaceAll(RegExp(r'[^\w.\- ]'), '_').trim();
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.isEmpty) return 'extracted';
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  /// Container format of [head], the first bytes of a file.
  static ArchiveFormat? detectFormat(List<int> head) {
    if (head.length >= 4 &&
        head[0] == 0x50 &&
        head[1] == 0x4B &&
        ((head[2] == 0x03 && head[3] == 0x04) ||
            (head[2] == 0x05 && head[3] == 0x06) ||
            (head[2] == 0x07 && head[3] == 0x08))) {
      return ArchiveFormat.zip;
    }
    if (head.length >= 2 && head[0] == 0x1F && head[1] == 0x8B) {
      return ArchiveFormat.tarGzip;
    }
    if (head.length >= 3 &&
        head[0] == 0x42 &&
        head[1] == 0x5A &&
        head[2] == 0x68) {
      return ArchiveFormat.tarBzip2;
    }
    // ustar magic lives at offset 257, so this needs the whole first block.
    if (head.length >= 262) {
      final magic = String.fromCharCodes(head.sublist(257, 262));
      if (magic == 'ustar') return ArchiveFormat.tar;
    }
    return null;
  }

  /// Validates one archive entry name against [targetRoot] and returns the
  /// absolute path it would be written to.
  ///
  /// Separate from [extract] so the rule can be exercised directly:
  /// `package:archive`'s `ZipEncoder` will not emit the UNIX creator metadata
  /// that its own decoder requires to reconstruct a symlink entry, so a
  /// round-tripped test fixture cannot reach the symlink branch.
  static String validateEntryName(String targetRoot, String name) {
    if (name.isEmpty) {
      throw const ArchiveExtractionException(
          'Refusing archive entry with no name.');
    }
    if (p.isAbsolute(name) || name.contains('\\') || name.contains('\u0000')) {
      throw ArchiveExtractionException('Refusing unsafe archive entry: $name');
    }

    final root = p.normalize(p.absolute(targetRoot));
    final outPath = p.normalize(p.join(root, name));

    if (outPath != root && !p.isWithin(root, outPath)) {
      throw ArchiveExtractionException(
        'Refusing archive entry outside the target folder: $name',
      );
    }

    return outPath;
  }

  /// Unpacks [archiveFile] into [extractDir], reporting nothing on success.
  static Future<void> extract(File archiveFile, String extractDir) async {
    await extractWithProgress(archiveFile, extractDir, null);
  }

  /// As [extract], calling [onProgress] with the running entry count.
  ///
  /// A GitHub source archive unpacks to a few thousand files; without any feedback
  /// that reads on a phone as the app having hung.
  static Future<void> extractWithProgress(
    File archiveFile,
    String extractDir,
    void Function(int entries, int bytes)? onProgress,
  ) async {
    if (!archiveFile.existsSync()) {
      throw ArchiveExtractionException(
          'No such archive: ${p.basename(archiveFile.path)}');
    }

    final targetRoot = p.normalize(p.absolute(extractDir));
    final format = await _formatOf(archiveFile);

    final written = <String>{};
    var totalBytes = 0;
    var entryCount = 0;
    var createdRoot = false;

    try {
      final archive = await _open(archiveFile, format);

      for (final entry in archive) {
        entryCount++;
        if (entryCount > maxEntries) {
          throw ArchiveExtractionException(
            'Refusing to extract: the archive has more than $maxEntries entries.',
          );
        }

        if (entry.isSymbolicLink) {
          throw ArchiveExtractionException(
            'Refusing to extract link entry: ${entry.name}',
          );
        }

        final outPath = validateEntryName(targetRoot, entry.name);

        if (entry.isDirectory) {
          if (!createdRoot) {
            await Directory(targetRoot).create(recursive: true);
            createdRoot = true;
          } else {
            await Directory(outPath).create(recursive: true);
          }
          continue;
        }

        if (!entry.isFile) continue;

        final content = entry.content;
        totalBytes += content.length;
        if (totalBytes > maxTotalBytes) {
          throw const ArchiveExtractionException(
            'Refusing to extract: the archive expands beyond 512 MB.',
          );
        }

        if (!createdRoot) {
          await Directory(targetRoot).create(recursive: true);
          createdRoot = true;
        }
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        // Guards against an archive that lists the same path twice, where the
        // second write would otherwise clobber the first with different content.
        written.add(outPath);
        await outFile.writeAsBytes(content);

        if (onProgress != null && entryCount % 32 == 0) {
          onProgress(entryCount, totalBytes);
        }
      }
    } catch (_) {
      // Leave nothing half-extracted. A folder that exists but is missing the
      // entries an archive refused is worse than no folder: it looks usable.
      if (createdRoot) {
        try {
          final dir = Directory(targetRoot);
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {
          // Best effort; the original error is the one worth reporting.
        }
      }
      rethrow;
    }

    if (entryCount == 0) {
      // The container parsed but held nothing. Refused rather than reported as
      // success: the alternative is a silently created empty folder, which reads
      // as "your project imported" and is indistinguishable from a broken import.
      // This is what a text file renamed to `.zip` produces.
      throw const ArchiveExtractionException(
        'The archive contained no files. It may not really be an archive.',
      );
    }

    onProgress?.call(entryCount, totalBytes);
  }
  static Future<ArchiveFormat> _formatOf(File file) async {
    final head = await _readHead(file, 512);
    final sniffed = detectFormat(head);
    if (sniffed != null) return sniffed;

    final byName = formatForName(p.basename(file.path));
    if (byName != null) return byName;

    throw ArchiveExtractionException(
      'Unrecognised archive format: ${p.basename(file.path)}',
    );
  }

  static Future<List<int>> _readHead(File file, int count) async {
    final handle = await file.open();
    try {
      final head = await handle.read(count);
      return head;
    } finally {
      await handle.close();
    }
  }

  static Future<Archive> _open(File file, ArchiveFormat format) async {
    switch (format) {
      case ArchiveFormat.zip:
        return ZipDecoder().decodeStream(_streamOf(file));
      case ArchiveFormat.tar:
        return TarDecoder().decodeStream(_streamOf(file));
      case ArchiveFormat.tarGzip:
        final raw = await _readCapped(file);
        return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(raw));
      case ArchiveFormat.tarBzip2:
        final raw = await _readCapped(file);
        return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(raw));
    }
  }

  /// Streaming input, so a large ZIP or TAR is never fully resident.
  static InputFileStream _streamOf(File file) =>
      InputFileStream.withFileHandle(FileHandle(file.path));

  static Future<List<int>> _readCapped(File file) async {
    final length = await file.length();
    if (length > maxCompressedBytes) {
      throw const ArchiveExtractionException(
        'Refusing to extract: the compressed archive is larger than 256 MB.',
      );
    }
    return file.readAsBytes();
  }
}

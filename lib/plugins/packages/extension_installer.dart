import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/archive_extractor.dart';
import 'extension_manifest.dart';

class InstalledExtension {
  final ExtensionManifest manifest;
  final String directory;

  const InstalledExtension(this.manifest, this.directory);
}

class StagedExtension {
  final ExtensionManifest manifest;
  final String directory;
  final String container;
  final String? readme;

  const StagedExtension({
    required this.manifest,
    required this.directory,
    required this.container,
    this.readme,
  });

  int get snippetCount =>
      manifest.snippets.values.fold(0, (total, list) => total + list.length);
}

/// Installs declarative extension packages into app-private storage.
///
/// A package is a `.bcext` (zip) containing `extension.json` at its root. It is
/// data, never code, so installing one cannot execute anything: the app only
/// reads languages, snippets and themes out of it.
class ExtensionInstaller {
  static const maxArchiveBytes = 16 * 1024 * 1024;
  static const maxPackageBytes = 16 * 1024 * 1024;
  static const maxUnpackedBytes = 48 * 1024 * 1024;
  static const maxManifestBytes = 256 * 1024;
  static const _maxFiles = 2000;

  final String rootDir;
  final http.Client client;

  ExtensionInstaller({required this.rootDir, http.Client? client})
      : client = client ?? http.Client();

  Future<List<InstalledExtension>> installed() async {
    final root = Directory(rootDir);
    if (!await root.exists()) return const [];

    final result = <InstalledExtension>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final manifestFile = File(p.join(entity.path, 'extension.json'));
      if (!await manifestFile.exists()) continue;
      try {
        result.add(InstalledExtension(
          await _readManifest(manifestFile),
          entity.path,
        ));
      } catch (error) {
        debugPrint('ExtensionInstaller: skipping $name: $error');
      }
    }
    result.sort((a, b) =>
        a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return result;
  }

  Future<StagedExtension> stageArchive(File archive) async {
    if (await archive.length() > maxArchiveBytes) {
      throw ExtensionFormatException(
        'That package is larger than ${maxArchiveBytes ~/ (1024 * 1024)} MB.',
      );
    }

    await Directory(rootDir).create(recursive: true);
    final temp = Directory(
      p.join(rootDir, '.incoming-${DateTime.now().microsecondsSinceEpoch}'),
    );
    try {
      await ArchiveExtractor.extractWithProgress(
        archive,
        temp.path,
        null,
        totalBytesLimit: maxUnpackedBytes,
        entryLimit: _maxFiles,
        compressedBytesLimit: maxArchiveBytes,
      );
      return await _stageFrom(temp.path);
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete(recursive: true).catchError((_) => temp);
      }
      rethrow;
    }
  }

  Future<InstalledExtension> installArchive(File archive) async =>
      commit(await stageArchive(archive));

  Future<StagedExtension> stageUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const ExtensionFormatException(
        'Enter a full https:// URL to a .bcext package.',
      );
    }

    await Directory(rootDir).create(recursive: true);
    final download = File(
      p.join(
          rootDir, '.download-${DateTime.now().microsecondsSinceEpoch}.bcext'),
    );
    try {
      final request = http.Request('GET', uri);
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      final finalUrl = response.request?.url;
      if (finalUrl != null && finalUrl.scheme != 'https') {
        throw const ExtensionFormatException(
          'The download was redirected to a non-HTTPS URL.',
        );
      }
      if (response.statusCode != 200) {
        throw ExtensionFormatException(
          'Download failed with HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > maxArchiveBytes) {
        throw ExtensionFormatException(
          'That package is larger than ${maxArchiveBytes ~/ (1024 * 1024)} MB.',
        );
      }

      final sink = download.openWrite();
      var total = 0;
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          total += chunk.length;
          if (total > maxArchiveBytes) {
            throw ExtensionFormatException(
              'That package is larger than '
              '${maxArchiveBytes ~/ (1024 * 1024)} MB.',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return await stageArchive(download);
    } finally {
      if (await download.exists()) {
        await download.delete().catchError((_) => download);
      }
    }
  }

  Future<InstalledExtension> installUrl(String url) async =>
      commit(await stageUrl(url));

  /// Stages a folder such as the one created by the in-app scaffold, so a
  /// developer can edit the manifest and reload without zipping anything.
  Future<StagedExtension> stageDirectory(String sourceDir) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw const ExtensionFormatException('That folder does not exist.');
    }

    await Directory(rootDir).create(recursive: true);
    final temp = Directory(
      p.join(rootDir, '.incoming-${DateTime.now().microsecondsSinceEpoch}'),
    );
    try {
      await temp.create(recursive: true);
      var files = 0;
      var bytes = 0;
      await for (final entity
          in source.list(recursive: true, followLinks: false)) {
        if (entity is Link) {
          throw const ExtensionFormatException(
            'Extension folders cannot contain symlinks.',
          );
        }
        if (entity is! File) continue;
        files++;
        if (files > _maxFiles) {
          throw const ExtensionFormatException(
              'That folder has too many files.');
        }
        final relative = p.relative(entity.path, from: source.path);
        if (relative.split(p.separator).any((part) => part == '.git')) continue;
        final destination = File(p.join(temp.path, relative));
        await destination.parent.create(recursive: true);
        bytes += await entity.length();
        if (bytes > maxUnpackedBytes) {
          throw ExtensionFormatException(
            'That folder is larger than ${maxUnpackedBytes ~/ (1024 * 1024)} MB.',
          );
        }
        await entity.copy(destination.path);
      }
      return await _stageFrom(temp.path);
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete(recursive: true).catchError((_) => temp);
      }
      rethrow;
    }
  }

  Future<InstalledExtension> installDirectory(String sourceDir) async =>
      commit(await stageDirectory(sourceDir));

  Future<void> discard(StagedExtension staged) async {
    final directory = Directory(staged.container);
    if (await directory.exists()) {
      await directory.delete(recursive: true).catchError((_) => directory);
    }
  }

  Future<StagedExtension> _stageFrom(String extracted) async {
    final packageRoot = _packageRoot(extracted);
    final manifest = await _readManifest(
      File(p.join(packageRoot, 'extension.json')),
    );
    return StagedExtension(
      manifest: manifest,
      directory: packageRoot,
      container: extracted,
      readme: await _readReadme(packageRoot),
    );
  }

  Future<void> uninstall(String id) async {
    if (id.contains('/') || id.contains('\\') || id.startsWith('.')) {
      throw ArgumentError.value(id, 'id', 'Not a valid extension id');
    }
    final directory = Directory(p.join(rootDir, id));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Builds a `.bcext` from a folder, for authors publishing from the phone.
  Future<String> packageDirectory(String sourceDir, String outputPath) async {
    final source = Directory(sourceDir);
    final manifest = await _readManifest(
      File(p.join(source.path, 'extension.json')),
    );

    final archive = Archive();
    var bytes = 0;
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw const ExtensionFormatException(
          'Extension folders cannot contain symlinks.',
        );
      }
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      if (relative.split(p.separator).contains('.git')) continue;
      bytes += await entity.length();
      if (bytes > maxPackageBytes) {
        throw ExtensionFormatException(
          'That folder is larger than ${maxPackageBytes ~/ (1024 * 1024)} MB.',
        );
      }
      archive.addFile(ArchiveFile(
        relative.replaceAll(p.separator, '/'),
        await entity.length(),
        await entity.readAsBytes(),
      ));
    }
    if (!archive.files.any((file) => file.name == 'extension.json')) {
      throw const ExtensionFormatException(
        'extension.json must be at the root of the folder.',
      );
    }

    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return '${manifest.id}-${manifest.version}.bcext';
  }

  Future<InstalledExtension> commit(StagedExtension staged) async {
    final target = Directory(p.join(rootDir, staged.manifest.id));
    final backup = Directory(
      p.join(
        rootDir,
        '.old-${staged.manifest.id}-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    var backedUp = false;
    try {
      if (await target.exists()) {
        await target.rename(backup.path);
        backedUp = true;
      }
      await Directory(staged.directory).rename(target.path);
    } catch (_) {
      if (backedUp &&
          await backup.exists() &&
          !await target.exists()) {
        await backup.rename(target.path).catchError((_) => backup);
      }
      rethrow;
    } finally {
      await discard(staged);
      if (await backup.exists()) {
        await backup.delete(recursive: true).catchError((_) => backup);
      }
    }
    return InstalledExtension(staged.manifest, target.path);
  }

  static const _maxReadmeBytes = 64 * 1024;

  Future<String?> _readReadme(String packageRoot) async {
    final file = File(p.join(packageRoot, 'README.md'));
    if (!await file.exists()) return null;
    final length = await file.length();
    final handle = await file.open();
    try {
      final bytes = await handle.read(
        length > _maxReadmeBytes ? _maxReadmeBytes : length,
      );
      final text = utf8.decode(bytes, allowMalformed: true);
      return length > _maxReadmeBytes ? '$text\n…' : text;
    } finally {
      await handle.close();
    }
  }

  Future<ExtensionManifest> _readManifest(File file) async {
    if (!await file.exists()) {
      throw const ExtensionFormatException(
        'The package has no extension.json at its root.',
      );
    }
    if (await file.length() > maxManifestBytes) {
      throw const ExtensionFormatException('extension.json is too large.');
    }
    return ExtensionManifest.parse(await file.readAsString());
  }

  String _packageRoot(String extracted) {
    if (File(p.join(extracted, 'extension.json')).existsSync()) {
      return extracted;
    }
    final children = Directory(extracted)
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((dir) => !p.basename(dir.path).startsWith('.'))
        .toList();
    if (children.length == 1 &&
        File(p.join(children.single.path, 'extension.json')).existsSync()) {
      return children.single.path;
    }
    throw const ExtensionFormatException(
      'extension.json must be at the root of the package, or inside one '
      'top-level folder.',
    );
  }
}

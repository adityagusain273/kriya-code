import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/archive_extractor.dart';
import '../core/constants.dart';

/// Turns a downloaded CI artifact ZIP into a file the system installer accepts.
class ArtifactInstaller {
  static const _channel = MethodChannel(AppConstants.execChannel);

  /// Unpacks [zipBytes] under the app cache and returns the APK inside it.
  ///
  /// Artifacts are always ZIPs, and the upload step may nest the APK in a
  /// folder, so the whole tree is searched. Extraction goes through
  /// [ArchiveExtractor], which refuses traversal and caps the output size.
  ///
  /// shortcut: a split-per-ABI artifact contains several APKs and only the
  /// first is returned — the system installer cannot install one split alone.
  /// Teach this to pick by ABI if split artifacts become the default.
  static Future<File?> prepareApk(List<int> zipBytes, {required int artifactId}) async {
    final cache = await getTemporaryDirectory();
    final work = Directory(p.join(cache.path, 'cloud_build', '$artifactId'));
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);

    final zip = File(p.join(work.path, 'artifact.zip'));
    await zip.writeAsBytes(zipBytes);

    final unpacked = p.join(work.path, 'unpacked');
    await ArchiveExtractor.extract(zip, unpacked);

    final dir = Directory(unpacked);
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
        return entity;
      }
    }
    return null;
  }

  /// Hands [apk] to Android's package installer via `ACTION_VIEW`.
  ///
  /// Returns false when no install activity could be started, which on most
  /// devices means the user has not allowed "install unknown apps" for B Code.
  static Future<bool> install(File apk) async {
    return await _channel.invokeMethod<bool>('installApk', {'path': apk.path}) ?? false;
  }
}

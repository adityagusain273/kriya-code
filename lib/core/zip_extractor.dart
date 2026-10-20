import 'dart:io';
import 'package:archive/archive_io.dart';

class ZipExtractor {
  static Future<void> extract(File zipFile, String extractDir) async {
    await extractFileToDisk(zipFile.path, extractDir);
  }
}

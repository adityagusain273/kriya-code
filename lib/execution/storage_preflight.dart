import 'dart:io';

import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Free bytes on the filesystem holding [path], or null when the platform
/// cannot answer: a desktop host, or an APK built before the storage plugin
/// existed.
typedef FreeBytesProbe = Future<int?> Function(String path);

/// Free space on the volume that holds the app's runtimes directory.
class DeviceStorage {
  const DeviceStorage._();

  static const _channel = MethodChannel(AppConstants.storageChannel);

  /// `StatFs(path).availableBytes` from StoragePlugin.
  static Future<int?> freeBytes(String path) async {
    if (!Platform.isAndroid) return null;
    try {
      final bytes =
          await _channel.invokeMethod<int>('freeBytes', {'path': path});
      return (bytes != null && bytes > 0) ? bytes : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= 1024 * mb) {
      return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / mb).round()} MB';
  }
}

enum StorageVerdict {
  /// Enough room, including the unpacking margin.
  fits,

  /// Refuse: installing now would fill the volume.
  insufficient,

  /// The platform did not answer. Nothing is verified either way.
  unknown,
}

class StorageCheck {
  final StorageVerdict verdict;

  /// Packed size of what would be downloaded.
  final int packedBytes;

  /// Free space required to install it safely.
  final int requiredBytes;

  final int? freeBytes;

  const StorageCheck({
    required this.verdict,
    required this.packedBytes,
    required this.requiredBytes,
    this.freeBytes,
  });

  bool get allowsInstall => verdict != StorageVerdict.insufficient;

  String get message {
    final free = freeBytes;
    if (free == null) {
      return 'Free space could not be checked on this device.';
    }
    return 'Not enough free space: ${DeviceStorage.formatBytes(free)} available, '
        '${DeviceStorage.formatBytes(requiredBytes)} needed for a '
        '${DeviceStorage.formatBytes(packedBytes)} runtime (it needs room to '
        'unpack as well as to download). Free some space in Settings → Apps, '
        'or remove an unused runtime.';
  }
}

/// Guards runtime downloads and unpacking against filling the device.
///
/// A phone that runs out of space mid-extract is left with a half-unpacked
/// runtime and no way to run it, and a volume that fills completely takes the
/// app's own databases with it. So the check runs before any bytes move.
class StoragePreflight {
  const StoragePreflight._();

  /// A `.deb` unpacks to roughly twice its packed size, and the packed files
  /// stay on disk while it does. Requiring twice the download up front covers
  /// both, and leaves the volume with room to spare.
  static const int unpackMargin = 2;

  static StorageCheck evaluate({
    required int packedBytes,
    int? freeBytes,
    int margin = unpackMargin,
  }) {
    final required = packedBytes * margin;
    if (freeBytes == null) {
      return StorageCheck(
        verdict: StorageVerdict.unknown,
        packedBytes: packedBytes,
        requiredBytes: required,
      );
    }
    if (freeBytes < required) {
      return StorageCheck(
        verdict: StorageVerdict.insufficient,
        packedBytes: packedBytes,
        requiredBytes: required,
        freeBytes: freeBytes,
      );
    }
    return StorageCheck(
      verdict: StorageVerdict.fits,
      packedBytes: packedBytes,
      requiredBytes: required,
      freeBytes: freeBytes,
    );
  }

  /// The second gate, run after the packed files are on disk: unpacking then
  /// needs about one more copy, not two.
  static StorageCheck evaluateExtraction({
    required int packedBytes,
    int? freeBytes,
  }) =>
      evaluate(packedBytes: packedBytes, freeBytes: freeBytes, margin: 1);
}
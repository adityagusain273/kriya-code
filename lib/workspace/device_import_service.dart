import 'dart:async';

import 'package:flutter/services.dart';

import '../core/constants.dart';

/// What came back from a device import.
class DeviceImport {
  /// Absolute path of the imported file or folder, inside the workspace.
  final String path;

  /// Files copied. Always 1 for a single-file import.
  final int files;

  /// Bytes copied.
  final int bytes;

  /// True when a ceiling stopped the copy short.
  ///
  /// The import still succeeded, so this must not be presented as a failure — but
  /// silently claiming a project arrived in full when it did not is worse.
  final bool truncated;

  const DeviceImport({
    required this.path,
    required this.files,
    required this.bytes,
    this.truncated = false,
  });
}

/// Incremental progress of a folder import.
class DeviceImportProgress {
  final String name;
  final int files;
  final int bytes;

  const DeviceImportProgress({
    required this.name,
    required this.files,
    required this.bytes,
  });
}

/// Brings files and whole project folders off the device and into the workspace.
///
/// Android has no "give me any path" API: a path has to come from the Storage Access
/// Framework, whose grant is per-app and expressed as a `content://` URI rather than a
/// filesystem path. Everything else in the editor — run configs, the live server, git,
/// Termux — is built on one plain directory tree, so the URI is resolved on the native
/// side and the bytes are copied into that tree. That is also why this service returns
/// a path and not a handle.
///
/// For files that other apps must also see, pointing the editor at the shared folder
/// in Settings is the answer instead; see `WorkspaceService`.
class DeviceImportService {
  DeviceImportService._();

  static final DeviceImportService instance = DeviceImportService._();

  static const MethodChannel _channel = MethodChannel(AppConstants.safChannel);

  final _progress = StreamController<DeviceImportProgress>.broadcast();
  bool _handlerInstalled = false;

  /// Fires while a folder import runs. Broadcast, so the UI can attach and detach.
  Stream<DeviceImportProgress> get progress => _progress.stream;

  /// Picks a single file and copies it to the workspace root.
  ///
  /// Returns null when the user backs out.
  Future<DeviceImport?> pickFile() async {
    _ensureHandler();
    final path = await _invokePath('importFile');
    if (path == null) return null;
    return DeviceImport(path: path, files: 1, bytes: 0);
  }

  /// Picks a folder and copies the whole tree into the workspace root.
  ///
  /// Returns null when the user backs out, and also when the platform refuses: this
  /// device has no folder picker, so the action has to no-op rather than throw out of
  /// a menu callback. A real project takes long enough that the caller is expected to
  /// show [progress] while it runs.
  Future<DeviceImport?> pickFolder() async {
    _ensureHandler();
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('importFolder');
      if (raw == null) return null;
      final path = raw['path'];
      if (path is! String || path.isEmpty) return null;
      return DeviceImport(
        path: path,
        files: _asInt(raw['files']),
        bytes: _asInt(raw['bytes']),
        truncated: raw['truncated'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      // "NO_PICKER" means the ROM has no folder picker at all; anything else is a real
      // failure the caller reports.
      if (e.code == 'NO_PICKER') return null;
      rethrow;
    }
  }

  Future<String?> _invokePath(String method) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } on MissingPluginException {
      return null;
    }
  }

  void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'importProgress') return null;
      final args = call.arguments;
      if (args is! Map) return null;
      _progress.add(DeviceImportProgress(
        name: args['name'] as String? ?? 'project',
        files: _asInt(args['files']),
        bytes: _asInt(args['bytes']),
      ));
      return null;
    });
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Human-readable byte count, for import feedback.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

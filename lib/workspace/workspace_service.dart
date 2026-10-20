import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Where the editor's files live, and whether that place is shared with other apps.
///
/// The default is an app-private folder: it needs no permission, works on every
/// device, and is what a first-time user should get without being interrupted by a
/// permission dialog.
///
/// The shared folder (`/storage/emulated/0/BCode`) is opt-in because it needs
/// All-files access on a modern Android, which is a grant the user has to make on a
/// system screen and can revoke later. It is worth offering because it is the only
/// way another app such as Termux can work on the same files: SAF grants are
/// per-app, so Termux can never open a `content://` URI that was granted to B Code.
class WorkspaceLocation {
  /// True when files live in the shared volume and other apps can reach them.
  final bool shared;

  /// Absolute path of the folder in use.
  final String path;

  /// True when the shared folder is wanted but the system grant is missing, so the
  /// UI can explain what has to happen next.
  final bool needsAllFilesAccess;

  const WorkspaceLocation({
    required this.shared,
    required this.path,
    this.needsAllFilesAccess = false,
  });
}

class WorkspaceService {
  WorkspaceService(this._prefs);

  final SharedPreferences _prefs;

  static const _optInKey = 'workspace_share_with_termux';

  static const _channel = MethodChannel(AppConstants.safChannel);

  /// Whether the user asked for the shared folder. Independent of whether the
  /// system has granted access yet.
  bool get shareRequested => _prefs.getBool(_optInKey) ?? false;

  Future<void> setShareRequested(bool value) =>
      _prefs.setBool(_optInKey, value);

  /// Resolves the folder to use right now.
  ///
  /// Falls back to the app-private folder whenever the shared one is unavailable,
  /// so refusing the permission costs the user nothing but the sharing itself.
  Future<WorkspaceLocation> resolve(String privatePath) async {
    if (shareRequested && await _grantAvailable()) {
      final path = await _sharedPath();
      if (path != null && path.isNotEmpty) {
        return WorkspaceLocation(shared: true, path: path);
      }
    }
    return WorkspaceLocation(
      shared: false,
      path: privatePath,
      needsAllFilesAccess: shareRequested,
    );
  }

  /// Current grant state, for the settings screen to describe accurately.
  Future<WorkspaceLocation> status(String privatePath) async {
    final granted = await _grantAvailable();
    final sharedPath = granted ? await _sharedPath() : null;
    return WorkspaceLocation(
      shared: sharedPath != null && sharedPath.isNotEmpty,
      path: (sharedPath != null && sharedPath.isNotEmpty)
          ? sharedPath
          : privatePath,
      needsAllFilesAccess: shareRequested && !granted,
    );
  }

  /// Opens the system screen where All-files access is granted.
  ///
  /// Returns false when there is no such screen on this device, which happens on
  /// some heavily modified ROMs; the caller then leaves the toggle off and explains
  /// that sharing is unavailable rather than leaving a switch that does nothing.
  Future<bool> openAllFilesAccessSettings() async {
    try {
      final opened =
          await _channel.invokeMethod<bool>('openAllFilesAccessSettings') ??
              false;
      return opened;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _grantAvailable() async {
    try {
      final status = await _channel
          .invokeMapMethod<Object?, Object?>('sharedWorkspaceStatus');
      return status?['granted'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> _sharedPath() async {
    try {
      return await _channel.invokeMethod<String>('sharedWorkspacePath');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
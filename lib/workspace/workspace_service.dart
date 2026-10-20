import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Where the editor's files live, and whether that place is shared with other apps.
///
/// The default is an app-private folder: it needs no permission, works on every
/// device, and is what a first-time user should get without being interrupted by a
/// permission dialog.
///
/// The v1 release intentionally drops the shared folder (`/storage/emulated/0/BCode`)
/// and with it MANAGE_EXTERNAL_STORAGE: all-files access is a Play policy exception
/// for media apps, not a code editor. [resolve] therefore always answers with the
/// private workspace, and `WorkspaceLocation.needsAllFilesAccess` never becomes
/// true. Reintroducing sharing means shipping the permission again with a
/// vocational reason in the store listing.
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
  /// Always the app-private folder while the all-files grant is not declared:
  /// the channel would ask the OS for a grant the manifest cannot provide, so
  /// consult it only as a status display, never as the boot-time decision.
  Future<WorkspaceLocation> resolve(String privatePath) => Future.value(
      WorkspaceLocation(shared: false, path: privatePath));

  /// Opens the system screen where All-files access is granted.
  ///
  /// Returns false when there is no such screen on this device, which happens on
  /// some heavily modified ROMs. Kept for diagnostics; callers in v1 don't expose
  /// it because the manifest no longer declares the all-files permission.
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
}

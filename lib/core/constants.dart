class AppConstants {
  static const appId = 'com.bcode.editor';
  static const appName = 'B Code';

  static const githubApiBase = 'https://api.github.com';
  static const githubDeviceCodeUrl = 'https://github.com/login/device/code';
  static const githubTokenUrl = 'https://github.com/login/oauth/access_token';
  static const githubScopes = 'repo,read:user';

  /// GitHub OAuth App client ID. This is a public identifier by design — the
  /// device flow needs no client secret, and a secret compiled into a Flutter
  /// binary would be extractable regardless. Inject with
  /// `--dart-define=GITHUB_CLIENT_ID=...`; there is deliberately no default so
  /// a misconfigured CI build fails loudly instead of authenticating against an
  /// unknown app.
  static const githubClientId = String.fromEnvironment('GITHUB_CLIENT_ID');

  /// Stand-in used when no real client id was injected, so a debug build still
  /// starts.
  ///
  /// The alternative — throwing at startup — meant that `flutter run`, a plain
  /// `flutter build apk --debug` and therefore every adb install produced an app
  /// that died on launch with "B Code could not start", so the only way to try
  /// the editor was to remember a build flag. Release builds still refuse to
  /// start without a real id (see `_bootstrap`), because shipping a build that
  /// cannot sign in should fail at build time rather than at the login screen.
  static const unconfiguredClientId = 'bcode-unconfigured-client';

  /// Whether a real GitHub client id was compiled in.
  static bool get githubConfigured =>
      githubClientId.isNotEmpty && githubClientId != unconfiguredClientId;

  /// When true, the RASP layer must not kill sideloaded/F-Droid builds.
  /// Set with `--dart-define=ALLOW_SIDELOAD=true`.
  static const allowSideload = bool.fromEnvironment('ALLOW_SIDELOAD');

  static const execChannel = 'bcode.exec';
  static const termuxChannel = 'bcode.termux';
  static const safChannel = 'bcode.saf';
  static const storageChannel = 'bcode.storage';

  static const runtimesDirName = 'runtimes';

  static const bashPath = '/data/data/$appId/files/runtimes/bash/bin/bash';
  static const androidShPath = '/system/bin/sh';
  static const posixBashPath = '/bin/bash';
}

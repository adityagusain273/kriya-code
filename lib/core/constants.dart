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

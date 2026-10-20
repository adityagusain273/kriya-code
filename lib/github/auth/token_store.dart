import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the GitHub OAuth access token.
///
/// Uses `EncryptedSharedPreferences` (AES-256-GCM, key held in the Android
/// Keystore) rather than the package default. The default for
/// `AndroidOptions` is `encryptedSharedPreferences: false`, which writes a
/// plain `shared_prefs/FlutterSecureStorage.xml` holding an AES-128-CBC value
/// under an RSA-wrapped key. Not plaintext, but not what the store listing
/// claims either.
///
/// `resetOnError: true` covers the restore-from-backup case: the Keystore key
/// does not migrate, so a restored copy contains a value that cannot be
/// decrypted. Clearing it is the correct outcome.
class TokenStore {
  static const _key = 'github_oauth_token';

  /// Legacy key written by builds that used the default options.
  static const _legacyKey = 'github_oauth_token';

  final FlutterSecureStorage _storage;
  final FlutterSecureStorage _legacyStorage;

  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            ),
        _legacyStorage = const FlutterSecureStorage();

  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    if (value != null) return value;
    return _migrateLegacy();
  }

  /// Moves a token written by an older build into encrypted storage, then
  /// deletes the legacy copy.
  Future<String?> _migrateLegacy() async {
    try {
      final legacy = await _legacyStorage.read(key: _legacyKey);
      if (legacy == null || legacy.isEmpty) return null;
      await _storage.write(key: _key, value: legacy);
      await _legacyStorage.delete(key: _legacyKey);
      debugPrint('Migrated GitHub token to encrypted storage.');
      return legacy;
    } catch (e) {
      debugPrint('Legacy token migration skipped: $e');
      return null;
    }
  }

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() async {
    await _storage.delete(key: _key);
    try {
      await _legacyStorage.delete(key: _legacyKey);
    } catch (_) {}
  }
}
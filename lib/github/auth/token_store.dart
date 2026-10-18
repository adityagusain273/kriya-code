import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _key = 'github_oauth_token';
  final FlutterSecureStorage _storage;

  TokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() => _storage.delete(key: _key);
}

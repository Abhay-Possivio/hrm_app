import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _access = 'access_token';
const _refresh = 'refresh_token';

/// Flutter version of tokenService.
///
/// localStorage is synchronous, but secure storage on mobile is async, so
/// tokens are cached in memory: getAccess()/getRefresh() stay synchronous,
/// and load() restores them from disk once at startup.
class TokenService {
  TokenService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String? _accessToken;
  String? _refreshToken;

  /// Call once in main() before runApp().
  Future<void> load() async {
    _accessToken = await _storage.read(key: _access);
    _refreshToken = await _storage.read(key: _refresh);
  }

  String? getAccess() => _accessToken;

  String? getRefresh() => _refreshToken;

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    await _storage.write(key: _access, value: access);
    await _storage.write(key: _refresh, value: refresh);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }
}

final tokenService = TokenService();
import 'package:dio/dio.dart';

import '../api/api_client.dart';
import 'token_service.dart';

/// Thrown when the token endpoint responds 2xx but without both tokens.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._api, this._tokens);

  final Dio _api;
  final TokenService _tokens;

  Future<void> login(String username, String password) async {
    final res = await _api.post('/accounts/token/', data: {
      'username': username,
      'password': password,
    });

    final data = res.data;
    final access = data is Map ? data['access'] as String? : null;
    final refresh = data is Map ? data['refresh'] as String? : null;

    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      throw const AuthException('Login failed: missing authentication tokens.');
    }

    await _tokens.setTokens(access, refresh);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _api.get('/accounts/me/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<dynamic> changePassword(String currentPassword, String newPassword) async {
    final res = await _api.post('/accounts/password-change/', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    return res.data;
  }

  Future<void> logout() => _tokens.clear();

  Future<dynamic> requestPasswordReset(String email) async {
    final res = await _api.post('/accounts/password-reset/', data: {'email': email});
    return res.data;
  }

  Future<dynamic> confirmPasswordReset(Map<String, dynamic> data) async {
    final res = await _api.post('/accounts/password-reset/confirm/', data: data);
    return res.data;
  }
}

/// Shared instance, used the same way as the exported `authService` in React.
final authService = AuthService(api, tokenService);
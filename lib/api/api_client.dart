import 'package:dio/dio.dart';

import '../auth/token_service.dart';

/// Flutter's version of import.meta.env.VITE_API_BASE_URL. Set it with:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com/api
const baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.hrm.vivcom.ae/api',
);

/// Flutter's version of `window.location.href = "/login"`.
/// main.dart points this at AuthStore.logout, and the router's redirect
/// then sends the user to /login.
void Function()? onSessionExpired;

/// Endpoints where a 401 means "wrong credentials", not "access expired".
const _noRefreshPaths = {'/accounts/token/', '/accounts/token/refresh/'};

final api = _createApi();

Dio _createApi() {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  // Client without interceptors: the bare `axios` used for the refresh call
  // and the retry in the React version.
  final plain = Dio(BaseOptions(baseUrl: baseUrl));

  // One shared refresh at a time. With ROTATE_REFRESH_TOKENS=True, two
  // parallel refreshes would send the same token twice; the second would be
  // blacklisted and log the user out.
  Future<String>? refreshing;

  Future<String> refreshTokens() async {
    final refresh = tokenService.getRefresh();
    if (refresh == null) {
      throw StateError('Refresh token is missing.');
    }

    final res = await plain.post(
      '/accounts/token/refresh/',
      data: {'refresh': refresh},
    );

    // ROTATE_REFRESH_TOKENS=True: the server issues a NEW refresh token and
    // blacklists the old one, so store the new one when it's returned.
    final access = res.data['access'] as String;
    final newRefresh = res.data['refresh'] as String? ?? refresh;
    await tokenService.setTokens(access, newRefresh);
    return access;
  }

  // Attach access token automatically
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = tokenService.getAccess();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },

    // Silent refresh when access expires
    onError: (error, handler) async {
      final request = error.requestOptions;

      if (error.response?.statusCode != 401 ||
          _noRefreshPaths.contains(request.path)) {
        return handler.next(error);
      }

      String? access;
      try {
        refreshing ??= refreshTokens().whenComplete(() => refreshing = null);
        access = await refreshing;
      } catch (_) {
        await tokenService.clear();
        onSessionExpired?.call();
        return handler.next(error);
      }

      request.headers['Authorization'] = 'Bearer $access';
      try {
        handler.resolve(await plain.fetch(request));
      } on DioException catch (e) {
        handler.next(e);
      }
    },
  ));

  return dio;
}
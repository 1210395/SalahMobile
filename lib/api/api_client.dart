// سكن برو — Dio API client for the Laravel backend.

import 'package:dio/dio.dart';

/// Hosted production backend.
const String kProdApiBase = 'https://sakanpro.app/api';

/// Base URL resolution:
/// - by default (any build — debug or release) the app talks to the hosted
///   backend, so a plain `flutter build apk`/`flutter run` just works
/// - for local backend dev, override at build time with
///   `--dart-define=API_BASE=http://10.0.2.2:8000/api` (Android emulator) or
///   `--dart-define=API_BASE=http://127.0.0.1:8000/api` (web/desktop/iOS sim)
String resolveApiBase() {
  const override = String.fromEnvironment('API_BASE');
  if (override.isNotEmpty) return override;
  return kProdApiBase;
}

/// The site the backend serves its own pages from — the join/invite landing page
/// lives there, not under /api.
///
/// Derived from whatever base the build is pointed at, so moving the backend to
/// another domain moves the invite links with it. Hard-coding the host meant a
/// shipped APK would keep sending residents to the OLD site on move day, with
/// nothing in the app able to correct it.
String resolveSiteBase() {
  final base = resolveApiBase();
  final api = base.lastIndexOf('/api');

  return api > 0 ? base.substring(0, api) : base;
}

class ApiClient {
  ApiClient._() {
    dio = Dio(BaseOptions(
      baseUrl: resolveApiBase(),
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        // A 401 means the token expired or was revoked (a lapsed Sanctum token,
        // or a rotated single-use login-code) — drop the local token and let the
        // app end the session so a stale identity can't linger. The `_token`
        // guard makes this fire once (and avoids a loop on the logout call).
        if (e.response?.statusCode == 401 && _token != null) {
          _token = null;
          onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));
  }

  static final ApiClient I = ApiClient._();

  late final Dio dio;
  String? _token;

  /// Wired by the app to sign out + route to login when a request 401s.
  void Function()? onUnauthorized;

  void setToken(String? token) => _token = token;
  bool get hasToken => _token != null;
}

// عمارتي — Dio API client for the Laravel backend.

import 'package:dio/dio.dart';

/// Hosted production backend (Coolify @ Imarty.olive-dev.com).
const String kProdApiBase = 'https://imarty.olive-dev.com/api';

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
    ));
  }

  static final ApiClient I = ApiClient._();

  late final Dio dio;
  String? _token;

  void setToken(String? token) => _token = token;
  bool get hasToken => _token != null;
}

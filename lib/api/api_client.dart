// عمارتي — Dio API client for the Laravel backend.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Base URL resolution:
/// - override at build time with `--dart-define=API_BASE=http://host:port`
/// - Android emulator reaches the host machine via 10.0.2.2
/// - web / desktop / iOS simulator use localhost
String resolveApiBase() {
  const override = String.fromEnvironment('API_BASE');
  if (override.isNotEmpty) return override;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000/api';
  }
  return 'http://127.0.0.1:8000/api';
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

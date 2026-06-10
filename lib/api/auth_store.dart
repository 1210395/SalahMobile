// عمارتي — auth state: token persistence + login/OTP/logout against the API.

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.name,
    required this.role,
    required this.buildingKey,
    this.email,
    this.phone,
    this.unitNo,
  });
  final int id;
  final String name;
  final String role; // admin | resident | guest
  final String buildingKey; // residential | commercial
  final String? email;
  final String? phone;
  final String? unitNo;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        role: j['role'] ?? 'resident',
        buildingKey: j['building_key'] ?? 'residential',
        email: j['email'],
        phone: j['phone'],
        unitNo: j['unit_no'],
      );
}

class AuthStore {
  AuthStore._();
  static final AuthStore I = AuthStore._();

  static const _tokenKey = 'amarati_token';

  String? token;
  AuthUser? user;

  bool get isAuthed => token != null;

  Dio get _dio => ApiClient.I.dio;

  /// Restore a persisted token and re-fetch the user. Returns true if a valid
  /// session was restored.
  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null) return false;
    token = t;
    ApiClient.I.setToken(t);
    try {
      final res = await _dio.get('/me');
      user = AuthUser.fromJson(Map<String, dynamic>.from(res.data['user']));
      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<void> _persist(Map<String, dynamic> data) async {
    token = data['token'];
    user = AuthUser.fromJson(Map<String, dynamic>.from(data['user']));
    ApiClient.I.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token!);
  }

  Future<AuthUser> loginEmail(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Returns the dev OTP code in local environments (so the flow is testable
  /// without an SMS provider), or null in production.
  Future<String?> requestOtp(String phone) async {
    final res = await _dio.post('/auth/request-otp', data: {'phone': phone});
    return res.data['dev_code'] as String?;
  }

  Future<AuthUser> verifyOtp(String phone, String code,
      {String? role, String? buildingKey, String? name}) async {
    final res = await _dio.post('/auth/verify-otp', data: {
      'phone': phone,
      'code': code,
      'role': ?role,
      'building_key': ?buildingKey,
      // Optional full name captured on first sign-up (ignored by the backend if
      // the account already exists).
      'name': ?name,
    });
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  Future<void> logout() async {
    try {
      if (token != null) await _dio.post('/auth/logout');
    } catch (_) {}
    token = null;
    user = null;
    ApiClient.I.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

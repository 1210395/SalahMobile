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

  /// Re-fetch the current user (e.g. after a server-side role change).
  Future<void> refresh() async {
    if (token == null) return;
    final res = await _dio.get('/me');
    user = AuthUser.fromJson(Map<String, dynamic>.from(res.data['user']));
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

  /// Sign in with an identifier that may be an email OR a mobile number plus a
  /// password (the backend's `login` now accepts either). Sends `email` when the
  /// identifier looks like an email, otherwise `phone`.
  Future<AuthUser> loginIdentifier(String identifier, String password) async {
    final key = identifier.contains('@') ? 'email' : 'phone';
    final res = await _dio.post('/auth/login', data: {key: identifier, 'password': password});
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Redeem a resident login code (typed or scanned from a QR) and log in as
  /// that resident. Persists the token+user like [loginEmail].
  Future<AuthUser> redeemCode(String code) async {
    final res = await _dio.post('/auth/redeem-code', data: {'code': code});
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Create a new account (always a resident — role is server-decided).
  Future<AuthUser> register(String name, String email, String password,
      {String? phone, String? whatsapp}) async {
    final res = await _dio.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'phone': ?phone,
      'whatsapp': ?whatsapp,
    });
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Send an email confirmation code (mirrors the OTP flow). Returns the dev
  /// code in local environments so the flow is testable without SMTP, or null.
  Future<String?> requestEmailCode(String email) async {
    final res = await _dio.post('/auth/request-email-code', data: {'email': email});
    return res.data['dev_code'] as String?;
  }

  /// Verify an email confirmation code. Returns an error message on failure, or
  /// null when the code is accepted.
  Future<String?> verifyEmailCode(String email, String code) async {
    try {
      await _dio.post('/auth/verify-email-code', data: {'email': email, 'code': code});
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      return 'رمز التأكيد غير صحيح';
    }
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

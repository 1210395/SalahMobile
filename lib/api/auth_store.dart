// سكن برو — auth state: token persistence + login/OTP/logout against the API.

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.name,
    required this.role,
    required this.buildingKey,
    this.buildingId,
    this.email,
    this.phone,
    this.unitNo,
  });
  final int id;
  final String name;
  final String role; // admin | resident | guest
  final String buildingKey; // residential | commercial
  // null = belongs to NO building yet (a freshly-registered pending manager).
  // A renter placed by an admin always has one — used to tell the two apart.
  final int? buildingId;
  final String? email;
  final String? phone;
  final String? unitNo;

  /// A pending manager: registered, will create their own building at setup.
  /// Distinct from a placed renter who simply has no unit yet.
  bool get isPendingManager =>
      role == 'resident' && buildingId == null && (unitNo == null || unitNo!.trim().isEmpty);

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0,
        name: j['name'] ?? '',
        role: j['role'] ?? 'resident',
        buildingKey: j['building_key'] ?? 'residential',
        buildingId: j['building_id'] is int
            ? j['building_id']
            : int.tryParse('${j['building_id'] ?? ''}'),
        email: j['email'],
        phone: j['phone'],
        unitNo: j['unit_no'],
      );
}

/// One of the buildings an identifier opens an account in.
class BuildingChoice {
  const BuildingChoice({required this.id, required this.name, this.role = '', this.unitNo});
  final int id;
  final String name;
  final String role;
  final String? unitNo;

  factory BuildingChoice.fromJson(Map<String, dynamic> j) => BuildingChoice(
        id: j['building_id'] is int ? j['building_id'] : int.tryParse('${j['building_id']}') ?? 0,
        name: '${j['building_name'] ?? ''}',
        role: '${j['role'] ?? ''}',
        unitNo: j['unit_no'] == null ? null : '${j['unit_no']}',
      );
}

/// The same person may hold an account in several buildings (they rent in one
/// and own in another). When the credentials open more than one, the server
/// answers with the list instead of a token and the app asks which building.
class MultipleBuildingsException implements Exception {
  const MultipleBuildingsException(this.choices);
  final List<BuildingChoice> choices;
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
    // No token + a `choose` list: the credentials matched accounts in several
    // buildings and the caller must name one.
    final choose = data['choose'];
    if (data['token'] == null && choose is List) {
      throw MultipleBuildingsException(
        [for (final c in choose) BuildingChoice.fromJson(Map<String, dynamic>.from(c))],
      );
    }
    token = data['token'];
    user = AuthUser.fromJson(Map<String, dynamic>.from(data['user']));
    ApiClient.I.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token!);
  }

  Future<AuthUser> loginEmail(String email, String password, {int? buildingId}) async {
    final res = await _dio.post('/auth/login',
        data: {'email': email, 'password': password, 'building_id': ?buildingId});
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Sign in with an identifier that may be an email OR a mobile number plus a
  /// password (the backend's `login` now accepts either). Sends `email` when the
  /// identifier looks like an email, otherwise `phone`.
  Future<AuthUser> loginIdentifier(String identifier, String password, {int? buildingId}) async {
    final key = identifier.contains('@') ? 'email' : 'phone';
    final res = await _dio.post('/auth/login',
        data: {key: identifier, 'password': password, 'building_id': ?buildingId});
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
      {String? phone, String? whatsapp, String? emailCode}) async {
    final res = await _dio.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'phone': ?phone,
      'whatsapp': ?whatsapp,
      // The code is verified atomically server-side, so a failed register never
      // consumes it (which used to make the correct code read as "wrong").
      'email_code': ?emailCode,
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
      {String? role, String? buildingKey, String? name, int? buildingId}) async {
    final res = await _dio.post('/auth/verify-otp', data: {
      'phone': phone,
      'code': code,
      // Which building's account, when the number opens more than one. The code
      // is NOT consumed while choosing, so the same one is re-sent here.
      'building_id': ?buildingId,
      'role': ?role,
      'building_key': ?buildingKey,
      // Optional full name captured on first sign-up (ignored by the backend if
      // the account already exists).
      'name': ?name,
    });
    await _persist(Map<String, dynamic>.from(res.data));
    return user!;
  }

  /// Ask for a password-reset code. Returns the dev code when the deployment has
  /// no mailer (so the flow stays usable), else null — the code went by e-mail.
  Future<String?> forgotPassword(String email) async {
    final res = await _dio.post('/auth/forgot-password', data: {'email': email});
    return res.data['dev_code'] as String?;
  }

  /// Consume the code, set the new password, and open the session it returns.
  /// Throws [MultipleBuildingsException] when the address opens accounts in more
  /// than one building — the code is NOT consumed then, so the retry works.
  Future<AuthUser> resetPassword(String email, String code, String password,
      {int? buildingId}) async {
    final res = await _dio.post('/auth/reset-password', data: {
      'email': email,
      'code': code,
      'password': password,
      'building_id': ?buildingId,
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

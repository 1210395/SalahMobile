// عمارتي — repository: fetches API data into the runtime DataStore so every
// screen renders live data through its existing (synchronous) accessors.

import 'package:dio/dio.dart';

import '../data/sample_data.dart';
import 'api_client.dart';

/// Human (Arabic) message for an API/network error — surfaced via toast.
String apiErrorText(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'تعذّر الاتصال بالخادم';
    }
  }
  return 'حدث خطأ، حاول مرة أخرى';
}

class Api {
  Api._();
  static final Api I = Api._();

  Dio get _dio => ApiClient.I.dio;

  List<Map<String, dynamic>> _list(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic> _obj(dynamic data) => Map<String, dynamic>.from(data);

  /// Load every collection for [b] (authenticated) into [DataStore].
  ///
  /// Requests are issued sequentially: the local `php artisan serve` dev server
  /// is single-threaded, so a burst of parallel requests can stall it. A real
  /// (fpm/nginx) deployment handles concurrency fine, but sequential is safe
  /// everywhere and the payloads are tiny.
  Future<void> loadBundle(BType b) async {
    final q = {'btype': btypeKey(b)};
    Future<dynamic> get(String path, [Map<String, dynamic>? extra]) =>
        _dio.get(path, queryParameters: {...q, ...?extra}).then((r) => r.data);

    final building = await get('/building');
    final summary = await get('/summary');
    final units = await get('/units');
    final payments = await get('/payments');
    final expenses = await get('/expenses');
    final workers = await get('/workers');
    final parking = await get('/parking');
    final guard = await get('/guard');
    final alerts = await get('/alerts');
    final year = await get('/year-summary', {'year': '2026'});
    final craftsmen = await _dio.get('/craftsmen').then((r) => r.data);
    final waTemplates = await _dio.get('/wa-templates').then((r) => r.data);
    final payTypes = await _dio.get('/pay-types').then((r) => r.data);

    final s = DataStore.I;
    s.loadedBtype = b;
    s.building = Building.fromJson(_obj(building));
    s.summary = SummaryData.fromJson(_obj(summary));
    s.units = _list(units).map(Unit.fromJson).toList();
    s.payments = _list(payments).map(Payment.fromJson).toList();
    s.expenses = _list(expenses).map(Expense.fromJson).toList();
    s.workers = _list(workers).map(Worker.fromJson).toList();
    s.parking = _list(parking).map(ParkingSpot.fromJson).toList();
    s.guard = Guard.fromJson(_obj(guard));
    s.alerts = _list(alerts).map(AlertItem.fromJson).toList();
    s.year = YearData.fromJson(_obj(year));
    s.craftsmen = _list(craftsmen).map(Craftsman.fromJson).toList();
    s.waTemplates = _list(waTemplates).map(WaTemplate.fromJson).toList();
    s.payTypes = _list(payTypes).map(PayType.fromJson).toList();
  }

  // ───────────────────────────── Writes ─────────────────────────────
  // building_key is derived server-side from ?btype for admins, so every write
  // carries the active building type as a query param.

  Future<void> createPayment(BType b, Map<String, dynamic> body) =>
      _dio.post('/payments', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> createExpense(BType b, Map<String, dynamic> body) =>
      _dio.post('/expenses', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> createWorker(BType b, Map<String, dynamic> body) =>
      _dio.post('/workers', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> createCraftsman(Map<String, dynamic> body) =>
      _dio.post('/craftsmen', data: body);

  // ───────────── Units CRUD (#2) ─────────────
  Future<void> createUnit(BType b, Map<String, dynamic> body) =>
      _dio.post('/units', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> updateUnit(BType b, int id, Map<String, dynamic> body) =>
      _dio.put('/units/$id', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> deleteUnit(BType b, int id) =>
      _dio.delete('/units/$id', queryParameters: {'btype': btypeKey(b)});

  // ───────────── Building edit (#3) ─────────────
  Future<void> updateBuilding(BType b, Map<String, dynamic> body) =>
      _dio.put('/building', queryParameters: {'btype': btypeKey(b)}, data: body);

  // ───────────── Resident notes (#4) ─────────────
  Future<void> createNote(String body) => _dio.post('/notes', data: {'body': body});

  Future<List<Map<String, dynamic>>> listNotes(BType b) =>
      _dio.get('/notes', queryParameters: {'btype': btypeKey(b)}).then((r) => _list(r.data));

  // ───────────── Alerts engine (#9) ─────────────
  Future<int> regenerateAlerts(BType b) async {
    final res = await _dio.post('/alerts/regenerate', queryParameters: {'btype': btypeKey(b)});
    return (res.data['generated'] as num?)?.toInt() ?? 0;
  }

  // ───────────── Onboarding (#1, #11) ─────────────
  Future<Map<String, dynamic>> subscription(BType b) =>
      _dio.get('/subscription', queryParameters: {'btype': btypeKey(b)}).then((r) => _obj(r.data));

  Future<Map<String, dynamic>> activateSubscription(BType b) => _dio
      .post('/subscription/activate', data: {'btype': btypeKey(b)}).then((r) => _obj(r.data));

  /// Returns the updated user (now an admin of [b]) so the app can refresh role.
  Future<Map<String, dynamic>> setupBuilding(BType b, Map<String, dynamic> body) => _dio
      .post('/building/setup', data: {...body, 'btype': btypeKey(b)})
      .then((r) => _obj(r.data['user']));

  Future<void> createJoinRequest(BType b, Map<String, dynamic> body) =>
      _dio.post('/join-requests', data: {...body, 'btype': btypeKey(b)});

  Future<List<Map<String, dynamic>>> listJoinRequests(BType b) => _dio
      .get('/join-requests', queryParameters: {'btype': btypeKey(b)}).then((r) => _list(r.data));

  Future<void> approveJoinRequest(BType b, int id) => _dio
      .post('/join-requests/$id/approve', queryParameters: {'btype': btypeKey(b)});

  Future<void> rejectJoinRequest(BType b, int id) => _dio
      .post('/join-requests/$id/reject', queryParameters: {'btype': btypeKey(b)});

  // ───────────── Brand / settings (#10) ─────────────
  Future<void> loadSettings() async {
    try {
      final data = (await _dio.get('/settings')).data;
      DataStore.I.settings = Map<String, dynamic>.from(data)
          .map((k, v) => MapEntry(k, '${v ?? ''}'));
    } catch (_) {
      // keep brand defaults if settings can't be fetched
    }
  }

  Future<void> updateSettings(Map<String, dynamic> body) async {
    final data = (await _dio.put('/settings', data: body)).data;
    DataStore.I.settings =
        Map<String, dynamic>.from(data).map((k, v) => MapEntry(k, '${v ?? ''}'));
  }

  Future<void> uploadLogo(List<int> bytes, String filename) async {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'png';
    final form = FormData.fromMap({
      'logo': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType('image', ext == 'jpg' ? 'jpeg' : ext),
      ),
    });
    final data = (await _dio.post('/settings/logo', data: form)).data;
    DataStore.I.settings =
        Map<String, dynamic>.from(data).map((k, v) => MapEntry(k, '${v ?? ''}'));
  }

  // ───────────── Super-admin (#6) ─────────────
  Future<Map<String, dynamic>> globalReport({int? month, BType? btype}) async {
    final q = <String, dynamic>{};
    if (month != null) q['month'] = '$month';
    if (btype != null) q['btype'] = btypeKey(btype);
    final data = (await _dio.get('/reports/global', queryParameters: q)).data;
    return _obj(data);
  }

  Future<List<Map<String, dynamic>>> listAdmins() async =>
      _list((await _dio.get('/admins')).data);

  Future<void> createAdmin(Map<String, dynamic> body) => _dio.post('/admins', data: body);

  /// Resident's own receipts (their unit only).
  Future<List<Payment>> myPayments() async {
    final data = (await _dio.get('/me/payments')).data;
    return _list(data).map(Payment.fromJson).toList();
  }

  /// Guest mode — only the public building summary is available (no token).
  Future<void> loadGuest(BType b) async {
    final q = {'btype': btypeKey(b)};
    final building = (await _dio.get('/building', queryParameters: q)).data;
    final summary = (await _dio.get('/summary', queryParameters: q)).data;
    final s = DataStore.I;
    s.loadedBtype = b;
    s.building = Building.fromJson(_obj(building));
    s.summary = SummaryData.fromJson(_obj(summary));
  }
}

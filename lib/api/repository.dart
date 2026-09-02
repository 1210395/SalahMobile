// سكن برو — repository: fetches API data into the runtime DataStore so every
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

    // Building-wide financials are admin-only (a resident gets 403). Fail soft so
    // a resident's bundle still loads — their summary/year just stay zeroed.
    Future<dynamic> getSoft(String path, [Map<String, dynamic>? extra]) async {
      try {
        return await get(path, extra);
      } catch (_) {
        return null;
      }
    }

    // One request for the whole first paint. Each section is only a few
    // milliseconds of server work but a full round trip of waiting, so fetching
    // them one after another cost about 1.8 seconds on a fast network and far
    // more on mobile. A server that predates /bundle (during the host move)
    // answers 404, and the old path below still works.
    dynamic building, summary, units, payments, expenses, workers, parking,
        guard, alerts, year, craftsmen, waTemplates, payTypes;

    Map<String, dynamic>? packed;
    try {
      packed = _obj(await get('/bundle', {'year': '${DateTime.now().year}'}));
    } catch (_) {
      packed = null;
    }

    if (packed != null) {
      building = packed['building'];
      summary = packed['summary'];
      units = packed['units'] ?? const [];
      payments = packed['payments'] ?? const [];
      expenses = packed['expenses'] ?? const [];
      workers = packed['workers'] ?? const [];
      parking = packed['parking'] ?? const [];
      guard = packed['guard'];
      alerts = packed['alerts'] ?? const [];
      year = packed['year_summary'];
      craftsmen = packed['craftsmen'] ?? const [];
      waTemplates = packed['wa_templates'] ?? const [];
      payTypes = packed['pay_types'] ?? const [];
    } else {
      building = await get('/building');
      summary = await getSoft('/summary');
      units = await get('/units');
      payments = await get('/payments');
      expenses = await get('/expenses');
      workers = await get('/workers');
      parking = await get('/parking');
      guard = await get('/guard');
      alerts = await get('/alerts');
      year = await getSoft('/year-summary', {'year': '${DateTime.now().year}'});
      craftsmen = await _dio.get('/craftsmen').then((r) => r.data);
      waTemplates = await _dio.get('/wa-templates').then((r) => r.data);
      payTypes = await _dio.get('/pay-types').then((r) => r.data);
    }

    final s = DataStore.I;
    final b0 = _obj(building);
    s.building = Building.fromJson(b0);
    // Multi-building: the server returns the user's OWN building regardless of the
    // requested ?btype. Key the loaded dataset off the building the server
    // actually returned (its `key`/`type`), not the requested type — otherwise
    // the data getters (kApartments/kShops) and buildingFor() mismatch and the
    // UI shows a blank name / empty lists.
    final key = '${b0['key'] ?? ''}';
    final type = '${b0['type'] ?? ''}';
    s.loadedBtype = (key == 'commercial' || type == 'تجاري')
        ? BType.commercial
        : (key == 'residential' || type == 'سكني' ? BType.residential : b);
    s.summary = SummaryData.fromJson(_obj(summary));
    s.units = _list(units).map(Unit.fromJson).toList();
    s.payments = _list(payments).map(Payment.fromJson).toList();
    s.expenses = _list(expenses).map(Expense.fromJson).toList();
    s.workers = _list(workers).map(Worker.fromJson).toList();
    s.parking = _list(parking).map(ParkingSpot.fromJson).toList();
    s.guard = Guard.fromJson(guard == null ? const {} : _obj(guard));
    s.alerts = _list(alerts).map(AlertItem.fromJson).toList();
    s.year = YearData.fromJson(_obj(year));
    s.craftsmen = _list(craftsmen).map(Craftsman.fromJson).toList();
    s.waTemplates = _list(waTemplates).map(WaTemplate.fromJson).toList();
    s.payTypes = _list(payTypes).map(PayType.fromJson).toList();
  }

  /// Re-fetch only the live summary for a period (year + optional 0-based month)
  /// so the dashboard totals reflect the selected time window.
  Future<void> fetchSummary(BType b, {required int year, int? month}) async {
    final q = {
      'btype': btypeKey(b),
      'year': '$year',
      if (month != null) 'month': '$month', // backend month param is 0-based
    };
    final summary = (await _dio.get('/summary', queryParameters: q)).data;
    DataStore.I.summary = SummaryData.fromJson(_obj(summary));
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

  Future<void> updateWorker(BType b, int id, Map<String, dynamic> body) =>
      _dio.put('/workers/$id', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> deleteWorker(BType b, int id) =>
      _dio.delete('/workers/$id', queryParameters: {'btype': btypeKey(b)});

  /// Manager composes a push/internal notification to all residents or one unit.
  Future<void> sendNotification(BType b, Map<String, dynamic> body) =>
      _dio.post('/notifications', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> createCraftsman(Map<String, dynamic> body) =>
      _dio.post('/craftsmen', data: body);

  /// Remove an entry from this building's directory. A wrong number used to be
  /// permanent — and visible to every other building on the platform.
  Future<void> deleteCraftsman(int id) => _dio.delete('/craftsmen/$id');

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

  // ───────────── Admin creates a renter / co-admin ─────────────
  Future<void> createResident(BType b, Map<String, dynamic> body) =>
      _dio.post('/residents', queryParameters: {'btype': btypeKey(b)}, data: body);

  Future<void> createCoAdmin(BType b, Map<String, dynamic> body) =>
      _dio.post('/co-admins', queryParameters: {'btype': btypeKey(b)}, data: body);

  /// Set (or create) the login for the renter on a unit; reissues their QR code.
  /// كشف حساب الساكن — personal record, both pots, and the dated statement.
  /// Assembled server-side so the screen, a PDF and an export always agree.
  Future<Map<String, dynamic>> unitStatement(BType b, int unitId) async {
    final r = await _dio.get('/units/$unitId/statement',
        queryParameters: {'btype': btypeKey(b)});
    return Map<String, dynamic>.from(r.data);
  }

  /// Set the renter's password (this also reissues their QR). Returns the
  /// updated resident record so the caller can show the new login code — the
  /// password itself is only ever known here, at the moment it is set.
  Future<Map<String, dynamic>> setUnitPassword(BType b, int unitId, String password) async {
    final r = await _dio.post('/units/$unitId/password',
        queryParameters: {'btype': btypeKey(b)}, data: {'password': password});
    return Map<String, dynamic>.from(r.data);
  }

  // ───────────── Payments / expenses edit + delete ─────────────
  Future<void> updatePayment(BType b, int id, Map<String, dynamic> body) =>
      _dio.put('/payments/$id', queryParameters: {'btype': btypeKey(b)}, data: body);
  Future<void> deletePayment(BType b, int id) =>
      _dio.delete('/payments/$id', queryParameters: {'btype': btypeKey(b)});
  Future<void> updateExpense(BType b, int id, Map<String, dynamic> body) =>
      _dio.put('/expenses/$id', queryParameters: {'btype': btypeKey(b)}, data: body);
  Future<void> deleteExpense(BType b, int id) =>
      _dio.delete('/expenses/$id', queryParameters: {'btype': btypeKey(b)});

  // ───────────── Guard upsert + parking CRUD ─────────────
  Future<void> setGuard(BType b, Map<String, dynamic> body) =>
      _dio.put('/guard', queryParameters: {'btype': btypeKey(b)}, data: body);
  Future<void> createParking(BType b, Map<String, dynamic> body) =>
      _dio.post('/parking', queryParameters: {'btype': btypeKey(b)}, data: body);
  Future<void> updateParking(BType b, String id, Map<String, dynamic> body) =>
      _dio.put('/parking/$id', queryParameters: {'btype': btypeKey(b)}, data: body);
  Future<void> deleteParking(BType b, String id) =>
      _dio.delete('/parking/$id', queryParameters: {'btype': btypeKey(b)});

  Future<void> updatePayType(int id, Map<String, dynamic> body) =>
      _dio.put('/pay-types/$id', data: body);

  // ───────────── Resident notes (#4) ─────────────
  Future<void> createNote(String body) => _dio.post('/notes', data: {'body': body});

  Future<List<Map<String, dynamic>>> listNotes(BType b) =>
      _dio.get('/notes', queryParameters: {'btype': btypeKey(b)}).then((r) => _list(r.data));

  Future<void> markNoteRead(int id) => _dio.post('/notes/$id/read');

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
      DataStore.I.applySettingsJson(data);
    } catch (_) {
      // keep brand defaults if settings can't be fetched
    }
  }

  Future<void> updateSettings(Map<String, dynamic> body) async {
    final data = (await _dio.put('/settings', data: body)).data;
    DataStore.I.applySettingsJson(data);
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
    DataStore.I.applySettingsJson(data);
  }

  // ───────────── Super-admin (#6) ─────────────
  Future<Map<String, dynamic>> globalReport({int? month, BType? btype}) async {
    final q = <String, dynamic>{};
    if (month != null) q['month'] = '$month';
    if (btype != null) q['btype'] = btypeKey(btype);
    final data = (await _dio.get('/reports/global', queryParameters: q)).data;
    return _obj(data);
  }

  /// The buildings a signed-in user may pick from: {id, key, name, type}. Needed
  /// because a building TYPE ('سكني') is not an identity — several buildings share
  /// one — so joining a building, or creating its admin, must name it by id.
  Future<List<Map<String, dynamic>>> listBuildings() async =>
      _list((await _dio.get('/buildings')).data);

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
    // Guests get only the public building shell (name/theme) — financials are
    // login-only, so the summary stays zeroed (a guest never sees real money).
    final q = {'btype': btypeKey(b)};
    final building = (await _dio.get('/building', queryParameters: q)).data;
    final s = DataStore.I;
    s.loadedBtype = b;
    s.building = Building.fromJson(_obj(building));
    s.summary = SummaryData.fromJson(const {});
  }
}

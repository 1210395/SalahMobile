// عمارتي — repository: fetches API data into the runtime DataStore so every
// screen renders live data through its existing (synchronous) accessors.

import 'package:dio/dio.dart';

import '../data/sample_data.dart';
import 'api_client.dart';

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

// عمارتي — models, helpers, and the runtime DataStore.
//
// Every public accessor (kApartments, kPayments, Summary.*, …) returns LIVE
// data from [DataStore] once a session has loaded it from the Laravel API, and
// an EMPTY value otherwise. No bundled sample data — real users start empty.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Supported currencies (code → symbol). The active building's currency drives
/// how money is displayed app-wide.
const Map<String, String> kCurrencySymbols = {
  'NIS': '₪', 'JOD': 'د.أ', 'USD': '\$', 'SAR': 'ر.س', 'AED': 'د.إ',
  'EGP': 'ج.م', 'KWD': 'د.ك', 'QAR': 'ر.ق', 'BHD': 'د.ب', 'OMR': 'ر.ع',
  'TRY': '₺', 'EUR': '€', 'GBP': '£', 'JD': 'د.أ', 'ILS': '₪',
};
List<String> get kCurrencyCodes => kCurrencySymbols.keys.toList();

String currencySymbol(String code) => kCurrencySymbols[code] ?? code;

/// The active building's base currency (from live data, else USD).
String get activeCurrency => DataStore.I.building?.currency ?? 'USD';

/// Group digits with thousands separators (e.g. 25840 -> "25,840").
String _grouped(num n, {bool dec = false}) {
  final abs = n.abs();
  final whole = abs.truncate();
  final s = whole.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  var out = buf.toString();
  if (dec) {
    final frac = ((abs - whole) * 100).round().toString().padLeft(2, '0');
    out = '$out.$frac';
  }
  return out;
}

/// Group digits with thousands separators, no currency symbol.
String groupNumber(num n, {bool dec = false}) => _grouped(n, dec: dec);

/// Format money in a specific currency: "$" prefixes, others suffix the symbol.
String fmtMoney(num n, String code, {bool dec = false}) {
  final sign = n < 0 ? '-' : '';
  final sym = currencySymbol(code);
  final num = _grouped(n, dec: dec);
  return sym == '\$' ? '$sign$sym$num' : '$sign$num $sym';
}

/// Format money in the active building's currency. Kept named `fmtUSD` so the
/// hundreds of existing call sites stay currency-aware without churn.
String fmtUSD(num n, {bool dec = false}) => fmtMoney(n, activeCurrency, dec: dec);

const List<String> arMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

enum BType { residential, commercial }

BType btypeFromKey(String? k) =>
    k == 'commercial' ? BType.commercial : BType.residential;
String btypeKey(BType b) => b == BType.commercial ? 'commercial' : 'residential';

/// Map an API color token (e.g. "navy600", "ok") to a brand color.
Color colorFromName(String? name) {
  switch (name) {
    case 'navy600':
      return AppColors.navy600;
    case 'gold500':
      return AppColors.gold500;
    case 'late':
      return AppColors.late;
    case 'ok':
      return AppColors.ok;
    case 'credit':
      return AppColors.credit;
    case 'warn':
      return AppColors.warn;
    default:
      return AppColors.navy600;
  }
}

int _int(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

// ───────────────────────────── Models ─────────────────────────────

class Building {
  const Building({
    required this.name,
    required this.address,
    required this.units,
    required this.type,
    required this.subscription,
    required this.currency,
    required this.floors,
    this.exchangeRate = 1,
    this.elevatorFee = 0,
  });
  final String name;
  final String address;
  final int units;
  final String type;
  final int subscription;
  final String currency;
  final int floors;
  final double exchangeRate; // entered-currency → base
  final int elevatorFee;     // monthly elevator fee (base currency)

  factory Building.fromJson(Map<String, dynamic> j) => Building(
        name: j['name'] ?? '',
        address: j['address'] ?? '',
        units: _int(j['units_count']),
        type: j['type'] ?? '',
        subscription: _int(j['subscription']),
        currency: j['currency'] ?? 'USD',
        floors: _int(j['floors']),
        exchangeRate: (j['exchange_rate'] is num)
            ? (j['exchange_rate'] as num).toDouble()
            : double.tryParse('${j['exchange_rate'] ?? 1}') ?? 1,
        elevatorFee: _int(j['elevator_fee']),
      );
}

class Unit {
  const Unit({
    required this.id,
    required this.no,
    required this.floor,
    required this.resident,
    required this.kind,
    required this.phone,
    required this.sub,
    required this.status,
    required this.balance,
    required this.payer,
    this.dbId = 0,
  });
  final String id;
  final String no;
  final int floor;
  final String resident;
  final String kind;
  final String phone;
  final int sub;
  final String status;
  final int balance;
  final String payer;
  final int dbId; // server primary key (0 for bundled seed units)

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: '${j['ext_id'] ?? j['id']}',
        dbId: _int(j['id']),
        no: '${j['no']}',
        floor: _int(j['floor']),
        resident: j['resident'] ?? '',
        kind: j['kind'] ?? '',
        phone: j['phone'] ?? '—',
        sub: _int(j['sub']),
        status: j['status'] ?? 'ok',
        balance: _int(j['balance']),
        payer: j['payer'] ?? '—',
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.unit,
    required this.name,
    required this.amount,
    required this.kind,
    required this.month,
    required this.year,
    required this.date,
    required this.method,
  });
  final int id;
  final String unit;
  final String name;
  final int amount;
  final String kind;
  final int month;
  final int year;
  final String date;
  final String method;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: _int(j['id']),
        unit: '${j['unit_no'] ?? j['unit']}',
        name: j['name'] ?? '',
        amount: _int(j['amount']),
        kind: j['kind'] ?? '',
        month: _int(j['month']),
        year: _int(j['year']),
        date: '${j['date']}'.split('T').first,
        method: j['method'] ?? '',
      );
}

class PayType {
  const PayType({required this.id, required this.label, required this.amount, required this.on, required this.opt});
  final String id;
  final String label;
  final int amount;
  final bool on;
  final bool opt;

  factory PayType.fromJson(Map<String, dynamic> j) => PayType(
        id: j['key'] ?? j['id'] ?? '',
        label: j['label'] ?? '',
        amount: _int(j['amount']),
        on: j['enabled'] == true || j['enabled'] == 1,
        opt: j['optional'] == true || j['optional'] == 1,
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.cat,
    required this.icon,
    required this.tone,
    required this.supplier,
    required this.amount,
    required this.date,
    required this.desc,
  });
  final int id;
  final String cat;
  final String icon;
  final String tone;
  final String supplier;
  final int amount;
  final String date;
  final String desc;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: _int(j['id']),
        cat: j['cat'] ?? '',
        icon: j['icon'] ?? 'receipt',
        tone: j['tone'] ?? 'gold',
        supplier: j['supplier'] ?? '',
        amount: _int(j['amount']),
        date: '${j['date']}'.split('T').first,
        desc: j['description'] ?? j['desc'] ?? '',
      );
}

class Worker {
  const Worker({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    required this.address,
    required this.cycle,
    required this.amount,
    required this.last,
    required this.next,
  });
  final int id;
  final String name;
  final String type;
  final String phone;
  final String address;
  final String cycle;
  final int amount;
  final String last;
  final String next;

  factory Worker.fromJson(Map<String, dynamic> j) => Worker(
        id: _int(j['id']),
        name: j['name'] ?? '',
        type: j['type'] ?? '',
        phone: j['phone'] ?? '',
        address: j['address'] ?? '',
        cycle: j['cycle'] ?? '',
        amount: _int(j['amount']),
        last: '${j['last_payment'] ?? j['last']}'.split('T').first,
        next: '${j['next_due'] ?? j['next']}'.split('T').first,
      );
}

class ParkingSpot {
  const ParkingSpot({
    required this.id,
    required this.no,
    required this.status,
    required this.unit,
    required this.code,
    required this.note,
  });
  final String id;
  final String no;
  final String status;
  final String unit;
  final String code;
  final String note;

  factory ParkingSpot.fromJson(Map<String, dynamic> j) => ParkingSpot(
        id: '${j['id']}',
        no: '${j['no']}',
        status: j['status'] ?? '',
        unit: j['unit_no'] ?? j['unit'] ?? '',
        code: j['code'] ?? '—',
        note: j['note'] ?? '',
      );
}

class Guard {
  const Guard({
    required this.name,
    required this.phone,
    required this.address,
    required this.fee,
    required this.last,
    required this.next,
  });
  final String name;
  final String phone;
  final String address;
  final int fee;
  final String last;
  final String next;

  factory Guard.fromJson(Map<String, dynamic> j) => Guard(
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        address: j['address'] ?? '',
        fee: _int(j['fee']),
        last: '${j['last_payment'] ?? j['last']}'.split('T').first,
        next: '${j['next_due'] ?? j['next']}'.split('T').first,
      );
}

class Craftsman {
  const Craftsman({required this.id, required this.name, required this.job, required this.phone, required this.note});
  final int id;
  final String name;
  final String job;
  final String phone;
  final String note;

  factory Craftsman.fromJson(Map<String, dynamic> j) => Craftsman(
        id: _int(j['id']),
        name: j['name'] ?? '',
        job: j['job'] ?? '',
        phone: j['phone'] ?? '',
        note: j['note'] ?? '',
      );
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.type,
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.time,
    required this.channel,
  });
  final int id;
  final String type;
  final String icon;
  final String tone;
  final String title;
  final String body;
  final String time;
  final String channel;

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
        id: _int(j['id']),
        type: j['type'] ?? '',
        icon: j['icon'] ?? 'bell',
        tone: j['tone'] ?? 'navy',
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        time: j['time_label'] ?? j['time'] ?? '',
        channel: j['channel'] ?? 'internal',
      );
}

class WaTemplate {
  const WaTemplate({required this.id, required this.label, required this.text});
  final int id;
  final String label;
  final String text;

  factory WaTemplate.fromJson(Map<String, dynamic> j) => WaTemplate(
        id: _int(j['id']),
        label: j['label'] ?? '',
        text: j['text'] ?? '',
      );
}

class MonthRow {
  const MonthRow({required this.m, required this.paid, required this.total});
  final int m;
  final int paid;
  final int total;

  factory MonthRow.fromJson(Map<String, dynamic> j) =>
      MonthRow(m: _int(j['m']), paid: _int(j['paid']), total: _int(j['total']));
}

class YearData {
  const YearData({required this.year, required this.openingBalance, required this.months});
  final int year;
  final int openingBalance;
  final List<MonthRow> months;

  factory YearData.fromJson(Map<String, dynamic> j) => YearData(
        year: _int(j['year']),
        openingBalance: _int(j['opening_balance']),
        months: (j['months'] as List? ?? [])
            .map((m) => MonthRow.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

class ChartDatum {
  const ChartDatum({required this.label, required this.value, required this.color, this.label2});
  final String label;
  final num value;
  final Color color;
  final String? label2;

  factory ChartDatum.fromJson(Map<String, dynamic> j) => ChartDatum(
        label: j['label'] ?? '',
        value: _int(j['value']),
        color: colorFromName(j['color']),
      );
}

class SummaryData {
  const SummaryData({
    required this.balance,
    required this.due,
    required this.revenueM,
    required this.expenseM,
    required this.bars,
    required this.trend,
  });
  final int balance;
  final int due;
  final int revenueM;
  final int expenseM;
  final List<ChartDatum> bars;
  final List<ChartDatum> trend;

  factory SummaryData.fromJson(Map<String, dynamic> j) {
    List<ChartDatum> list(String k) => (j[k] as List? ?? [])
        .map((e) => ChartDatum.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return SummaryData(
      balance: _int(j['balance']),
      due: _int(j['due']),
      revenueM: _int(j['revenueM']),
      expenseM: _int(j['expenseM']),
      bars: list('bars'),
      trend: list('trend'),
    );
  }
}

// ───────────────────────── Runtime data store ─────────────────────────

/// Holds the live bundle for the currently active building type. Populated by
/// the API repository after sign-in; cleared on logout.
class DataStore {
  DataStore._();
  static final DataStore I = DataStore._();

  BType? loadedBtype;
  Building? building;
  SummaryData? summary;
  List<Unit>? units;
  List<Payment>? payments;
  List<Expense>? expenses;
  List<Worker>? workers;
  List<ParkingSpot>? parking;
  Guard? guard;
  List<AlertItem>? alerts;
  YearData? year;
  // Global (not building-scoped).
  List<Craftsman>? craftsmen;
  List<WaTemplate>? waTemplates;
  List<PayType>? payTypes;
  Map<String, String>? settings; // editable brand / app settings

  bool get loaded => units != null;

  void clear() {
    loadedBtype = null;
    building = null;
    summary = null;
    units = null;
    payments = null;
    expenses = null;
    workers = null;
    parking = null;
    guard = null;
    alerts = null;
    year = null;
    craftsmen = null;
    waTemplates = null;
    payTypes = null;
  }
}

// ──────────────────── Public accessors (live data only) ────────────────────
// No bundled sample data. Every accessor returns the live bundle, or an EMPTY
// value when nothing is loaded — so real users start completely empty and a
// failed/absent load never shows fake numbers.

const List<String> kExpCats = ['مصعد', 'نظافة', 'كهرباء', 'صيانة', 'أخرى'];

const Building _emptyBuilding = Building(
    name: '', address: '', units: 0, type: '', subscription: 0, currency: 'USD', floors: 0);
const Guard _emptyGuard =
    Guard(name: '', phone: '', address: '', fee: 0, last: '—', next: '—');
const SummaryData _zeroSummary = SummaryData(
    balance: 0, due: 0, revenueM: 0, expenseM: 0, bars: [], trend: []);

final DataStore _s = DataStore.I;
bool get _resLoaded => _s.loaded && _s.loadedBtype == BType.residential;
bool get _comLoaded => _s.loaded && _s.loadedBtype == BType.commercial;

Building buildingFor(BType b) =>
    (_s.building != null && _s.loadedBtype == b) ? _s.building! : _emptyBuilding;

List<Unit> get kApartments => _resLoaded ? _s.units! : const [];
List<Unit> get kShops => _comLoaded ? _s.units! : const [];
List<Payment> get kPayments => _s.payments ?? const [];
List<PayType> get kPayTypes => _s.payTypes ?? const [];
List<Expense> get kExpenses => _s.expenses ?? const [];
List<Worker> get kWorkers => _s.workers ?? const [];
List<ParkingSpot> get kParking => _s.parking ?? const [];
Guard get kGuard => _s.guard ?? _emptyGuard;
List<Craftsman> get kCraftsmen => _s.craftsmen ?? const [];
List<AlertItem> get kAlerts => _s.alerts ?? const [];
List<WaTemplate> get kWaTemplates => _s.waTemplates ?? const [];
List<MonthRow> get kMonthsGrid => _s.year?.months ?? const [];
int get kOpeningBalance => _s.year?.openingBalance ?? 0;

/// Backwards-compatible map used by older call sites.
Map<BType, Building> get kBuildings =>
    {for (final b in BType.values) b: buildingFor(b)};

/// Building summary (dashboard / reports), live or zero.
class Summary {
  Summary._();
  static SummaryData get _d => _s.summary ?? _zeroSummary;
  static int get balance => _d.balance;
  static int get due => _d.due;
  static int get revenueM => _d.revenueM;
  static int get expenseM => _d.expenseM;
  static List<ChartDatum> get bars => _d.bars;
  static List<ChartDatum> get trend => _d.trend;
}

/// Editable brand (#10) — live from API settings, or bundled defaults.
class Brand {
  Brand._();
  static String _v(String k, String fallback) {
    final v = _s.settings?[k];
    return (v == null || v.isEmpty) ? fallback : v;
  }

  static String get appName => _v('app_name', 'عمارتي');
  static String get slogan => _v('slogan', 'إدارة عماراتك بثقة وراحة');
  static String get description => _v('description',
      'برنامج متكامل لإدارة شؤون العمارات السكنية والمجمعات التجارية — المستحقات، المصروفات، التقارير والتنبيهات في مكان واحد.');
  static String get tagline => _v('tagline', 'عمارتي … تنظيم اليوم، راحة تدوم');
  static String get logoUrl => _v('logo_url', '');
}

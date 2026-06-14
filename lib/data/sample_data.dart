// عمارتي — models, helpers, seed data, and the runtime DataStore.
//
// Every public accessor (kApartments, kPayments, Summary.*, …) returns LIVE
// data from [DataStore] once a session has loaded it from the Laravel API, and
// falls back to the bundled seed data otherwise. This lets every screen read
// data synchronously, exactly as in the original prototype, while being backed
// by the real backend.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Supported currencies (code → symbol). The active building's currency drives
/// how money is displayed app-wide.
const Map<String, String> kCurrencySymbols = {
  'USD': '\$', 'SAR': 'ر.س', 'AED': 'د.إ', 'EGP': 'ج.م', 'JOD': 'د.أ',
  'KWD': 'د.ك', 'QAR': 'ر.ق', 'BHD': 'د.ب', 'OMR': 'ر.ع', 'TRY': '₺',
  'EUR': '€', 'GBP': '£', 'JD': 'د.أ',
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
  });
  final String name;
  final String address;
  final int units;
  final String type;
  final int subscription;
  final String currency;
  final int floors;

  factory Building.fromJson(Map<String, dynamic> j) => Building(
        name: j['name'] ?? '',
        address: j['address'] ?? '',
        units: _int(j['units_count']),
        type: j['type'] ?? '',
        subscription: _int(j['subscription']),
        currency: j['currency'] ?? 'USD',
        floors: _int(j['floors']),
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

// ───────────────────────────── Seed data ─────────────────────────────

const Map<BType, Building> _seedBuildings = {
  BType.residential: Building(
    name: 'عمارة الياسمين', address: 'حي النرجس، شارع 12، الرياض',
    units: 12, type: 'سكني', subscription: 40, currency: 'USD', floors: 6,
  ),
  BType.commercial: Building(
    name: 'مجمع التجارة الذهبي', address: 'طريق الملك فهد، الرياض',
    units: 10, type: 'تجاري', subscription: 120, currency: 'USD', floors: 3,
  ),
};

const List<Unit> _seedApartments = [
  Unit(id: 'A1', no: '101', floor: 1, resident: 'أحمد العامري', kind: 'مالك', phone: '+966 50 123 4567', sub: 40, status: 'ok', balance: 0, payer: 'الساكن'),
  Unit(id: 'A2', no: '102', floor: 1, resident: 'سارة المطيري', kind: 'مستأجر', phone: '+966 55 987 6543', sub: 40, status: 'late', balance: -80, payer: 'المالك'),
  Unit(id: 'A3', no: '201', floor: 2, resident: 'خالد الزهراني', kind: 'مالك', phone: '+966 54 222 1188', sub: 40, status: 'ok', balance: 0, payer: 'الساكن'),
  Unit(id: 'A4', no: '202', floor: 2, resident: 'نورة القحطاني', kind: 'مستأجر', phone: '+966 56 778 9900', sub: 40, status: 'credit', balance: 40, payer: 'الساكن'),
  Unit(id: 'A5', no: '301', floor: 3, resident: 'فهد الدوسري', kind: 'مالك', phone: '+966 50 445 6677', sub: 40, status: 'late', balance: -40, payer: 'الساكن'),
  Unit(id: 'A6', no: '302', floor: 3, resident: 'ليان السبيعي', kind: 'مستأجر', phone: '+966 53 119 2233', sub: 40, status: 'ok', balance: 0, payer: 'المالك'),
  Unit(id: 'A7', no: '401', floor: 4, resident: 'شقة شاغرة', kind: 'شاغر', phone: '—', sub: 40, status: 'vacant', balance: 0, payer: '—'),
  Unit(id: 'A8', no: '402', floor: 4, resident: 'ماجد الحربي', kind: 'مالك', phone: '+966 59 332 4455', sub: 40, status: 'ok', balance: 0, payer: 'الساكن'),
];

const List<Unit> _seedShops = [
  Unit(id: 'S1', no: 'M-01', floor: 1, resident: 'صيدلية الشفاء', kind: 'مستأجر', phone: '+966 50 200 3040', sub: 120, status: 'ok', balance: 0, payer: 'المستأجر'),
  Unit(id: 'S2', no: 'M-02', floor: 1, resident: 'مقهى لافندر', kind: 'مستأجر', phone: '+966 55 600 1020', sub: 120, status: 'late', balance: -240, payer: 'المستأجر'),
  Unit(id: 'S3', no: 'M-03', floor: 1, resident: 'بقالة المدينة', kind: 'مالك', phone: '+966 54 700 8090', sub: 120, status: 'ok', balance: 0, payer: 'المالك'),
  Unit(id: 'S4', no: 'M-04', floor: 2, resident: 'مكتب محاماة العدل', kind: 'مستأجر', phone: '+966 56 808 1122', sub: 120, status: 'credit', balance: 120, payer: 'المستأجر'),
  Unit(id: 'S5', no: 'M-05', floor: 2, resident: 'صالون الأناقة', kind: 'مستأجر', phone: '+966 53 909 3344', sub: 120, status: 'ok', balance: 0, payer: 'المستأجر'),
  Unit(id: 'S6', no: 'M-06', floor: 3, resident: 'محل شاغر', kind: 'شاغر', phone: '—', sub: 120, status: 'vacant', balance: 0, payer: '—'),
];

const List<Payment> _seedPayments = [
  Payment(id: 1, unit: '102', name: 'سارة المطيري', amount: 40, kind: 'الاشتراك الشهري', month: 4, year: 2026, date: '2026-05-03', method: 'تحويل بنكي'),
  Payment(id: 2, unit: '201', name: 'خالد الزهراني', amount: 55, kind: 'اشتراك + مصعد', month: 4, year: 2026, date: '2026-05-02', method: 'نقداً'),
  Payment(id: 3, unit: '101', name: 'أحمد العامري', amount: 40, kind: 'الاشتراك الشهري', month: 4, year: 2026, date: '2026-05-01', method: 'محفظة رقمية'),
  Payment(id: 4, unit: '302', name: 'ليان السبيعي', amount: 40, kind: 'الاشتراك الشهري', month: 3, year: 2026, date: '2026-04-28', method: 'تحويل بنكي'),
  Payment(id: 5, unit: '402', name: 'ماجد الحربي', amount: 70, kind: 'اشتراك + باركينج', month: 3, year: 2026, date: '2026-04-26', method: 'نقداً'),
  Payment(id: 6, unit: '202', name: 'نورة القحطاني', amount: 80, kind: 'اشتراك (شهرين)', month: 3, year: 2026, date: '2026-04-20', method: 'تحويل بنكي'),
];

const List<PayType> _seedPayTypes = [
  PayType(id: 'sub', label: 'الاشتراك الشهري', amount: 40, on: true, opt: false),
  PayType(id: 'elev', label: 'رسوم المصعد', amount: 15, on: true, opt: false),
  PayType(id: 'guard', label: 'أجرة الحارس', amount: 10, on: true, opt: true),
  PayType(id: 'park', label: 'أجرة الباركينج', amount: 20, on: false, opt: true),
];

const List<Expense> _seedExpenses = [
  Expense(id: 1, cat: 'مصعد', icon: 'elevator', tone: 'navy', supplier: 'شركة أوتيس للمصاعد', amount: 350, date: '2026-05-04', desc: 'عقد صيانة دورية'),
  Expense(id: 2, cat: 'نظافة', icon: 'broom', tone: 'ok', supplier: 'مؤسسة النظافة المثالية', amount: 200, date: '2026-05-01', desc: 'أجور شهر مايو'),
  Expense(id: 3, cat: 'كهرباء', icon: 'alert', tone: 'warn', supplier: 'شركة الكهرباء', amount: 180, date: '2026-04-29', desc: 'فاتورة الأجزاء المشتركة'),
  Expense(id: 4, cat: 'صيانة', icon: 'wrench', tone: 'credit', supplier: 'سباك - عبدالله', amount: 90, date: '2026-04-22', desc: 'إصلاح تسرب الطابق 3'),
  Expense(id: 5, cat: 'أخرى', icon: 'receipt', tone: 'gold', supplier: 'متجر مواد', amount: 60, date: '2026-04-18', desc: 'لمبات وأدوات'),
];

const List<String> kExpCats = ['مصعد', 'نظافة', 'كهرباء', 'صيانة', 'أخرى'];

const List<Worker> _seedWorkers = [
  Worker(id: 1, name: 'مؤسسة النظافة المثالية', type: 'شركة نظافة', phone: '+966 50 111 2233', address: 'حي العليا', cycle: 'شهري', amount: 200, last: '2026-05-01', next: '2026-06-01'),
  Worker(id: 2, name: 'سعيد - عامل نظافة', type: 'عامل', phone: '+966 56 444 5566', address: 'حي النخيل', cycle: 'أسبوعي', amount: 50, last: '2026-05-02', next: '2026-05-09'),
];

const List<ParkingSpot> _seedParking = [
  ParkingSpot(id: 'P1', no: 'P-01', status: 'مشغول', unit: '101', code: '4471', note: 'سيارة بيضاء'),
  ParkingSpot(id: 'P2', no: 'P-02', status: 'مشغول', unit: '201', code: '2290', note: ''),
  ParkingSpot(id: 'P3', no: 'P-03', status: 'شاغر', unit: '', code: '—', note: 'متاح للإيجار'),
  ParkingSpot(id: 'P4', no: 'P-04', status: 'مشغول', unit: '402', code: '8813', note: 'سيارة عائلية'),
  ParkingSpot(id: 'P5', no: 'P-05', status: 'صيانة', unit: '', code: '—', note: 'إصلاح أرضية'),
  ParkingSpot(id: 'P6', no: 'P-06', status: 'شاغر', unit: '', code: '—', note: ''),
];

const Guard _seedGuard = Guard(
  name: 'محمد عبدالرحمن', phone: '+966 50 777 8899',
  address: 'سكن الحارس - الدور الأرضي', fee: 10, last: '2026-05-01', next: '2026-06-01',
);

const List<Craftsman> _seedCraftsmen = [
  Craftsman(id: 1, name: 'عبدالله السباك', job: 'سباكة', phone: '+966 50 321 0011', note: 'متوفر 24 ساعة'),
  Craftsman(id: 2, name: 'يوسف الكهربائي', job: 'كهرباء', phone: '+966 55 432 0022', note: 'خبرة 10 سنوات'),
  Craftsman(id: 3, name: 'ورشة النجار', job: 'نجارة', phone: '+966 54 543 0033', note: 'أبواب وأثاث'),
  Craftsman(id: 4, name: 'فني التكييف', job: 'تكييف', phone: '+966 56 654 0044', note: 'صيانة وتعبئة فريون'),
  Craftsman(id: 5, name: 'صباغ المحترف', job: 'دهان', phone: '+966 53 765 0055', note: ''),
];

const List<AlertItem> _seedAlerts = [
  AlertItem(id: 1, type: 'subscription', icon: 'wallet', tone: 'late', title: 'اشتراك متأخر — شقة 102', body: 'سارة المطيري متأخرة عن دفع شهرين (\$80).', time: 'قبل ساعة', channel: 'whatsapp'),
  AlertItem(id: 2, type: 'contract', icon: 'elevator', tone: 'warn', title: 'عقد صيانة المصعد', body: 'ينتهي عقد الصيانة بعد 8 أيام. جدّد العقد.', time: 'اليوم', channel: 'internal'),
  AlertItem(id: 3, type: 'cleaning', icon: 'broom', tone: 'navy', title: 'استحقاق أجور النظافة', body: 'دفعة شركة النظافة مستحقة في 1 يونيو.', time: 'أمس', channel: 'internal'),
  AlertItem(id: 4, type: 'insurance', icon: 'shield', tone: 'warn', title: 'تأمين المبنى', body: 'وثيقة التأمين تنتهي خلال 21 يوم.', time: 'قبل 3 أيام', channel: 'internal'),
  AlertItem(id: 5, type: 'paid', icon: 'checkCircle', tone: 'ok', title: 'تم استلام دفعة', body: 'أحمد العامري — شقة 101 سدّد \$40.', time: 'قبل 4 أيام', channel: 'internal'),
];

const List<WaTemplate> _seedWaTemplates = [
  WaTemplate(id: 1, label: 'تذكير اشتراك', text: 'السلام عليكم، نذكّركم بسداد اشتراك الصيانة الشهري (\$40) لشهر مايو. شكراً لتعاونكم 🌿'),
  WaTemplate(id: 2, label: 'إشعار تأخر', text: 'تنبيه: لديكم مبلغ متأخر بقيمة \$80. يرجى السداد لتفعيل خدمات المبنى.'),
  WaTemplate(id: 3, label: 'استلام دفعة', text: 'تم استلام دفعتكم بنجاح. شكراً لكم — لجنة المبنى.'),
];

const List<MonthRow> _seedMonthsGrid = [
  MonthRow(m: 0, paid: 8, total: 8),
  MonthRow(m: 1, paid: 8, total: 8),
  MonthRow(m: 2, paid: 7, total: 8),
  MonthRow(m: 3, paid: 6, total: 8),
  MonthRow(m: 4, paid: 5, total: 8),
  MonthRow(m: 5, paid: 0, total: 8),
];

const SummaryData _seedSummary = SummaryData(
  balance: 25840,
  due: 12650,
  revenueM: 3200,
  expenseM: 1860,
  bars: [
    ChartDatum(label: 'إيرادات', value: 3200, color: AppColors.navy600),
    ChartDatum(label: 'مستحقات', value: 2400, color: AppColors.gold500),
    ChartDatum(label: 'مصروفات', value: 1860, color: AppColors.late),
    ChartDatum(label: 'صيانة', value: 880, color: AppColors.ok),
  ],
  trend: [
    ChartDatum(label: 'ينا', value: 2800, color: AppColors.navy600),
    ChartDatum(label: 'فبر', value: 3100, color: AppColors.navy600),
    ChartDatum(label: 'مار', value: 2950, color: AppColors.navy600),
    ChartDatum(label: 'أبر', value: 3300, color: AppColors.navy600),
    ChartDatum(label: 'ماي', value: 3200, color: AppColors.navy600),
  ],
);

// ─────────────────────── Public accessors (live ↦ seed) ───────────────────────

final DataStore _s = DataStore.I;
bool get _resLoaded => _s.loaded && _s.loadedBtype == BType.residential;
bool get _comLoaded => _s.loaded && _s.loadedBtype == BType.commercial;

Building buildingFor(BType b) =>
    (_s.building != null && _s.loadedBtype == b) ? _s.building! : _seedBuildings[b]!;

List<Unit> get kApartments => _resLoaded ? _s.units! : _seedApartments;
List<Unit> get kShops => _comLoaded ? _s.units! : _seedShops;
List<Payment> get kPayments => _s.payments ?? _seedPayments;
List<PayType> get kPayTypes => _s.payTypes ?? _seedPayTypes;
List<Expense> get kExpenses => _s.expenses ?? _seedExpenses;
List<Worker> get kWorkers => _s.workers ?? _seedWorkers;
List<ParkingSpot> get kParking => _s.parking ?? _seedParking;
Guard get kGuard => _s.guard ?? _seedGuard;
List<Craftsman> get kCraftsmen => _s.craftsmen ?? _seedCraftsmen;
List<AlertItem> get kAlerts => _s.alerts ?? _seedAlerts;
List<WaTemplate> get kWaTemplates => _s.waTemplates ?? _seedWaTemplates;
List<MonthRow> get kMonthsGrid => _s.year?.months ?? _seedMonthsGrid;
int get kOpeningBalance => _s.year?.openingBalance ?? 8200;

/// Backwards-compatible map used by older call sites.
Map<BType, Building> get kBuildings =>
    {for (final b in BType.values) b: buildingFor(b)};

/// Building summary (dashboard / guest / reports), live or seed.
class Summary {
  Summary._();
  static SummaryData get _d => _s.summary ?? _seedSummary;
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

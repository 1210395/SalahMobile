// عمارتي — models, helpers, and the runtime DataStore.
//
// Every public accessor (kApartments, kPayments, Summary.*, …) returns LIVE
// data from [DataStore] once a session has loaded it from the Laravel API, and
// an EMPTY value otherwise. No bundled sample data — real users start empty.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Supported currencies (code → symbol). The active building's currency drives
/// how money is displayed app-wide.
// Symbols for every code we might store/display (incl. aliases like ILS≡NIS,
// JD≡JOD) so old data always renders.
const Map<String, String> kCurrencySymbols = {
  'NIS': '₪', 'JOD': 'د.أ', 'USD': '\$', 'SAR': 'ر.س', 'AED': 'د.إ',
  'EGP': 'ج.م', 'KWD': 'د.ك', 'QAR': 'ر.ق', 'BHD': 'د.ب', 'OMR': 'ر.ع',
  'TRY': '₺', 'EUR': '€', 'GBP': '£', 'JD': 'د.أ', 'ILS': '₪',
};
// The picker list — ONE canonical code per currency (no NIS/ILS or JOD/JD
// duplicates, which would confuse users and make the same currency compare as
// "different" in the conversion path).
const List<String> kCurrencyCodes = [
  'NIS', 'JOD', 'USD', 'SAR', 'AED', 'EGP', 'KWD', 'QAR', 'BHD', 'OMR', 'TRY', 'EUR', 'GBP',
];

/// #6 — the app's market is Palestine, so a new building starts in shekels.
/// It stays a free choice: every currency picker still lists all of the above.
const String kDefaultCurrency = 'NIS';

String currencySymbol(String code) => kCurrencySymbols[code] ?? code;

/// The active building's base currency (from live data, else the default).
String get activeCurrency => DataStore.I.building?.currency ?? kDefaultCurrency;

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

/// Numbered month label (per the spec: months show as "شهر 1 … شهر 12", not
/// Arabic month names). [i] is the 0-based month index used across the data
/// layer (Payment.month, report selectors, …).
String monthLabelNum(int i) => 'شهر ${i + 1}';

/// A COUNT of months in correct Arabic. Arabic doesn't pluralise like English:
/// 1 → شهر، 2 → شهرين، 3-10 → N أشهر، 11+ → N شهراً. Writing "2 أشهر" or
/// "11 أشهر" reads as broken Arabic to a native speaker.
String monthsCountLabel(int n) {
  if (n == 1) return 'شهر واحد';
  if (n == 2) return 'شهرين';
  if (n >= 3 && n <= 10) return '$n أشهر';
  return '$n شهراً';
}

// ───────────── Derived ledger helpers (month settlement) ─────────────

/// Subscription amount already paid for a unit's given month/year. Only a
/// اشتراك شهري line settles a month — an "أخرى" line is income (#28) and a ذمم
/// line pays down old debt, not this month.
int paidForMonth(String unitNo, int month, int year) => kPayments
    .where((p) => p.unit == unitNo && p.month == month && p.year == year && p.isSub)
    .fold<int>(0, (s, p) => s + p.amount);

/// A month is SETTLED once its dues-settling payments cover the monthly fee.
/// A settled month can't be paid again (#34).
bool monthSettled(Unit u, int month, int year) =>
    u.sub > 0 && paidForMonth(u.no, month, year) >= u.sub;

/// Outstanding ذمم سابقة for a unit (the ذمم pot only — paying a subscription
/// never reduces this).
int duesOf(Unit u) => u.duesOwed;

/// Outstanding اشتراكات شهرية for a unit (the subscription pot only).
int subOwedOf(Unit u) => u.subOwed;

/// Everything a unit owes across both pots.
int owedOf(Unit u) => u.owed;

/// All month labels as numbered "شهر N" strings (0-based index → label).
List<String> get arMonthsNum =>
    [for (var i = 0; i < 12; i++) monthLabelNum(i)];

/// The unit a per-unit report is FOR, given what the picker last chose.
///
/// Returns null when the choice no longer matches anything — a renamed unit, a
/// switch between سكني and تجاري, a unit marked vacant. The screen and the
/// export both used `orElse: () => units.first` instead, so a report asked for
/// one resident silently came out in another resident's name, carrying their
/// payments. A report that cannot name the right person must name nobody.
Unit? resolveReportUnit(List<Unit> units, String? wanted) {
  if (units.isEmpty) return null;
  if (wanted == null) return units.first; // nothing picked yet; the picker shows which
  for (final u in units) {
    if (u.no == wanted) return u;
  }
  return null;
}

/// Right-hand square label for a unit row: "طابق 1 شقة 1" (residential) /
/// "طابق 1 وحدة 1" (commercial), derived from the unit's own floor + number.
String floorUnitLabel(Unit u, bool residential) =>
    'طابق ${u.floor} ${residential ? 'شقة' : 'وحدة'} ${u.no}';

/// Years available for selectors: every year present in live payments, unioned
/// with a sensible default window ending at the current year. Always sorted.
List<int> get kYears {
  final now = DateTime.now().year;
  final ys = <int>{now, now - 1, now - 2};
  for (final p in kPayments) {
    if (p.year > 1900) ys.add(p.year);
  }
  final list = ys.toList()..sort();
  return list;
}

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
    this.id = 0,
    required this.name,
    required this.address,
    required this.units,
    required this.type,
    required this.subscription,
    required this.currency,
    required this.floors,
    this.exchangeRate = 1,
    this.elevatorFee = 0,
    this.elevatorPhone = '',
    this.elevatorCompany = '',
    this.elevatorContractStart = '',
    this.elevatorContractEnd = '',
    this.elevatorLastCheck = '',
    this.elevatorCheckNotify = false,
    this.elevatorCheckInterval = 6,
  });

  /// Server id. A building type ('سكني'/'تجاري') is NOT an identity — several
  /// buildings share one — so anything targeting a building (a join request)
  /// must carry this. 0 = the local sample/offline building.
  final int id;
  final String name;
  final String address;
  final int units;
  final String type;
  final int subscription;
  final String currency;
  final int floors;
  final double exchangeRate; // entered-currency → base
  final int elevatorFee;     // monthly elevator fee (base currency)
  // Elevator maintenance contract + periodic-inspection reminder.
  final String elevatorPhone;
  final String elevatorCompany;
  final String elevatorContractStart;
  final String elevatorContractEnd;
  final String elevatorLastCheck;     // تاريخ آخر فحص دوري للمصعد
  final bool elevatorCheckNotify;
  final int elevatorCheckInterval;    // months between periodic checks

  factory Building.fromJson(Map<String, dynamic> j) => Building(
        id: _int(j['id']),
        name: j['name'] ?? '',
        address: j['address'] ?? '',
        units: _int(j['units_count']),
        type: j['type'] ?? '',
        subscription: _int(j['subscription']),
        currency: j['currency'] ?? kDefaultCurrency,
        floors: _int(j['floors']),
        exchangeRate: (j['exchange_rate'] is num)
            ? (j['exchange_rate'] as num).toDouble()
            : double.tryParse('${j['exchange_rate'] ?? 1}') ?? 1,
        elevatorFee: _int(j['elevator_fee']),
        elevatorPhone: j['elevator_phone'] ?? '',
        elevatorCompany: j['elevator_company'] ?? '',
        elevatorContractStart: _dateStr(j['elevator_contract_start']),
        elevatorContractEnd: _dateStr(j['elevator_contract_end']),
        elevatorLastCheck: _dateStr(j['elevator_last_check']),
        elevatorCheckNotify: j['elevator_check_notify'] == true || j['elevator_check_notify'] == 1,
        elevatorCheckInterval: j['elevator_check_interval'] == null ? 6 : _int(j['elevator_check_interval']),
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
    this.duesBalance = 0,
    this.subBalance = 0,
    this.openingBalance = 0,
    this.subCharges = 0,
    this.contractStart = '',
    this.contractEnd = '',
    this.loginCode = '',
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
  /// The two pots, kept apart on purpose (a subscription credit must never
  /// cancel an open ذمة). [balance] is their total — for cash views only.
  final int balance;

  /// ذمم سابقة: the debt entered for this unit, less what was paid against it.
  /// Negative = still owed.
  final int duesBalance;

  /// اشتراكات شهرية: what has accrued since billing started, less what was paid.
  /// Negative = behind.
  final int subBalance;

  /// The ذمة as originally entered (negative = owed) — what the edit form shows.
  final int openingBalance;

  /// Total subscription accrued to date (monthly fee × months billed).
  final int subCharges;
  final String payer;
  final String contractStart; // ISO date, '' if none
  final String contractEnd;   // ISO date, '' = open-ended / مستمر
  final String loginCode;     // QR / code-login token issued to the resident
  final int dbId; // server primary key (0 for bundled seed units)

  /// True when the contract has no end date (ongoing / مستمر).
  bool get ongoing => contractEnd.trim().isEmpty;

  /// Outstanding ذمم (0 when settled or in credit).
  int get duesOwed => duesBalance < 0 ? -duesBalance : 0;

  /// Outstanding اشتراكات (0 when settled or in credit).
  int get subOwed => subBalance < 0 ? -subBalance : 0;

  /// Everything the resident owes across BOTH pots — never the netted balance,
  /// which a credit on one side would quietly shrink.
  int get owed => duesOwed + subOwed;

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
        // A server that predates the split sends neither field: treat the whole
        // balance as the subscription pot so nothing renders as a phantom ذمة.
        duesBalance: j.containsKey('dues_balance') ? _int(j['dues_balance']) : 0,
        subBalance: j.containsKey('sub_balance') ? _int(j['sub_balance']) : _int(j['balance']),
        openingBalance: _int(j['opening_balance']),
        subCharges: _int(j['sub_charges']),
        payer: j['payer'] ?? '—',
        contractStart: _dateStr(j['contract_start']),
        contractEnd: _dateStr(j['contract_end']),
        loginCode: '${j['login_code'] ?? ''}',
      );
}

/// Normalise a nullable API date ("2026-01-01T00:00:00" / null) to "2026-01-01".
String _dateStr(Object? v) {
  if (v == null) return '';
  final s = '$v';
  if (s.isEmpty || s == 'null') return '';
  return s.split('T').first;
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
    this.appliesToDues = true,
    this.bucket = 'sub',
    this.chequeDate = '',
    this.chequeNumber = '',
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

  /// False for an "أخرى" line: recorded as income but does NOT settle dues (#28).
  final bool appliesToDues;

  /// The pot this payment settles: 'sub' (اشتراك شهري) | 'dues' (ذمم سابقة) |
  /// 'none' (إيراد فقط). The two money pots are reported separately.
  final String bucket;

  bool get isDues => bucket == 'dues';
  bool get isSub => bucket == 'sub';
  final String chequeDate;   // future due-date when the method is شيك (#26)
  final String chequeNumber;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: _int(j['id']),
        // ايراد خاص rows carry no unit at all (unit_no is null) — keep it empty,
        // never the literal string "null".
        unit: '${j['unit_no'] ?? j['unit'] ?? ''}',
        name: j['name'] ?? '',
        amount: _int(j['amount']),
        kind: j['kind'] ?? '',
        month: _int(j['month']),
        year: _int(j['year']),
        date: '${j['date']}'.split('T').first,
        method: j['method'] ?? '',
        appliesToDues: j['applies_to_dues'] == null
            ? true
            : (j['applies_to_dues'] == true || j['applies_to_dues'] == 1),
        bucket: () {
          final b = '${j['bucket'] ?? ''}';
          if (b == 'sub' || b == 'dues' || b == 'none') return b;
          // Older row/server: read the pot off what it does say.
          if ('${j['kind'] ?? ''}'.trim() == 'ذمم') return 'dues';
          return (j['applies_to_dues'] == false || j['applies_to_dues'] == 0) ? 'none' : 'sub';
        }(),
        chequeDate: _dateStr(j['cheque_date']),
        chequeNumber: '${j['cheque_number'] ?? ''}',
      );
}

/// The three payment بنود (#23). Fees (elevator/guard/parking) are folded into
/// the monthly fee, so a resident's charge is a single monthly amount.
enum PayItem { monthly, dues, other }

String payItemLabel(PayItem i) => switch (i) {
      PayItem.monthly => 'دفعة شهرية',
      PayItem.dues => 'ذمم',
      PayItem.other => 'أخرى',
    };

class PayType {
  const PayType({required this.id, required this.label, required this.amount, required this.on, required this.opt, this.dbId = 0});
  final String id;
  final String label;
  final int amount;
  final bool on;
  final bool opt;
  final int dbId; // server primary key (for updates)

  factory PayType.fromJson(Map<String, dynamic> j) => PayType(
        id: '${j['key'] ?? j['id'] ?? ''}',
        dbId: _int(j['id']),
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
    this.currency = '',
    this.originalAmount = 0,
  });
  final int id;
  final String cat;
  final String icon;
  final String tone;
  final String supplier;
  final int amount;       // base (building-currency) amount
  final String date;
  final String desc;
  final String currency;      // currency the amount was entered in (may differ from base)
  final int originalAmount;   // amount as entered, before conversion to base

  /// True when the expense was entered in a currency other than the building's.
  bool get foreignCurrency =>
      currency.isNotEmpty && originalAmount > 0 && currency != activeCurrency;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: _int(j['id']),
        cat: j['cat'] ?? '',
        icon: j['icon'] ?? 'receipt',
        tone: j['tone'] ?? 'gold',
        supplier: j['supplier'] ?? '',
        amount: _int(j['amount']),
        date: '${j['date']}'.split('T').first,
        desc: j['description'] ?? j['desc'] ?? '',
        currency: j['currency'] ?? '',
        originalAmount: _int(j['original_amount']),
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
    this.came = false,
    this.lastVisit = '',
    this.payStatus = 'none',
    this.paidAmount = 0,
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
  final bool came;          // حضر في هذه الدورة؟
  final String lastVisit;   // تاريخ آخر حضور
  final String payStatus;   // full | partial | none
  final int paidAmount;     // المدفوع (إن كان جزئياً)

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
        came: j['came'] == true || j['came'] == 1,
        lastVisit: _dateStr(j['last_visit']),
        payStatus: j['pay_status'] ?? 'none',
        paidAmount: _int(j['paid_amount']),
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
    required this.dueYear,
    required this.duePrev,
    required this.carried,
    required this.yearRevenue,
    required this.yearExpense,
    required this.revenueM,
    required this.expenseM,
    required this.bars,
    required this.trend,
  });
  final int balance;

  /// Dues owed as of the end of the selected year …
  final int due;

  /// … split into what the selected year itself added (#9) …
  final int dueYear;

  /// … and what was carried in from earlier years (#10).
  final int duePrev;

  /// Cash carried into the selected year from earlier years (#10).
  final int carried;
  final int yearRevenue;
  final int yearExpense;
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
      dueYear: _int(j['dueYear']),
      duePrev: _int(j['duePrev']),
      carried: _int(j['carried']),
      yearRevenue: _int(j['yearRevenue']),
      yearExpense: _int(j['yearExpense']),
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
  // The 'sms' block from /settings, kept separately: it's structured
  // (bool + list), not a string like every branding key, and null until a
  // settings payload has actually been parsed (Brand supplies the default).
  bool? smsAvailable;
  List<String>? smsCoverage;

  /// Split a raw /settings response into the flat branding map (existing
  /// shape, every value stringified) and the sms block. Shared by
  /// loadSettings/updateSettings/uploadLogo so the three don't each hand-roll
  /// the same parse.
  void applySettingsJson(dynamic data) {
    final map = Map<String, dynamic>.from(data);
    final sms = map.remove('sms');
    settings = map.map((k, v) => MapEntry(k, '${v ?? ''}'));
    smsAvailable = sms is Map ? sms['available'] == true : null;
    smsCoverage = (sms is Map && sms['coverage'] is List)
        ? List<String>.from((sms['coverage'] as List).map((e) => '$e'))
        : null;
  }

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
    name: '', address: '', units: 0, type: '', subscription: 0, currency: kDefaultCurrency, floors: 0);
const Guard _emptyGuard =
    Guard(name: '', phone: '', address: '', fee: 0, last: '—', next: '—');
const SummaryData _zeroSummary = SummaryData(
    balance: 0,
    due: 0,
    dueYear: 0,
    duePrev: 0,
    carried: 0,
    yearRevenue: 0,
    yearExpense: 0,
    revenueM: 0,
    expenseM: 0,
    bars: [],
    trend: []);

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
  static int get dueYear => _d.dueYear;
  static int get duePrev => _d.duePrev;
  static int get carried => _d.carried;
  static int get yearRevenue => _d.yearRevenue;
  static int get yearExpense => _d.yearExpense;
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
  static String get slogan => _v('slogan', 'فخر الصناعة الوطنية');
  static String get description => _v('description',
      'برنامج متكامل لإدارة شؤون العمارات السكنية والمجمعات التجارية — المستحقات، المصروفات، التقارير والتنبيهات في مكان واحد.');
  static String get tagline => _v('tagline', 'عمارتي … تنظيم اليوم، راحة تدوم');
  static String get logoUrl => _v('logo_url', '');

  // Whether the configured SMS gateway can reach the phone at all, and which
  // prefixes it covers — a local operator gateway serves +970/+972 only, so
  // the app can say so BEFORE a login attempt rather than after a silent wait.
  static bool get smsAvailable => _s.smsAvailable ?? false;
  static List<String> get smsCoverage => _s.smsCoverage ?? const ['+970', '+972'];
}

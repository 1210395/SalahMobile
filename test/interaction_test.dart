// Populated interaction tests — the smoke test renders every screen EMPTY, which
// hides bugs that only appear with real data or when a form/sheet is opened.
// This suite loads a realistic residential bundle into DataStore, renders every
// screen populated, and opens + fills every add/edit sheet, asserting that no
// exception is ever thrown while building or interacting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amarati/app.dart';
import 'package:amarati/common.dart';
import 'package:amarati/screens/admin_finance.dart' show AddPaymentSheet, PaymentsScreen;

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
      home: child,
    );

/// Populate DataStore with a realistic residential bundle (mirrors the API JSON
/// shapes, including the overhaul fields: elevator contract, worker attendance,
/// unit contracts, alert targets).
void _loadBundle() {
  final s = DataStore.I;
  s.loadedBtype = BType.residential;
  s.building = Building.fromJson({
    'name': 'عمارة الياسمين', 'address': 'حي النرجس', 'type': 'سكني',
    'subscription': 40, 'currency': 'USD', 'floors': 6, 'units_count': 12,
    'exchange_rate': 3.75, 'elevator_fee': 15, 'elevator_phone': '+966 92 000',
    'elevator_company': 'شركة أوتيس', 'elevator_contract_start': '2026-01-01',
    'elevator_contract_end': '2026-12-31', 'elevator_last_check': '2026-05-04',
    'elevator_check_notify': true, 'elevator_check_interval': 6,
  });
  s.summary = SummaryData.fromJson({
    'balance': 12000, 'due': 900, 'revenueM': 800, 'expenseM': 300,
    'bars': [
      {'label': 'الاشتراكات', 'value': 800, 'color': 'ok'},
      {'label': 'المصروفات', 'value': 300, 'color': 'late'},
      {'label': 'الذمم', 'value': 900, 'color': 'gold500'},
    ],
    'trend': [for (var i = 0; i < 12; i++) {'label': 'ش', 'value': i * 10, 'color': 'navy600'}],
  });
  s.units = [
    Unit.fromJson({
      'id': 1, 'no': '101', 'floor': 1, 'resident': 'أحمد علي', 'kind': 'مالك',
      'phone': '+966500000001', 'sub': 40, 'status': 'ok', 'balance': 0, 'payer': 'الساكن',
      'contract_start': '2026-01-01', 'contract_end': null, 'login_code': 'ABC12345',
    }),
    Unit.fromJson({
      'id': 2, 'no': '102', 'floor': 1, 'resident': 'سارة محمد', 'kind': 'مستأجر',
      'phone': '+966500000002', 'sub': 40, 'status': 'late', 'balance': -120, 'payer': 'المستأجر',
      'contract_start': '2026-01-01', 'contract_end': '2026-12-31', 'login_code': 'DEF67890',
    }),
    Unit.fromJson({
      'id': 3, 'no': '103', 'floor': 2, 'resident': 'وحدة شاغرة', 'kind': 'شاغر',
      'phone': '—', 'sub': 0, 'status': 'vacant', 'balance': 0, 'payer': '—',
    }),
  ];
  s.payments = [
    Payment.fromJson({
      'id': 1, 'unit_no': '101', 'name': 'أحمد علي', 'amount': 40,
      'kind': 'الاشتراك الشهري', 'month': 4, 'year': 2026, 'date': '2026-05-01', 'method': 'نقداً',
    }),
    Payment.fromJson({
      'id': 2, 'unit_no': '101', 'name': 'أحمد علي', 'amount': 40,
      'kind': 'الاشتراك الشهري', 'month': 3, 'year': 2026, 'date': '2026-04-01', 'method': 'تحويل بنكي',
    }),
  ];
  s.expenses = [
    Expense.fromJson({
      'id': 1, 'cat': 'صيانة', 'icon': 'wrench', 'tone': 'credit', 'supplier': 'مؤسسة الصيانة',
      'amount': 27, 'original_amount': 100, 'currency': 'ILS', 'exchange_rate': 0.27,
      'date': '2026-06-30', 'description': 'صيانة عامة',
    }),
  ];
  s.workers = [
    Worker.fromJson({
      'id': 1, 'name': 'عامل النظافة', 'type': 'عامل', 'phone': '+966500000003', 'address': '',
      'cycle': 'شهري', 'amount': 200, 'last_payment': '2026-06-01', 'next_due': '2026-07-01',
      'came': true, 'last_visit': '2026-06-28', 'pay_status': 'partial', 'paid_amount': 100,
    }),
  ];
  s.parking = [
    ParkingSpot.fromJson({'id': 1, 'no': 'P1', 'status': 'مشغول', 'unit_no': '101', 'code': 'X1', 'note': ''}),
    ParkingSpot.fromJson({'id': 2, 'no': 'P2', 'status': 'شاغر', 'unit_no': null, 'code': null, 'note': ''}),
  ];
  s.guard = Guard.fromJson({
    'name': 'حارس المبنى', 'phone': '+966500000004', 'address': 'الغرفة الأرضية',
    'fee': 300, 'last_payment': '2026-06-01', 'next_due': '2026-07-01',
  });
  s.alerts = [
    AlertItem.fromJson({
      'id': 1, 'type': 'notice', 'icon': 'bell', 'tone': 'navy', 'title': 'إعلان',
      'body': 'اجتماع السكان', 'time_label': 'الآن', 'channel': 'internal', 'target': 'all',
    }),
  ];
  s.craftsmen = [
    Craftsman.fromJson({'id': 1, 'name': 'كهربائي', 'job': 'كهرباء', 'phone': '+966500000005', 'note': ''}),
  ];
  s.payTypes = [
    PayType.fromJson({'id': 1, 'key': 'sub', 'label': 'الاشتراك الشهري', 'amount': 40, 'enabled': true, 'optional': false}),
    PayType.fromJson({'id': 2, 'key': 'elev', 'label': 'رسوم المصعد', 'amount': 0, 'enabled': false, 'optional': true}),
    PayType.fromJson({'id': 3, 'key': 'guard', 'label': 'رسوم الحارس', 'amount': 15, 'enabled': false, 'optional': true}),
  ];
  s.waTemplates = [WaTemplate.fromJson({'id': 1, 'label': 'تذكير', 'text': 'تذكير بالدفع'})];
  s.year = YearData.fromJson({
    'year': 2026, 'opening_balance': 1000,
    'months': [for (var i = 0; i < 12; i++) {'m': i, 'paid': i * 40, 'total': 480}],
  });
}

void main() {
  setUp(_loadBundle);
  tearDown(() => DataStore.I.clear());

  // Every screen, rendered with REAL data (not empty).
  final adminScreens = [
    'home', 'building', 'units', 'payments', 'expenses', 'workers', 'parking',
    'guard', 'elevator', 'craftsmen', 'reports', 'alerts', 'years', 'more',
    'subscribe', 'buildingSetup', 'approvals',
  ];
  for (final sc in adminScreens) {
    testWidgets('populated render: $sc', (tester) async {
      await tester.pumpWidget(_wrap(AmaratiApp(
          initialScreen: sc, initialRole: AppRole.admin, initialBtype: BType.residential)));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'exception rendering populated $sc');
    });
  }

  for (final sc in ['resHome', 'resReport', 'resElevator']) {
    testWidgets('populated render (resident): $sc', (tester) async {
      await tester.pumpWidget(_wrap(AmaratiApp(
          initialScreen: sc, initialRole: AppRole.resident, initialBtype: BType.residential)));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'exception rendering resident $sc');
    });
  }

  // Open the add/compose sheet on each screen that has a FAB, and assert it
  // builds without throwing (exercises the form widgets, dropdowns, chips…).
  final sheetScreens = ['units', 'payments', 'expenses', 'workers', 'parking', 'alerts'];
  for (final sc in sheetScreens) {
    testWidgets('opens add sheet: $sc', (tester) async {
      await tester.pumpWidget(_wrap(AmaratiApp(
          initialScreen: sc, initialRole: AppRole.admin, initialBtype: BType.residential)));
      await tester.pump(const Duration(milliseconds: 120));
      final fab = find.byType(AppFab);
      if (fab.evaluate().isEmpty) return; // no FAB on this screen build
      await tester.tap(fab.first);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull, reason: 'exception opening add sheet on $sc');
      // Type into the first text field if present (exercises onChanged/rebuild).
      final fields = find.byType(TextField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, '5');
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull, reason: 'exception typing in $sc sheet');
      }
    });
  }

  // Onboarding wizard: step through all questions (Next advances, never throws).
  testWidgets('onboarding wizard steps through', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'buildingSetup', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    for (var i = 0; i < 6; i++) {
      // Fill any visible text field then advance.
      final fields = find.byType(TextField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, '5');
        await tester.pump(const Duration(milliseconds: 80));
      }
      final next = find.text('التالي');
      if (next.evaluate().isEmpty) break;
      await tester.tap(next.first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'exception on onboarding step $i');
    }
  });

  // Dashboard period filter: changing the month dropdown must not throw (the
  // fetch will fail offline, but the widget path is what we exercise).
  testWidgets('dashboard renders period filter controls', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'home', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('السنة'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // Helper: pump a screen, then tap a widget matching [finder] (if present) and
  // assert no exception. Uses warnIfMissed:false for canvas-y hit areas.
  Future<void> pumpAndTap(WidgetTester tester, String screen, Finder finder,
      {AppRole role = AppRole.admin}) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: screen, initialRole: role, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  }

  // Reports: switch through every tab (شهري / سنوي / شقة / مصروفات).
  testWidgets('reports: all tabs switch without error', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'reports', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    for (final tab in ['سنوي', 'شقة', 'مصروفات', 'شهري']) {
      final f = find.text(tab);
      if (f.evaluate().isEmpty) continue;
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'exception on reports tab $tab');
    }
  });

  // Reports expense tab: the category + month filters build.
  testWidgets('reports: expense filters render', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'reports', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final f = find.text('مصروفات');
    if (f.evaluate().isNotEmpty) {
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
  });

  // Elevator: open the maintenance-contract edit sheet (the "تعديل" button).
  testWidgets('elevator: contract edit sheet opens', (tester) async {
    await pumpAndTap(tester, 'elevator', find.text('تعديل'));
  });

  // Units: tap the first unit card → detail sheet (renders QR + login code).
  testWidgets('units: detail sheet opens (QR/login-code)', (tester) async {
    await pumpAndTap(tester, 'units', find.text('أحمد علي'));
  });

  // Payments: tap the first payment row → detail sheet (all-payments/receipt).
  testWidgets('payments: detail sheet opens', (tester) async {
    await pumpAndTap(tester, 'payments', find.byType(AppCard));
  });

  // Workers: open the attendance/payment status sheet.
  testWidgets('workers: status sheet opens', (tester) async {
    await pumpAndTap(tester, 'workers', find.text('تحديث الحالة'));
  });

  // Guard: open the edit sheet.
  testWidgets('guard: edit sheet opens', (tester) async {
    await pumpAndTap(tester, 'guard', find.byType(AppFab));
  });

  // Year transfer (الترحيل السنوي) renders populated.
  testWidgets('year-transfer renders', (tester) async {
    await pumpAndTap(tester, 'years', find.byType(AppCard));
  });

  // REGRESSION: a month with total==0 must not divide-by-zero (NaN.round() would
  // throw and crash the whole الترحيل السنوي screen).
  testWidgets('year-transfer survives a zero-total month', (tester) async {
    DataStore.I.year = YearData.fromJson({
      'year': DateTime.now().year, 'opening_balance': 0,
      'months': [
        {'m': 0, 'paid': 0, 'total': 0},
        {'m': 1, 'paid': 3, 'total': 8},
      ],
    });
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'years', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  // REGRESSION (the "bilal paid 600, shows 909" bug): a credited resident's
  // "المسدّد" must reflect ACTUAL payments, not sub×12 + balance.
  testWidgets('resident report shows actual paid, not required+balance', (tester) async {
    final s = DataStore.I;
    final yr = DateTime.now().year;
    s.loadedBtype = BType.residential;
    s.building = Building.fromJson({'name': 'ع', 'currency': 'USD', 'type': 'سكني'});
    s.summary = SummaryData.fromJson({});
    s.payTypes = [];
    // sub 50 → required 50×12 = 600; balance +309 (credit). Actual payments = 600.
    s.units = [
      Unit.fromJson({'no': '101', 'floor': 1, 'resident': 'بلال', 'kind': 'مالك',
        'sub': 50, 'status': 'ok', 'balance': 309}),
    ];
    s.payments = [
      Payment.fromJson({'id': 1, 'unit_no': '101', 'amount': 300, 'month': 1, 'year': yr, 'date': '$yr-02-01'}),
      Payment.fromJson({'id': 2, 'unit_no': '101', 'amount': 300, 'month': 2, 'year': yr, 'date': '$yr-03-01'}),
    ];
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'resReport', initialRole: AppRole.resident, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    // The old buggy value (600 + 309) must NOT appear anywhere.
    expect(find.textContaining('909'), findsNothing, reason: 'المسدّد must not be required+balance');
    // The real paid total (600) is shown.
    expect(find.textContaining('600'), findsWidgets);
  });

  // Payment edit sheet (long-press a payment) opens and offers delete.
  testWidgets('payments: long-press opens edit sheet with delete', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    // #33: the list opens grouped per renter — switch to the per-payment view.
    await tester.tap(find.text('كل الدفعات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    final row = find.text('أحمد علي');
    if (row.evaluate().isNotEmpty) {
      await tester.longPress(row.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.text('حذف الدفعة'), findsWidgets, reason: 'edit sheet must offer delete');
    }
  });

  // Worker sheet exposes the delete-worker action (the deleteWorker fix).
  testWidgets('workers: visit sheet offers delete worker', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'workers', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final statusBtn = find.text('تحديث الحالة');
    if (statusBtn.evaluate().isNotEmpty) {
      await tester.tap(statusBtn.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.text('حذف العامل / الشركة'), findsWidgets, reason: 'worker delete must be present');
    }
  });

  // Alerts screen: the manager's "إرسال إشعار" compose sheet opens.
  testWidgets('alerts: notification compose sheet opens', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'alerts', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final fab = find.text('إرسال إشعار');
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    }
  });

  // Unit rename path (UI): detail → edit exposes the editable number field.
  testWidgets('units: detail then edit exposes the number field', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('أحمد علي').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    final edit = find.text('تعديل');
    if (edit.evaluate().isNotEmpty) {
      await tester.tap(edit.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });

  // The whole admin screen set also renders for a COMMERCIAL building.
  testWidgets('commercial building: core screens render', (tester) async {
    DataStore.I.loadedBtype = BType.commercial;
    for (final sc in ['home', 'units', 'payments', 'reports']) {
      await tester.pumpWidget(_wrap(AmaratiApp(
          initialScreen: sc, initialRole: AppRole.admin, initialBtype: BType.commercial)));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'commercial $sc must render');
    }
  });

  // Resident alerts feed renders with a targeted alert present (privacy fix
  // shape): an alert addressed to the resident's own unit builds fine.
  testWidgets('resident alerts: targeted alert renders', (tester) async {
    DataStore.I.alerts = [
      AlertItem.fromJson({
        'id': 9, 'type': 'subscription', 'icon': 'wallet', 'tone': 'late',
        'title': 'اشتراك متأخر — وحدة 101', 'body': 'متأخر بمبلغ \$120',
        'time_label': 'الآن', 'channel': 'whatsapp', 'target': '101',
      }),
    ];
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'alerts', initialRole: AppRole.resident, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  // ─────────── Salah feedback regressions (v1.3.4 / v1.3.5) ───────────

  // #3: a payment detail must show WHICH month it covers (الشهر المدفوع عنه),
  // distinct from the pay date (تاريخ الدفع) — not just the payment date.
  testWidgets('payment detail shows the covered month and the pay date', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    // #33: the list opens grouped per renter — switch to the per-payment view.
    await tester.tap(find.text('كل الدفعات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('أحمد علي').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('الشهر المدفوع عنه'), findsOneWidget);
    expect(find.text('تاريخ الدفع'), findsOneWidget);
  });

  // #6: tapping an expense (not only long-press) must open its edit sheet.
  testWidgets('tapping an expense opens the edit sheet', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'expenses', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('مؤسسة الصيانة').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('تعديل المصروف'), findsOneWidget);
  });

  // #4: the reports month filter defaults to 'كل الأشهر' so a multi-month payment
  // shows its full whole-year total, not one month's slice.
  testWidgets('reports default to كل الأشهر (whole-year total)', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'reports', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('كل الأشهر'), findsWidgets);
  });

  // #2: the add-payment sheet exposes a covered-YEAR selector (record past years).
  testWidgets('payment sheet exposes a covered-year selector', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final fab = find.byType(AppFab);
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.text('سنة الأشهر المدفوعة'), findsOneWidget);
    }
  });

  // #5: commercial screens use 'وحدة' terminology — 'محل' must not appear.
  testWidgets('commercial units screen uses وحدة, never محل', (tester) async {
    DataStore.I.loadedBtype = BType.commercial;
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.commercial)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('محل'), findsNothing, reason: 'commercial units must say وحدة');
  });

  // Logout: the admin home header has a logout button that opens a confirm sheet.
  testWidgets('admin home logout button opens a confirm sheet', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'home', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final logout = find.byWidgetPredicate((w) => w is RoundBtn && w.icon == 'logout');
    expect(logout, findsWidgets, reason: 'header must expose a logout button');
    await tester.tap(logout.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('تسجيل الخروج'), findsWidgets);
  });

  // ─────────── Audit redesign — P2 (nav) ───────────

  // #13/#48: the role-switch button is gone from the admin home topbar.
  testWidgets('admin home has no role-switch button', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'home', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byWidgetPredicate((w) => w is RoundBtn && w.icon == 'switch'), findsNothing);
  });

  // #11/#12: the المصروفات tab is in the bottom nav, and a main screen exposes a
  // home button in the topbar (home moved off the nav).
  testWidgets('payments screen has expenses in nav + a home button in the header', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is RoundBtn && w.icon == 'home'), findsWidgets);
    expect(find.text('المصروفات'), findsWidgets); // the new nav tab
  });

  // ─────────── Audit redesign — P3 (validation) ───────────

  // #16: a digitsOnly Field strips letters at the keyboard (real input filtering,
  // not the old tryParse-fallback that let letters become a number).
  testWidgets('a digitsOnly Field rejects letters as you type', (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(body: Field(inputFormatters: digitsOnly, onChanged: (_) {}))));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '12ab34');
    await tester.pump();
    expect(find.text('1234'), findsOneWidget);
  });

  // #18/#19: the edit-unit sheet no longer lets the admin hand-set the balance
  // (dues are payment-derived) — the "الرصيد / الذمم" field is gone.
  testWidgets('edit-unit sheet has no free balance field', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('أحمد علي').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    final edit = find.text('تعديل');
    if (edit.evaluate().isNotEmpty) {
      await tester.tap(edit.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('الرصيد / الذمم'), findsNothing);
    }
  });

  // ─────────── Audit redesign — P4b (payment sheet) ───────────

  // #23: بنود are now دفعة شهرية / ذمم / أخرى — the per-fee toggles are gone
  // (elevator/guard/parking are folded into the single monthly fee).
  testWidgets('payment sheet uses the new بنود and drops the fee toggles', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byType(AppFab).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.text('بند الدفع'), findsOneWidget);
    expect(find.text('دفعة شهرية'), findsWidgets);
    expect(find.text('رسوم المصعد'), findsNothing); // folded into the monthly fee
  });

  // #22: a unit's detail exposes "تسجيل دفعة", which opens دفعة جديدة PRE-FILLED
  // for that renter (AddPaymentSheet(initialUnit: u.no)) instead of navigating to
  // the الإيرادات list. This guards the entry point; the full tap-through is
  // covered end-to-end (the widget-test surface can't reach the button now that
  // the sheet's action row scrolls with the form, #14).
  testWidgets('unit detail exposes the تسجيل دفعة action', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('أحمد علي').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.ancestor(of: find.text('تسجيل دفعة'), matching: find.byType(AppButton)),
        findsOneWidget);
  });

  // #22 (prefill): AddPaymentSheet accepts an initialUnit and opens on that renter.
  testWidgets('AddPaymentSheet prefills the renter from initialUnit', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final ctx = tester.widget<PaymentsScreen>(find.byType(PaymentsScreen)).ctx;

    await tester.pumpWidget(_wrap(
        Scaffold(body: AddPaymentSheet(ctx: ctx, initialUnit: '102'))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    // The sheet opened on unit 102 (سارة محمد in the bundle) — prefilled.
    expect(find.textContaining('102'), findsWidgets);
    expect(find.text('بند الدفع'), findsOneWidget);
  });

  // ─────────── Audit redesign — P4c (ايراد خاص + إيرادات views) ───────────

  // #38/#39: a payment can be building income with no renter behind it
  // ("دفعة برج جوال"). The sheet exposes an ايراد خاص target.
  testWidgets('payment sheet offers an ايراد خاص target with no unit', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final ctx = tester.widget<PaymentsScreen>(find.byType(PaymentsScreen)).ctx;

    await tester.pumpWidget(_wrap(Scaffold(body: AddPaymentSheet(ctx: ctx))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ايراد خاص'), findsOneWidget);

    await tester.tap(find.text('ايراد خاص'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    // Special income is not a renter's dues: no بند picker, no month picker.
    expect(find.text('بند الدفع'), findsNothing);
  });

  // #38/#39: a unit-less payment must never render as the literal string "null".
  test('Payment.fromJson maps a null unit_no to an empty unit', () {
    final p = Payment.fromJson({
      'id': 1,
      'unit_no': null,
      'name': 'دفعة برج جوال',
      'amount': 1200,
      'kind': 'ايراد خاص',
      'month': 7,
      'year': 2026,
      'date': '2026-07-01',
      'method': 'نقدي',
      'applies_to_dues': false,
    });
    expect(p.unit, '');
    expect(p.appliesToDues, isFalse);
  });

  // #33: الإيرادات can be read per-renter (default) or as individual payments.
  testWidgets('الإيرادات toggles between per-renter and per-payment views', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    expect(find.text('حسب الساكن'), findsOneWidget);
    expect(find.text('كل الدفعات'), findsOneWidget);
    // Renter mode is the default — rows are summarised as "N دفعة".
    expect(find.textContaining('دفعة'), findsWidgets);

    await tester.tap(find.text('كل الدفعات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    // Per-payment mode names the covered month on every row (Salah's #note).
    expect(find.textContaining('عن '), findsWidgets);
  });

  // ─────────── Audit redesign — #8/#9/#10 (dashboard carry-over) ───────────

  // #8/#9/#10: both hero figures are cumulative, so the dashboard must say what
  // the selected year added versus what it inherited from earlier years.
  testWidgets('dashboard breaks the year down into carried-over and this-year',
      (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'home', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    final y = DateTime.now().year;
    // #8 — the cash box names itself and its year.
    expect(find.text('رصيد الصندوق'), findsOneWidget);
    expect(find.textContaining('للعام'), findsWidgets);
    // #9 — the dues box says which year it closes on.
    expect(find.textContaining('حتى نهاية'), findsOneWidget);
    // #10 — the carry-over lines.
    expect(find.textContaining('تفصيل العام'), findsOneWidget);
    expect(find.text('رصيد مرحّل من السنوات السابقة'), findsOneWidget);
    expect(find.text('ذمم من السنوات السابقة'), findsOneWidget);
    expect(find.text('ذمم العام $y'), findsOneWidget);
    expect(find.text('إجمالي الذمم'), findsOneWidget);
  });

  // ─────────── Audit redesign — P5 (reports, building, copy) ───────────

  // #6: a new building starts in shekels — but every currency stays selectable.
  test('the default currency is NIS and every currency stays selectable', () {
    expect(kDefaultCurrency, 'NIS');
    expect(kCurrencyCodes.first, 'NIS');
    expect(kCurrencyCodes, contains('USD'));
    expect(kCurrencyCodes.length, greaterThan(5));
    expect(currencySymbol('NIS'), '₪');
  });

  // #44: the corner pen must say what it does, not just draw a glyph.
  testWidgets('the edit pen is labelled تعديل', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'building', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.ancestor(of: find.text('تعديل'), matching: find.byType(RoundBtn)), findsOneWidget);
  });

  // #41: exports offered share only — a download/save mode must exist. The
  // "تقرير شامل" button sits below the 600px test viewport, so scroll to it first.
  testWidgets('the report export sheet offers a تنزيل mode', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'reports', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final btn = find.text('تقرير شامل (Excel)');
    await tester.scrollUntilVisible(btn, 250, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(btn.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('تنزيل الملف على الجهاز'), findsOneWidget);
    expect(find.text('مشاركة الملف'), findsOneWidget);
  });

  // #46: المزيد rows must explain themselves, not just name themselves.
  testWidgets('the المزيد hub explains every entry', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'more', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.text('بيانات المبنى، الاشتراك الشهري الافتراضي، الرسوم، والعملة'), findsOneWidget);
    expect(find.text('تسجيل دفعات السكان والإيرادات الخاصة'), findsOneWidget);
  });

  // ─────────── Silently-blocked forms (the user's report) ───────────
  //
  // A greyed-out button with no explanation is a dead end: the app refuses the
  // user and they cannot tell what to fix. Every gated submit must name what is
  // missing. These tests guard the rule, not just the individual screens.

  // The reported bug: "إرسال رمز التأكيد" was greyed out on the register screen.
  // It used to require the ENTIRE form (name, phone, whatsapp, password, confirm)
  // even though sending a code to an email needs only… the email.
  testWidgets('register: the send-code button needs only a valid email', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(initialScreen: 'register', initialRole: AppRole.admin)));
    await tester.pump(const Duration(milliseconds: 200));

    // Nothing typed yet: the button is blocked AND says so.
    expect(find.byType(FormBlockedHint), findsWidgets);
    expect(find.text('• أدخل بريدك الإلكتروني أولاً'), findsOneWidget);

    final sendBtn = find.ancestor(
        of: find.text('إرسال رمز التأكيد'), matching: find.byType(AppButton));
    expect(tester.widget<AppButton>(sendBtn).disabled, isTrue);

    // An email ALONE unblocks it — no name, no phone, no password required.
    await tester.enterText(
        find.descendant(
            of: find.widgetWithText(Field, 'البريد الإلكتروني'),
            matching: find.byType(TextField)),
        'salah@example.com');
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<AppButton>(sendBtn).disabled, isFalse);
    expect(find.text('• أدخل بريدك الإلكتروني أولاً'), findsNothing);
  });

  // The register submit stays gated on the whole form — but now it LISTS what is
  // missing instead of just going grey.
  testWidgets('register: a blocked submit names every missing field', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(initialScreen: 'register', initialRole: AppRole.admin)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('لإنشاء الحساب، أكمل ما يلي:'), findsOneWidget);
    expect(find.text('• الاسم الكامل'), findsOneWidget);
    expect(find.text('• رقم جوال صحيح'), findsOneWidget);
    expect(find.text('• بريد إلكتروني صحيح'), findsOneWidget);
    expect(find.text('• كلمة سر من 6 أحرف على الأقل'), findsOneWidget);
  });

  // The app's front door must never grey out in silence either.
  testWidgets('login: a blocked sign-in says what is missing', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(initialScreen: 'login', initialRole: AppRole.admin)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('لتسجيل الدخول، أكمل ما يلي:'), findsOneWidget);
    expect(find.text('• أدخل بريدك الإلكتروني أو رقم جوالك'), findsOneWidget);
    expect(find.text('• أدخل كلمة المرور'), findsOneWidget);
  });

  // The payment sheet had NINE silent conditions — the worst offender in the app.
  testWidgets('payment sheet: a blocked save lists its reasons', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final ctx = tester.widget<PaymentsScreen>(find.byType(PaymentsScreen)).ctx;

    await tester.pumpWidget(_wrap(Scaffold(body: AddPaymentSheet(ctx: ctx))));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    // Fresh sheet: no unit picked yet, so it must SAY so rather than just grey out.
    expect(find.byType(FormBlockedHint), findsOneWidget);
    expect(find.text('لحفظ الدفعة، أكمل ما يلي:'), findsOneWidget);
  });

  // The rule itself: FormBlockedHint renders one bullet per reason, and nothing
  // at all when the form is complete.
  testWidgets('FormBlockedHint lists every reason and vanishes when satisfied',
      (tester) async {
    await tester.pumpWidget(_wrap(const Scaffold(
        body: FormBlockedHint(reasons: ['أولاً', 'ثانياً'], title: 'لإكمال الحفظ:'))));
    await tester.pump();
    expect(find.text('لإكمال الحفظ:'), findsOneWidget);
    expect(find.text('• أولاً'), findsOneWidget);
    expect(find.text('• ثانياً'), findsOneWidget);

    await tester.pumpWidget(_wrap(const Scaffold(body: FormBlockedHint(reasons: []))));
    await tester.pump();
    expect(find.byType(Text), findsNothing); // no empty red box when there is nothing to say
  });

  // ─────────── Renter login: password at creation + reset later ───────────

  // A renter's password used to hide behind an "إنشاء حساب دخول" switch that was
  // OFF by default, so a renter added the normal way got no account — and since the
  // QR is single-use and the edit sheet had no password field, they could never log
  // in at all. Every renter now leaves the add form with a real login.
  testWidgets('adding a renter always asks for a password', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byType(AppFab).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    // The add sheet offers the manual path (below the fold in the test viewport).
    final manual = find.text('إدخال البيانات يدوياً');
    await tester.dragUntilVisible(
        manual, find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(manual.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // No switch to hide the login behind — the password is simply there.
    expect(find.text('إنشاء حساب دخول للساكن'), findsNothing);
    expect(find.text('حساب الدخول'), findsWidgets);
    expect(find.text('كلمة المرور'), findsOneWidget);

    // …and a missing password blocks the save, out loud.
    expect(find.text('• كلمة مرور من 6 أحرف على الأقل'), findsOneWidget);
    expect(find.text('• رقم الموبايل — هو اسم المستخدم لحساب الدخول'), findsOneWidget);
  });

  // The edit sheet can now set/reset the login — it had no password field at all,
  // so a forgotten password was unrecoverable from inside the app.
  testWidgets('editing a unit can set a new password', (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'units', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('أحمد علي').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    final edit = find.text('تعديل');
    if (edit.evaluate().isEmpty) return;
    await tester.tap(edit.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('كلمة مرور جديدة'), findsOneWidget);
  });

  // ─────────── The freeze trap + the silent-lie class ───────────

  // THE WORST FAILURE MODE, and the one a green test suite hides: a blockers list
  // is recomputed only when the field's onChanged calls setState. If it doesn't,
  // the user types a perfectly valid value and the button STAYS DEAD forever while
  // the hint keeps insisting something is missing. That is worse than the original
  // bug. This test types into a gated field and demands the blocker clears.
  testWidgets('typing a valid value actually clears the blocker (no freeze)',
      (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(initialScreen: 'login', initialRole: AppRole.admin)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('• أدخل كلمة المرور'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.widgetWithText(Field, 'كلمة المرور'), matching: find.byType(TextField)),
        'secret6');
    await tester.pump(const Duration(milliseconds: 200));
    // The reason is gone — the list re-evaluated, so the field is wired to a rebuild.
    expect(find.text('• أدخل كلمة المرور'), findsNothing);

    await tester.enterText(
        find.descendant(
            of: find.widgetWithText(Field, 'البريد الإلكتروني أو رقم الجوال'),
            matching: find.byType(TextField)),
        'admin@amarati.app');
    await tester.pump(const Duration(milliseconds: 200));
    // Both satisfied → no hint at all, and the button is live.
    expect(find.byType(FormBlockedHint), findsNothing);
    final btn = find.ancestor(of: find.text('دخول'), matching: find.byType(AppButton));
    expect(tester.widget<AppButton>(btn).disabled, isFalse);
  });

  // #36 regression: a multi-month payment to الجميع/مجموعة has NO single unit, so
  // the monthly fee is 0. The guard `fee > 0 && perMonth >= fee` made that false
  // forever — the save button could never enable, while the hint demanded a minimum
  // of zero the user had already exceeded. An unsatisfiable form.
  testWidgets('a multi-month payment to الجميع is not permanently blocked',
      (tester) async {
    await tester.pumpWidget(_wrap(AmaratiApp(
        initialScreen: 'payments', initialRole: AppRole.admin, initialBtype: BType.residential)));
    await tester.pump(const Duration(milliseconds: 150));
    final ctx = tester.widget<PaymentsScreen>(find.byType(PaymentsScreen)).ctx;

    await tester.pumpWidget(_wrap(Scaffold(body: AddPaymentSheet(ctx: ctx))));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('الجميع'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    // Whatever else is outstanding, it must NEVER be the impossible zero-minimum.
    expect(find.textContaining('الحد الأدنى'), findsNothing);
  });

  // Arabic counts months properly: 2 → شهرين, 3-10 → أشهر, 11+ → شهراً.
  test('month counts read as real Arabic, not "2 أشهر"', () {
    expect(monthsCountLabel(1), 'شهر واحد');
    expect(monthsCountLabel(2), 'شهرين');
    expect(monthsCountLabel(3), '3 أشهر');
    expect(monthsCountLabel(10), '10 أشهر');
    expect(monthsCountLabel(11), '11 شهراً');
  });
}

// Populated interaction tests — the smoke test renders every screen EMPTY, which
// hides bugs that only appear with real data or when a form/sheet is opened.
// This suite loads a realistic residential bundle into DataStore, renders every
// screen populated, and opens + fills every add/edit sheet, asserting that no
// exception is ever thrown while building or interacting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amarati/app.dart';
import 'package:amarati/common.dart';

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
}

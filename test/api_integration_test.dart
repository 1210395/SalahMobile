// Data-pipeline test (no network): feeds API-shaped JSON through the model
// fromJson factories + DataStore, and asserts the synchronous getters surface
// the live data. The app is LIVE-DATA-ONLY (no bundled seed fallback — see
// commit a7852a7), so every getter is empty until a bundle is loaded. The real
// network path is exercised by the running app; the API itself is verified via
// the backend's PHPUnit suite.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sakan_pro/data/sample_data.dart';
import 'package:sakan_pro/theme/tokens.dart';
import 'package:sakan_pro/screens/report_pdf.dart' show reportBlocks;

void main() {
  setUp(() => DataStore.I.clear());

  test('empty when nothing loaded (no seed fallback)', () {
    expect(DataStore.I.loaded, isFalse);
    expect(kApartments, isEmpty);
    expect(kShops, isEmpty);
    expect(kPayments, isEmpty);
    expect(Summary.balance, 0);
    expect(Summary.due, 0);
  });

  test('live JSON populates getters for the active btype', () {
    final s = DataStore.I;
    s.loadedBtype = BType.commercial;
    s.units = [
      Unit.fromJson({'ext_id': 'S1', 'no': 'M-01', 'floor': 1, 'resident': 'صيدلية الشفاء', 'kind': 'مستأجر', 'phone': '+966', 'sub': 120, 'status': 'ok', 'balance': 0, 'payer': 'المستأجر'}),
      Unit.fromJson({'ext_id': 'S2', 'no': 'M-02', 'floor': 1, 'resident': 'مقهى لافندر', 'kind': 'مستأجر', 'phone': '+966', 'sub': 120, 'status': 'late', 'balance': -240, 'payer': 'المستأجر'}),
    ];
    s.payments = [
      Payment.fromJson({'id': 1, 'unit_no': 'M-01', 'name': 'صيدلية الشفاء', 'amount': 120, 'kind': 'الاشتراك الشهري', 'month': 4, 'year': 2026, 'date': '2026-05-03T00:00:00', 'method': 'تحويل بنكي'}),
    ];
    s.summary = SummaryData.fromJson({
      'balance': 99000, 'due': 1, 'revenueM': 2, 'expenseM': 3,
      'bars': [{'label': 'إيرادات', 'value': 10, 'color': 'navy600'}],
      'trend': [{'label': 'ينا', 'value': 5, 'color': 'navy600'}],
    });

    // Commercial getters now reflect the live data…
    expect(kShops.length, 2);
    expect(kShops.first.no, 'M-01');
    expect(kPayments.length, 1);
    expect(kPayments.first.unit, 'M-01');
    expect(kPayments.first.date, '2026-05-03'); // ISO time stripped
    expect(Summary.balance, 99000);
    expect(Summary.bars.first.color, isNotNull);

    // …while residential apartments stay empty (active btype is commercial,
    // and there is no seed fallback).
    expect(kApartments, isEmpty);
  });

  test('btype key round-trips', () {
    expect(btypeKey(BType.commercial), 'commercial');
    expect(btypeFromKey('commercial'), BType.commercial);
    expect(btypeFromKey(null), BType.residential);
  });

  test('Unit parses contract dates + login code (overhaul fields)', () {
    final open = Unit.fromJson({
      'no': '101', 'floor': 2, 'resident': 'أحمد', 'kind': 'مالك',
      'contract_start': '2026-01-01T00:00:00', 'contract_end': null,
      'login_code': 'A1B2C3D4',
    });
    expect(open.contractStart, '2026-01-01');
    expect(open.contractEnd, '');
    expect(open.ongoing, isTrue); // no end date → مستمر
    expect(open.loginCode, 'A1B2C3D4');

    final fixed = Unit.fromJson({
      'no': '102', 'floor': 2, 'resident': 'سارة', 'kind': 'مستأجر',
      'contract_start': '2026-01-01', 'contract_end': '2026-12-31',
    });
    expect(fixed.ongoing, isFalse);
    expect(fixed.contractEnd, '2026-12-31');
    expect(fixed.loginCode, '');
  });

  test('display helpers: months numbered, floor/unit label', () {
    expect(monthLabelNum(0), 'شهر 1');
    expect(monthLabelNum(11), 'شهر 12');
    expect(arMonthsNum.length, 12);
    expect(arMonthsNum.last, 'شهر 12');

    final apt = Unit.fromJson({'no': '5', 'floor': 3, 'resident': 'ليان', 'kind': 'مالك'});
    expect(floorUnitLabel(apt, true), 'طابق 3 شقة 5');
    expect(floorUnitLabel(apt, false), 'طابق 3 وحدة 5');
  });

  test('kYears unions live payment years with the recent window', () {
    final s = DataStore.I;
    s.payments = [
      Payment.fromJson({'id': 1, 'unit_no': '1', 'amount': 10, 'month': 0, 'year': 2022, 'date': '2022-01-01'}),
    ];
    final now = DateTime.now().year;
    expect(kYears, contains(2022));
    expect(kYears, contains(now));
    // sorted ascending
    final sorted = [...kYears]..sort();
    expect(kYears, sorted);
  });

  // ─────────── ذمم vs اشتراكات: two pots, never one number ───────────

  test('a unit carries its two pots apart, and owes on either', () {
    final u = Unit.fromJson({
      'no': '5', 'floor': 1, 'resident': 'ساكن', 'kind': 'مستأجر', 'sub': 100,
      'status': 'late', 'balance': -400, 'opening_balance': -700,
      'dues_balance': -700, 'sub_balance': 300,
    });
    expect(u.duesBalance, -700);
    expect(u.subBalance, 300);
    expect(u.duesOwed, 700);
    expect(u.subOwed, 0);
    // The subscription credit must NOT reduce what is owed on the ذمم.
    expect(u.owed, 700);
    expect(u.openingBalance, -700);
  });

  test('a server without the split is read as subscription-only', () {
    final u = Unit.fromJson({'no': '5', 'floor': 1, 'sub': 100, 'balance': -250});
    expect(u.duesBalance, 0);
    expect(u.subBalance, -250);
    expect(u.owed, 250);
  });

  test('a payment names the pot it settles, old rows included', () {
    Payment p(Map<String, dynamic> j) => Payment.fromJson({'id': 1, 'unit_no': '5', 'amount': 100, 'month': 0, 'year': 2026, 'date': '2026-01-01', ...j});

    expect(p({'bucket': 'dues'}).bucket, 'dues');
    expect(p({'bucket': 'none'}).bucket, 'none');
    // No bucket (a row written before the split): read it off what it does say.
    expect(p({'kind': 'ذمم'}).bucket, 'dues');
    expect(p({'kind': 'أخرى', 'applies_to_dues': false}).bucket, 'none');
    expect(p({'kind': 'دفعة شهرية'}).bucket, 'sub');
  });

  test('only a subscription payment settles a month', () {
    final s = DataStore.I;
    s.loadedBtype = BType.residential;
    s.payments = [
      Payment.fromJson({'id': 1, 'unit_no': '5', 'amount': 100, 'kind': 'ذمم', 'bucket': 'dues', 'month': 0, 'year': 2026, 'date': '2026-01-05'}),
      Payment.fromJson({'id': 2, 'unit_no': '5', 'amount': 40, 'kind': 'دفعة شهرية', 'bucket': 'sub', 'month': 0, 'year': 2026, 'date': '2026-01-05'}),
    ];
    // The ذمم payment is not part of January's subscription collection.
    expect(paidForMonth('5', 0, 2026), 40);
  });

  // ─────────── report layout: one table per block, not one for all ───────────

  test('a report splits into a table per block', () {
    // A unit report: a four-column summary, then a five-column payment list.
    // Rendered as one table, the summary's header governed both and the payment
    // columns were crushed — the client's "the report's shape needs fixing".
    final rows = <List<String>>[
      ['البند', 'المطلوب', 'المسدّد', 'المتبقي'],
      ['اشتراكات 2026', '600', '150', '450'],
      [],
      ['التاريخ', 'المبلغ', 'البند', 'يُخصم من', 'الطريقة'],
      ['2026-01-05', '150', 'دفعة شهرية', 'اشتراك شهري', 'نقداً'],
    ];

    final blocks = reportBlocks(rows);
    expect(blocks.length, 2);
    expect(blocks.first.first.length, 4);   // the summary keeps four columns
    expect(blocks.last.first.length, 5);    // the payments keep five
    expect(blocks.first.first.last, 'المتبقي');
  });

  test('blank and whitespace-only rows both end a block', () {
    final blocks = reportBlocks(<List<String>>[
      ['a'],
      [],
      ['b'],
      ['  ', ''],
      ['c'],
    ]);
    expect(blocks.length, 3);
  });

  // ─────────── a unit report names the right person, or nobody ───────────

  test('a report never falls back to a different resident', () {
    Unit u(String no, String name) => Unit.fromJson({
          'no': no, 'floor': 1, 'resident': name, 'kind': 'مستأجر', 'sub': 100,
          'status': 'ok', 'balance': 0,
        });
    final units = [u('1', 'موفق عليان'), u('2', 'بلال الفارس')];

    // The one that was asked for.
    expect(resolveReportUnit(units, '2')?.resident, 'بلال الفارس');

    // Nothing picked yet: the first, which the picker is showing.
    expect(resolveReportUnit(units, null)?.resident, 'موفق عليان');

    // The picked unit is gone (renamed, vacated, other building type). This used
    // to hand back units.first — so a report asked for بلال arrived carrying
    // موفق's name and payments.
    expect(resolveReportUnit(units, '99'), isNull);
    expect(resolveReportUnit(const [], '2'), isNull);
  });

  // ─────────── Brand exposes whether SMS can reach this host at all ───────────

  test('Brand parses the sms coverage block from /settings', () {
    DataStore.I.applySettingsJson({
      'app_name': 'عمارتي',
      'sms': {'available': true, 'coverage': []}, // a global provider, e.g. Twilio
    });
    expect(Brand.smsAvailable, isTrue);
    expect(Brand.smsCoverage, isEmpty); // empty = unrestricted, not "no coverage"
  });

  test('Brand falls back to the local-gateway default when sms is absent', () {
    // An older cached response / a host still on the pre-coverage controller.
    DataStore.I.applySettingsJson({'app_name': 'عمارتي'});
    expect(Brand.smsAvailable, isFalse);
    expect(Brand.smsCoverage, ['+970', '+972']);
  });

  // ─────────── the dark/light skin ───────────

  test('the app starts dark, and every colour follows the switch', () {
    // Dark is the brand's own world and the default the owner asked for.
    expect(AppTheme.skin.value, AppSkin.dark);
    expect(AppColors.page, kDarkPalette.page);
    expect(AppColors.ink900, kDarkPalette.ink900);

    AppTheme.skin.value = AppSkin.light;
    // The tokens are read through the active skin, so nothing else has to know.
    expect(AppColors.page, kLightPalette.page);
    expect(AppColors.ink900, kLightPalette.ink900);
    // The neutrals genuinely invert rather than shifting a shade.
    expect(AppColors.page.computeLuminance() > AppColors.ink900.computeLuminance(), isTrue);

    AppTheme.skin.value = AppSkin.dark;
    expect(AppColors.page.computeLuminance() < AppColors.ink900.computeLuminance(), isTrue);
  });

  test('shadows are black on dark and brand-tinted on light', () {
    // A cool-tinted shadow reads as depth on white and as a glow on black.
    AppTheme.skin.value = AppSkin.dark;
    expect(kDarkPalette.shadowInk, const Color(0xFF000000));
    AppTheme.skin.value = AppSkin.light;
    expect(kLightPalette.shadowInk == const Color(0xFF000000), isFalse);
    AppTheme.skin.value = AppSkin.dark;
  });

  test('the chosen skin survives a restart', () async {
    // The switch is worth nothing if the app forgets it on the next launch, and
    // the storage round-trip is the half that a screenshot cannot prove.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    AppTheme.skin.value = AppSkin.dark;
    await AppTheme.toggle();                 // the user taps the header button
    expect(AppTheme.skin.value, AppSkin.light);

    AppTheme.skin.value = AppSkin.dark;      // pretend the app was killed
    await AppTheme.restore();
    expect(AppTheme.skin.value, AppSkin.light, reason: 'light must survive a restart');

    await AppTheme.toggle();                 // back to dark, and that persists too
    AppTheme.skin.value = AppSkin.light;
    await AppTheme.restore();
    expect(AppTheme.skin.value, AppSkin.dark);
  });

  test('restore leaves the default alone when nothing was stored', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppTheme.skin.value = AppSkin.light;     // whatever the process happened to hold
    await AppTheme.restore();
    expect(AppTheme.skin.value, AppSkin.light,
        reason: 'restore must not invent a value when nothing was stored');
  });
}

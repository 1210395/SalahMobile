// Data-pipeline test (no network): feeds API-shaped JSON through the model
// fromJson factories + DataStore, and asserts the synchronous getters surface
// the live data. The real network path is exercised by the running app in a
// browser (see the ?demo= deep link), and the API itself is verified via curl.

import 'package:flutter_test/flutter_test.dart';

import 'package:amarati/data/sample_data.dart';

void main() {
  setUp(() => DataStore.I.clear());

  test('seed fallback when nothing loaded', () {
    expect(DataStore.I.loaded, isFalse);
    expect(kApartments.length, 8);
    expect(kShops.length, 6);
    expect(kPayments.length, 6);
    expect(Summary.balance, 25840);
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

    // …while residential apartments fall back to seed (active btype is commercial).
    expect(kApartments.length, 8);
  });

  test('btype key round-trips', () {
    expect(btypeKey(BType.commercial), 'commercial');
    expect(btypeFromKey('commercial'), BType.commercial);
    expect(btypeFromKey(null), BType.residential);
  });
}

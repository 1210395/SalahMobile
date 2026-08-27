// عمارتي — Admin: Reports, Alerts & Messages, Years.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../common.dart';
import '../api/repository.dart';
import '../data/file_save.dart';
import 'report_pdf.dart';

/// Clone chart data with a money value label drawn above each bar.
List<ChartDatum> _withValueLabels(List<ChartDatum> data) => data
    .map((d) => ChartDatum(label: d.label, value: d.value, color: d.color, label2: fmtUSD(d.value)))
    .toList();

// ───────────────────────────── Reports ─────────────────────────────

/// Set by another screen (e.g. Expenses) before navigating to 'reports' so the
/// reports screen opens on a specific tab. Consumed once in initState.
String? pendingReportTab;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String tab = 'monthly';

  @override
  void initState() {
    super.initState();
    if (pendingReportTab != null) {
      tab = pendingReportTab!;
      pendingReportTab = null;
    }
  }

  late int selYear = kYears.isNotEmpty ? kYears.last : DateTime.now().year;
  // -1 = كل الأشهر: default to the whole-year total so multi-month payments show
  // their full collected amount; the manager can narrow to a single month.
  int selMonth = -1;
  // Expense-report filters (category + month; -1 month = whole year).
  String expCat = 'all';
  int expMonth = -1;
  String expSupplier = 'all';
  String? selUnitNo;

  /// Building-wide amount collected in the selected month/year. selMonth == -1
  /// means "all months" — sums the whole year (so a multi-month payment shows
  /// its full total, e.g. 7 months × 100 = 700, not one month's 100).
  int _collected() => kPayments
      .where((p) => p.year == selYear && (selMonth == -1 || p.month == selMonth))
      .fold<int>(0, (s, p) => s + p.amount);

  /// Expenses dated within the selected month/year (selMonth == -1 = whole year).
  int _monthExpenses() => kExpenses.where((e) {
        final d = DateTime.tryParse(e.date);
        return d != null && d.year == selYear && (selMonth == -1 || d.month - 1 == selMonth);
      }).fold<int>(0, (s, e) => s + e.amount);

  /// Outstanding dues across the active building type — ذمم AND اشتراكات. Both
  /// pots are counted; netting them first let a subscription credit erase an
  /// open ذمة (and drop the unit off the "المتأخرون" list entirely).
  int _monthDue(Ctx ctx) => (ctx.res ? kApartments : kShops)
      .fold<int>(0, (s, u) => s + u.owed);

  /// Monthly chart built from LIVE figures (was static Summary.bars): collected
  /// vs expenses vs dues — recomputes whenever month/year/building changes.
  List<ChartDatum> _monthlyBars(Ctx ctx) => [
        ChartDatum(label: 'محصّل', value: _collected(), color: AppColors.ok),
        ChartDatum(label: 'مصروفات', value: _monthExpenses(), color: AppColors.late),
        ChartDatum(label: 'ذمم', value: _monthDue(ctx), color: AppColors.gold500),
      ];

  /// Annual 12-month revenue series for [selYear], summed straight from
  /// kPayments (robust regardless of any backend trend length).
  List<ChartDatum> _annualSeries() {
    final byMonth = List<int>.filled(12, 0);
    for (final p in kPayments) {
      if (p.year != selYear) continue;
      if (p.month < 0 || p.month > 11) continue;
      byMonth[p.month] += p.amount;
    }
    return [
      for (var i = 0; i < 12; i++)
        ChartDatum(label: monthLabelNum(i), value: byMonth[i], color: AppColors.navy600),
    ];
  }

  /// Sum of [unitNo]'s payments for a given 0-based [month] and [year].
  /// Values are kept signed (carry-over may be negative) — never clamped.
  int _paymentFor(String unitNo, int month, int year) => kPayments
      .where((p) => p.unit == unitNo && p.month == month && p.year == year)
      .fold<int>(0, (s, p) => s + p.amount);

  /// Live annual totals for the selected year (were hardcoded).
  int _yearRevenue() =>
      kPayments.where((p) => p.year == selYear).fold<int>(0, (s, p) => s + p.amount);
  int _yearExpenses() => kExpenses
      .where((e) => (DateTime.tryParse(e.date)?.year ?? selYear) == selYear)
      .fold<int>(0, (s, e) => s + e.amount);

  /// Export chooser: real .xlsx / .pdf files, either shared or SAVED to the
  /// device (#41 — the sheet used to offer share only), or copied as text.
  void _exportSheet(Ctx ctx, String title, List<List<String>> rows) {
    bool download = false;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: title,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Segmented(
                value: download ? 'save' : 'share',
                onChanged: (v) => setS(() => download = v == 'save'),
                options: const [
                  SegOption('share', 'مشاركة', icon: 'send'),
                  SegOption('save', 'تنزيل', icon: 'download'),
                ],
              ),
            ),
            _exportOption(
              icon: 'file',
              label: '${download ? 'تنزيل' : 'تصدير'} PDF (ملف .pdf)',
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  if (download) {
                    final path = await saveReportPdf(title, rows,
                        buildingName: ctx.building.name, fileName: _stampedName('pdf'));
                    ctx.toast('تم حفظ الملف في: $path');
                  } else {
                    await exportReportPdf(title, rows, buildingName: ctx.building.name);
                  }
                } catch (e) {
                  ctx.toast(apiErrorText(e), tone: 'late');
                }
              },
            ),
            const SizedBox(height: 10),
            _exportOption(
              icon: 'excel',
              label: '${download ? 'تنزيل' : 'تصدير'} Excel (ملف .xlsx)',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _shareReport(ctx, rows, excel: true, download: download);
              },
            ),
            const SizedBox(height: 10),
            _exportOption(
              icon: 'receipt',
              label: 'نسخ إلى الحافظة',
              onTap: () {
                Clipboard.setData(ClipboardData(text: _rowsToCsv(rows)));
                Navigator.of(sheetCtx).pop();
                ctx.toast('تم نسخ التقرير إلى الحافظة');
              },
            ),
            const SizedBox(height: 8),
            Text(
                download
                    ? 'يُحفظ الملف في مجلد التنزيلات على الجهاز، ويظهر مساره بعد الحفظ.'
                    : 'تُصدَّر الملفات عبر مشاركة النظام (واتساب، بريد، …).',
                style: AppType.base(
                    size: 11, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
          ],
        ),
      ),
    );
  }

  String _stampedName(String ext) =>
      'amarati-$tab-$selYear${(selMonth + 1).toString().padLeft(2, '0')}.$ext';

  Widget _exportOption({required String icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          IconChip(icon: icon, tone: 'navy', size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppType.base(size: 14.5, weight: FontWeight.w700))),
          const AppIcon('chevronL', size: 18, color: AppColors.ink300),
        ]),
      ),
    );
  }

  /// Prepend a branded header (app + building name) to exported rows so the
  /// Excel/CSV file identifies the building, mirroring the PDF header.
  List<List<String>> _withHeader(Ctx ctx, List<List<String>> rows) {
    final b = ctx.building.name.trim();
    return [
      ['عمارتي${b.isEmpty ? '' : ' — $b'}'],
      if (b.isNotEmpty) ['المبنى', b],
      <String>[],
      ...rows,
    ];
  }

  /// Build the .xlsx/.csv and either share it or save it to the device (#41).
  Future<void> _shareReport(Ctx ctx, List<List<String>> rows,
      {required bool excel, bool download = false}) async {
    try {
      final data = _withHeader(ctx, rows);
      final name = _stampedName(excel ? 'xlsx' : 'csv');
      final List<int> bytes;
      if (excel) {
        final book = xlsx.Excel.createExcel();
        final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];
        for (final r in data) {
          sheet.appendRow([for (final c in r) xlsx.TextCellValue(c)]);
        }
        bytes = book.encode() ?? <int>[];
      } else {
        // Prepend a BOM so Excel opens the Arabic CSV in UTF-8.
        bytes = utf8.encode('﻿${_rowsToCsv(data)}');
      }
      if (download) {
        final path = await saveToDownloads(name, bytes);
        ctx.toast('تم حفظ الملف في: $path');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'تقرير عمارتي');
    } catch (_) {
      ctx.toast('تعذّر تصدير الملف', tone: 'late');
    }
  }

  /// #41 — the comprehensive workbook can be shared or saved to the device.
  void _comprehensiveSheet(Ctx ctx) {
    showAppSheet(
      context,
      SheetShell(
        title: 'التقرير الشامل (Excel)',
        children: [
          _exportOption(
            icon: 'download',
            label: 'تنزيل الملف على الجهاز',
            onTap: () {
              Navigator.of(context).pop();
              _shareComprehensive(ctx, download: true);
            },
          ),
          const SizedBox(height: 10),
          _exportOption(
            icon: 'send',
            label: 'مشاركة الملف',
            onTap: () {
              Navigator.of(context).pop();
              _shareComprehensive(ctx);
            },
          ),
          const SizedBox(height: 8),
          Text('يحتوي الملف على ورقة لكل سنة فيها دفعات — الأحدث أولاً.',
              style: AppType.base(
                  size: 11, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
        ],
      ),
    );
  }

  /// "تقرير شامل" — a workbook with one sheet per year, each a resident-by-month
  /// matrix of payments (signed, carry-over included) drawn straight from live data.
  Future<void> _shareComprehensive(Ctx ctx, {bool download = false}) async {
    final residents =
        (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    if (residents.isEmpty) {
      ctx.toast('لا يوجد سكّان لإصدار تقرير شامل', tone: 'late');
      return;
    }
    // #42: kYears always seeds the last three calendar years, so the workbook
    // used to open on an empty 2024 sheet. Only export years that hold payments
    // (newest first), falling back to the selected year when there are none.
    var years = kYears.where((y) => kPayments.any((p) => p.year == y)).toList()
      ..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) years = [selYear];
    final bName = ctx.building.name.trim();
    try {
      final book = xlsx.Excel.createExcel();
      final defaultSheet = book.getDefaultSheet();
      for (final y in years) {
        final sheet = book['$y'];
        // Branded header: app + building name + report title, then a blank row.
        sheet.appendRow([xlsx.TextCellValue('عمارتي${bName.isEmpty ? '' : ' — $bName'}')]);
        sheet.appendRow([xlsx.TextCellValue('التقرير الشامل · $y')]);
        sheet.appendRow([xlsx.TextCellValue('')]);
        // Header: one row per apartment/shop; a column per month; then the
        // yearly summary columns (paid, required, remaining, paid-in-full).
        sheet.appendRow([
          xlsx.TextCellValue(ctx.res ? 'الشقة' : 'الوحدة'),
          for (var m = 0; m < 12; m++) xlsx.TextCellValue(monthLabelNum(m)),
          xlsx.TextCellValue('إجمالي المدفوع'),
          xlsx.TextCellValue('المطلوب سنوياً'),
          xlsx.TextCellValue('المتبقي'),
          xlsx.TextCellValue('مسدّد بالكامل؟'),
        ]);
        final monthTotals = List<int>.filled(12, 0);
        var paidAll = 0, reqAll = 0, remAll = 0;
        for (final u in residents) {
          var paidYear = 0;
          final cells = <xlsx.CellValue>[xlsx.TextCellValue('${u.no} — ${u.resident}')];
          for (var m = 0; m < 12; m++) {
            final v = _paymentFor(u.no, m, y);
            monthTotals[m] += v;
            paidYear += v;
            cells.add(xlsx.IntCellValue(v));
          }
          final required = u.sub * 12;
          cells.add(xlsx.IntCellValue(paidYear));
          cells.add(xlsx.IntCellValue(required));
          // The two pots are exported apart — a single netted number hid an
          // open ذمة behind a subscription credit.
          cells.add(xlsx.IntCellValue(u.duesBalance)); // ذمم: − = مدين
          cells.add(xlsx.IntCellValue(u.subBalance));  // اشتراكات: − = متأخر
          cells.add(xlsx.TextCellValue(u.owed == 0 ? 'نعم' : 'لا'));
          sheet.appendRow(cells);
          paidAll += paidYear;
          reqAll += required;
          // Grand total sums only what's OWED (debts), matching the dashboard's
          // الذمم — signed balances would let a credited unit cancel a debtor's
          // dues (owe 500 + credit 300 → misleading −200 instead of 500). The
          // per-row column keeps the signed balance above.
          remAll += u.owed;
        }
        // Trailing totals row: per-month column sums + the grand totals.
        sheet.appendRow([
          xlsx.TextCellValue('الإجمالي'),
          for (final t in monthTotals) xlsx.IntCellValue(t),
          xlsx.IntCellValue(paidAll),
          xlsx.IntCellValue(reqAll),
          xlsx.IntCellValue(remAll),
          xlsx.TextCellValue(''),
        ]);
      }
      // Drop the auto-created default sheet (we only want the per-year ones).
      if (defaultSheet != null && !years.map((y) => '$y').contains(defaultSheet)) {
        book.delete(defaultSheet);
      }
      final bytes = book.encode() ?? <int>[];
      if (download) {
        final path = await saveToDownloads('amarati-comprehensive.xlsx', bytes);
        ctx.toast('تم حفظ الملف في: $path');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/amarati-comprehensive.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'التقرير الشامل — عمارتي');
    } catch (_) {
      ctx.toast('تعذّر تصدير الملف', tone: 'late');
    }
  }

  String _rowsToCsv(List<List<String>> rows) => rows.map((r) => r.map(_csvCell).join(',')).join('\n');

  String _csvCell(String v) =>
      v.contains(',') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v;

  /// What this report IS, for the PDF's centred heading. A unit report must say
  /// whose it is: the resident asked for one man's statement and got another
  /// man's name at the top, because the title was the same generic phrase for
  /// every report the screen could produce.
  String _reportTitle(Ctx ctx) {
    final unitWord = ctx.res ? 'شقة' : 'وحدة';
    switch (tab) {
      case 'monthly':
        return selMonth == -1
            ? 'التقرير الشهري — كل أشهر $selYear'
            : 'التقرير الشهري — ${monthLabelNum(selMonth)} $selYear';
      case 'annual':
        return 'التقرير السنوي — $selYear';
      case 'unit':
        final u = _selectedUnit(ctx);
        return u == null
            ? 'تقرير ${ctx.res ? 'الشقة' : 'الوحدة'}'
            : 'كشف حساب — ${u.resident} · $unitWord ${u.no}';
      default:
        return 'تقرير المصروفات — $selYear';
    }
  }

  List<List<String>> _reportRows(Ctx ctx, List<Unit> lateUnits) {
    final unitWord = ctx.res ? 'الشقة' : 'الوحدة';
    switch (tab) {
      case 'monthly':
        return [
          ['التقرير الشهري', selMonth == -1 ? 'كل أشهر $selYear' : '${monthLabelNum(selMonth)} $selYear'],
          [],
          ['البند', 'القيمة'],
          ['إجمالي محصّل', '${_collected()}'],
          ['المصروفات', '${_monthExpenses()}'],
          ['الذمم', '${_monthDue(ctx)}'],
          [],
          ['المتأخرون', unitWord, 'ذمم سابقة', 'اشتراكات'],
          for (final u in lateUnits) [u.resident, u.no, '${u.duesOwed}', '${u.subOwed}'],
        ];
      case 'annual':
        return [
          ['التقرير السنوي', '$selYear'],
          [],
          ['الشهر', 'القيمة'],
          for (final d in _annualSeries()) [d.label, '${d.value}'],
          [],
          ['إجمالي الإيرادات', '${_yearRevenue()}'],
          ['إجمالي المصروفات', '${_yearExpenses()}'],
        ];
      case 'unit':
        final units = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
        if (units.isEmpty) {
          return [['تقرير ${ctx.res ? 'الشقة' : 'الوحدة'}', '—']];
        }
        // A stale or unmatched selection used to fall back to units.first, so a
        // report asked for one resident came out carrying another one's name and
        // payments. Say nothing rather than say someone else.
        final u = _selectedUnit(ctx);
        if (u == null) {
          return [['اختر ${ctx.res ? 'الشقة' : 'الوحدة'} أولاً']];
        }

        final subRequired = u.sub * 12;
        final subPaid = kPayments
            .where((p) => p.unit == u.no && p.year == selYear && p.isSub)
            .fold<int>(0, (t, p) => t + p.amount);
        final duesEntered = -u.openingBalance; // stored pre-negated
        final duesPaid = kPayments
            .where((p) => p.unit == u.no && p.isDues)
            .fold<int>(0, (t, p) => t + p.amount);
        final subLeft = subRequired - subPaid > 0 ? subRequired - subPaid : 0;
        final duesLeft = duesEntered - duesPaid > 0 ? duesEntered - duesPaid : 0;

        return [
          // Block 1 — the figures, with المتبقي as a column of its own.
          ['البند', 'المطلوب', 'المسدّد', 'المتبقي'],
          ['اشتراكات $selYear', '$subRequired', '$subPaid', '$subLeft'],
          ['ذمم سابقة', '$duesEntered', '$duesPaid', '$duesLeft'],
          ['الإجمالي', '${subRequired + duesEntered}', '${subPaid + duesPaid}', '${subLeft + duesLeft}'],
          [],
          // Block 2 — the payments, in their own table with their own headers.
          ['التاريخ', 'المبلغ', 'البند', 'يُخصم من', 'الطريقة'],
          for (final p in kPayments.where((p) => p.unit == u.no))
            [
              p.date,
              '${p.amount}',
              p.kind,
              p.isDues ? 'ذمم سابقة' : (p.isSub ? 'اشتراك شهري' : 'إيراد فقط'),
              p.method,
            ],
        ];
      default:
        return [
          ['تقرير المصروفات', '$selYear'],
          [],
          ['التصنيف', 'القيمة'],
          for (final d in _expenseData()) [d.label, '${d.value}'],
        ];
    }
  }

  /// Live expense breakdown by category for the selected year.
  List<ChartDatum> _expenseData() {
    final byCat = <String, int>{};
    for (final e in kExpenses) {
      final d = DateTime.tryParse(e.date);
      if (d != null && d.year != selYear) continue;
      if (expMonth >= 0 && (d == null || d.month - 1 != expMonth)) continue;
      if (expCat != 'all' && e.cat != expCat) continue;
      if (expSupplier != 'all' && e.supplier != expSupplier) continue;
      byCat[e.cat] = (byCat[e.cat] ?? 0) + e.amount;
    }
    const palette = [
      AppColors.navy600, AppColors.ok, AppColors.warn, AppColors.credit, AppColors.gold500
    ];
    final cats = byCat.keys.toList();
    return [
      for (var i = 0; i < cats.length; i++)
        ChartDatum(label: cats[i], value: byCat[cats[i]]!, color: palette[i % palette.length]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final lateUnits =
        (ctx.res ? kApartments : kShops).where((u) => u.status == 'late').toList();
    final expData = _expenseData();
    final expTotal = expData.fold<num>(0, (s, d) => s + d.value).toInt();

    return ScreenScaffold(
      header: AppHeader(
        title: 'التقارير',
        subtitle: 'تحليل شامل للمبنى',
        onHome: ctx.role == AppRole.admin ? () => ctx.go('home') : null,
        right: Row(mainAxisSize: MainAxisSize.min, children: [
          RoundBtn(icon: 'excel', onTap: () => _comprehensiveSheet(ctx)),
          const SizedBox(width: 8),
          RoundBtn(
              icon: 'download',
              onTap: () => _exportSheet(ctx, _reportTitle(ctx), _reportRows(ctx, lateUnits))),
        ]),
      ),
      nav: ctx.adminNav,
      children: [
        Segmented(
          small: true,
          value: tab,
          onChanged: (v) => setState(() => tab = v as String),
          options: [
            const SegOption('monthly', 'شهري'),
            const SegOption('annual', 'سنوي'),
            SegOption('unit', ctx.res ? 'شقة' : 'وحدة'),
            const SegOption('expense', 'مصروفات'),
          ],
        ),
        const SizedBox(height: 14),
        if (tab == 'monthly') ..._monthly(ctx, lateUnits),
        if (tab == 'annual') ..._annual(),
        if (tab == 'unit') ..._unit(ctx),
        if (tab == 'expense') ..._expense(expData, expTotal),
        const SizedBox(height: 4),
        AppButton(
          label: 'تقرير شامل (Excel)',
          full: true,
          icon: 'excel',
          onTap: () => _comprehensiveSheet(ctx),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: AppButton(
                label: 'PDF',
                variant: BtnVariant.outline,
                full: true,
                icon: 'file',
                onTap: () async {
                  try {
                    await exportReportPdf(_reportTitle(ctx), _reportRows(ctx, lateUnits),
                        buildingName: ctx.building.name);
                  } catch (e) {
                    ctx.toast(apiErrorText(e), tone: 'late');
                  }
                }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
                label: 'Excel',
                variant: BtnVariant.outline,
                full: true,
                icon: 'excel',
                onTap: () => _shareReport(ctx, _reportRows(ctx, lateUnits), excel: true)),
          ),
        ]),
      ],
    );
  }

  Widget _yearSelect() {
    // Offer a range of recent years (not only years that already have data) so
    // past periods can be viewed/edited in the reports.
    final now = DateTime.now().year;
    final years = <int>{for (var y = now - 5; y <= now; y++) y, ...kYears, selYear}.toList()
      ..sort();
    return SelectField(
      label: 'السنة',
      icon: 'calendar',
      options: [for (final y in years) SelectOption(y, '$y')],
      value: years.contains(selYear) ? selYear : years.last,
      onChanged: (v) => setState(() => selYear = v as int),
    );
  }

  Widget _monthSelect() => SelectField(
        label: 'الشهر',
        options: [
          const SelectOption(-1, 'كل الأشهر'),
          for (var i = 0; i < 12; i++) SelectOption(i, monthLabelNum(i)),
        ],
        value: selMonth,
        onChanged: (v) => setState(() => selMonth = v as int),
      );

  List<Widget> _monthly(Ctx ctx, List<Unit> lateUnits) {
    final collected = _collected();
    final expenses = _monthExpenses();
    final due = _monthDue(ctx);
    final unitWord = ctx.res ? 'شقة' : 'وحدة';
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _monthSelect()),
          const SizedBox(width: 10),
          Expanded(child: _yearSelect()),
        ],
      ),
      Row(children: [
        Expanded(child: StatCard(label: 'إجمالي محصّل', value: fmtUSD(collected), icon: 'trend', tone: 'ok')),
        const SizedBox(width: 10),
        Expanded(child: StatCard(label: 'الذمم', value: fmtUSD(due), icon: 'alert', tone: 'gold')),
      ]),
      const SizedBox(height: 12),
      // Nothing collected / spent / owed this month → show the empty state.
      if (collected == 0 && expenses == 0 && due == 0)
        const EmptyState(icon: 'trend', title: 'لا توجد حركة في هذا الشهر')
      else ...[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(text: 'الحركة الشهرية', margin: EdgeInsets.only(bottom: 10)),
              BarChart(data: _withValueLabels(_monthlyBars(ctx))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          pad: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Text('المتأخرون عن السداد', style: AppType.base(size: 13, weight: FontWeight.w800)),
              ),
              if (lateUnits.isEmpty)
                const EmptyState(icon: 'checkCircle', title: 'لا يوجد متأخرون')
              else
                ...List.generate(lateUnits.length, (i) {
                  final u = lateUnits[i];
                  return ListRow(
                    leading: Avatar(name: u.resident, size: 38, tone: 'navy'),
                    title: u.resident,
                    sub: '$unitWord ${u.no}',
                    dividerBelow: i < lateUnits.length - 1,
                    trailing: NumText(fmtUSD(-u.owed),
                        style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.late700)),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _annual() {
    final series = _annualSeries();
    final revenue = _yearRevenue();
    final hasData = revenue != 0 || _yearExpenses() != 0 || series.any((d) => d.value != 0);
    return [
      _yearSelect(),
      if (!hasData)
        const EmptyState(icon: 'trend', title: 'لا توجد بيانات لهذه السنة')
      else ...[
        HeroBanner(
          gradient: const [AppColors.navy700, AppColors.navy800],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الرصيد النهائي — $selYear',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.navy300)),
              const SizedBox(height: 6),
              NumText(fmtUSD(revenue - _yearExpenses()),
                  style: AppType.num(size: 28, weight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(text: 'الإيرادات الشهرية', margin: EdgeInsets.only(bottom: 10)),
              BarChart(data: series),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatCard(label: 'إجمالي الإيرادات', value: fmtUSD(revenue), icon: 'trend', tone: 'ok')),
          const SizedBox(width: 10),
          Expanded(child: StatCard(label: 'إجمالي المصروفات', value: fmtUSD(_yearExpenses()), icon: 'expense', tone: 'late')),
        ]),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// The unit a unit-report is FOR — never a fallback to somebody else.
  ///
  /// The screen and the export both used `orElse: () => units.first`, so a
  /// selection that no longer matched (a renamed unit, a switch between سكني and
  /// تجاري, a unit marked vacant) silently produced a report carrying another
  /// resident's name and payments. Returning null makes that state visible.
  Unit? _selectedUnit(Ctx ctx) => resolveReportUnit(
        (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList(),
        selUnitNo,
      );

  List<Widget> _unit(Ctx ctx) {
    final units = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    if (units.isEmpty) {
      return [EmptyState(icon: 'building', title: ctx.res ? 'لا توجد شقق فعّالة' : 'لا توجد وحدات فعّالة')];
    }
    final picked = _selectedUnit(ctx);
    if (picked == null) {
      return [
        SelectField(
          label: 'اختر الوحدة',
          icon: 'building',
          options: units.map((x) => SelectOption(x.no, '${x.no} — ${x.resident}')).toList(),
          value: units.first.no,
          onChanged: (v) => setState(() => selUnitNo = v as String),
        ),
        const EmptyState(
            icon: 'building',
            title: 'الوحدة المختارة لم تعد موجودة',
            sub: 'اختر وحدة من القائمة أعلاه'),
      ];
    }
    final u = picked;
    final s = kStatusMap[u.status]!;
    final pays = kPayments.where((p) => p.unit == u.no).toList();
    final required = u.sub * 12;
    // "المسدّد" = the unit's ACTUAL payments, not required+balance (which
    // over-counted a credited unit — the 909 bug). Each pot counts only its own
    // payments: a ذمم payment does not settle a month's subscription.
    final subPaidYear = kPayments
        .where((p) => p.unit == u.no && p.year == selYear && p.isSub)
        .fold<int>(0, (sum, p) => sum + p.amount);
    final duesEntered = -u.openingBalance;
    final duesPaidAll = kPayments
        .where((p) => p.unit == u.no && p.isDues)
        .fold<int>(0, (sum, p) => sum + p.amount);
    final subLeft = required - subPaidYear > 0 ? required - subPaidYear : 0;
    final duesLeft = duesEntered - duesPaidAll > 0 ? duesEntered - duesPaidAll : 0;

    return [
      SelectField(
        label: 'اختر الوحدة',
        icon: 'building',
        options: units.map((x) => SelectOption(x.no, '${x.no} — ${x.resident}')).toList(),
        value: u.no,
        onChanged: (v) => setState(() => selUnitNo = v as String),
      ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Avatar(name: u.resident, size: 46, tone: u.kind == 'مالك' ? 'navy' : 'gold'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(u.resident, style: AppType.base(size: 15, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${ctx.res ? 'شقة' : 'وحدة'} ${u.no} · ${u.kind}',
                          style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppBadge(label: s.label, tone: s.tone, icon: u.status == 'ok' ? 'checkCircle' : null),
              ],
            ),
            const SizedBox(height: 14),
            DetailGrid(rows: [
              DetailRow('wallet', 'اشتراكات $selYear المطلوبة', fmtUSD(required)),
              DetailRow('checkCircle', 'المسدّد من الاشتراكات', fmtUSD(subPaidYear), tone: 'ok'),
              // The figure a manager reads out to a resident: what is still owed,
              // per pot, and then the two together.
              DetailRow('dollar', 'المتبقي من الاشتراكات', fmtUSD(subLeft),
                  tone: subLeft > 0 ? 'late' : 'ok'),
              DetailRow('wallet', 'ذمم سابقة', fmtUSD(duesEntered)),
              DetailRow('checkCircle', 'المسدّد من الذمم', fmtUSD(duesPaidAll), tone: 'ok'),
              DetailRow('dollar', 'المتبقي من الذمم', fmtUSD(duesLeft),
                  tone: duesLeft > 0 ? 'late' : 'ok'),
              DetailRow('dollar', 'إجمالي المتبقي', fmtUSD(subLeft + duesLeft),
                  tone: (subLeft + duesLeft) > 0 ? 'late' : 'ok'),
              DetailRow('calendar', 'آخر دفعة', pays.isNotEmpty ? pays.first.date : '—', ltr: true),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        pad: 6,
        child: pays.isEmpty
            ? const EmptyState(icon: 'wallet', title: 'لا توجد مدفوعات لهذه الوحدة')
            : Column(
                children: List.generate(pays.length, (i) {
                  final p = pays[i];
                  return ListRow(
                    leading: const IconChip(icon: 'wallet', tone: 'ok', size: 40),
                    title: p.kind,
                    sub: '${p.method} · ${monthLabelNum(p.month)} ${p.year}',
                    dividerBelow: i < pays.length - 1,
                    trailing: NumText('+${fmtUSD(p.amount)}',
                        style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.ok700)),
                  );
                }),
              ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _expense(List<ChartDatum> expData, int expTotal) => [
        _yearSelect(),
        // Filters: category + month (more granular expense reporting).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectField(
                label: 'التصنيف',
                icon: 'grid',
                options: [
                  const SelectOption('all', 'كل التصنيفات'),
                  for (final c in kExpCats) SelectOption(c, c),
                ],
                value: expCat,
                onChanged: (v) => setState(() => expCat = v as String),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField(
                label: 'الشهر',
                icon: 'calendar',
                options: [
                  const SelectOption(-1, 'كل الأشهر'),
                  for (var i = 0; i < 12; i++) SelectOption(i, monthLabelNum(i)),
                ],
                value: expMonth,
                onChanged: (v) => setState(() => expMonth = v as int),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Supplier/vendor filter (in addition to category + month + year).
        SelectField(
          label: 'المورّد / الجهة',
          icon: 'building',
          options: [
            const SelectOption('all', 'كل الموردين'),
            for (final s in (kExpenses.map((e) => e.supplier).where((s) => s.isNotEmpty).toSet().toList()
              ..sort()))
              SelectOption(s, s),
          ],
          value: expSupplier,
          onChanged: (v) => setState(() => expSupplier = v as String),
        ),
        const SizedBox(height: 4),
        if (expData.isEmpty)
          const EmptyState(icon: 'expense', title: 'لا توجد مصروفات مطابقة للفلاتر'),
        if (expData.isNotEmpty)
        AppCard(
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Donut(data: expData),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NumText(fmtUSD(expTotal), style: AppType.num(size: 16, weight: FontWeight.w800)),
                        Text('الإجمالي', style: AppType.base(size: 10, weight: FontWeight.w600, color: AppColors.ink500)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: expData
                      .map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              Container(width: 9, height: 9, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(d.label,
                                    style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink600)),
                              ),
                              NumText(fmtUSD(d.value), style: AppType.num(size: 12.5, weight: FontWeight.w800)),
                            ]),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ];
}

// ───────────────────────────── Alerts & Messages ─────────────────────────────

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String tab = 'alerts';
  String _note = '';
  int _noteSeq = 0; // bump to reset the composer field after sending
  // The manager's inbox of resident notes (loaded on open for admins).
  List<Map<String, dynamic>>? _notes;

  @override
  void initState() {
    super.initState();
    if (widget.ctx.role == AppRole.admin) _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final list = await Api.I.listNotes(widget.ctx.btype);
      if (mounted) setState(() => _notes = list);
    } catch (_) {
      if (mounted) setState(() => _notes = const []);
    }
  }

  Future<void> _markNoteRead(int id) async {
    try {
      await Api.I.markNoteRead(id);
      await _loadNotes();
    } catch (e) {
      if (mounted) widget.ctx.toast(apiErrorText(e), tone: 'late');
    }
  }

  /// The manager's inbox of resident notes (name + unit + body), tap = mark read.
  List<Widget> _residentNotes(Ctx ctx) {
    final notes = _notes;
    if (notes == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(color: AppColors.navy700)),
        ),
      ];
    }
    final unread = notes.where((n) => n['status'] == 'new').length;
    return [
      const SizedBox(height: 4),
      SectionTitle(text: 'رسائل السكان${unread > 0 ? ' ($unread جديدة)' : ''}'),
      if (notes.isEmpty)
        const EmptyState(icon: 'bell', title: 'لا توجد رسائل من السكان', sub: 'ستظهر هنا ملاحظات السكان')
      else
        ...notes.map((n) {
          final isNew = n['status'] == 'new';
          final unit = '${n['unit_no'] ?? ''}'.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              pad: 13,
              onTap: isNew ? () => _markNoteRead((n['id'] as num).toInt()) : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconChip(icon: 'user', tone: isNew ? 'gold' : 'navy', size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              '${n['name'] ?? 'ساكن'}'
                              '${unit.isEmpty ? '' : ' · ${ctx.res ? 'شقة' : 'وحدة'} $unit'}',
                              style: AppType.base(size: 14, weight: FontWeight.w800),
                            ),
                          ),
                          if (isNew) const AppBadge(label: 'جديد', tone: 'gold', small: true),
                        ]),
                        const SizedBox(height: 4),
                        Text('${n['body'] ?? ''}',
                            style: AppType.base(
                                size: 12.5, weight: FontWeight.w500, color: AppColors.ink600, height: 1.55)),
                        if (isNew)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('اضغط لتعليمها كمقروءة',
                                style: AppType.base(size: 11, weight: FontWeight.w600, color: AppColors.navy500)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      const SizedBox(height: 8),
    ];
  }

  /// Residents see only their own unit's alerts + general (non unit-specific)
  /// announcements broadcast by the building admin.
  List<AlertItem> _visibleAlerts(Ctx ctx, bool isAdmin) {
    if (isAdmin) return kAlerts;
    final mine = (ctx.res ? kApartments : kShops)
        .firstWhere((u) => u.status != 'vacant', orElse: () => (ctx.res ? kApartments : kShops).first);
    return kAlerts.where((a) {
      final unitSpecific = a.type == 'subscription' || a.type == 'paid';
      if (!unitSpecific) return true; // general announcement → everyone
      return a.title.contains(mine.no) || a.body.contains(mine.no);
    }).toList();
  }

  Future<void> _sendNote(Ctx ctx) async {
    final body = _note.trim();
    if (body.isEmpty) return;
    try {
      await Api.I.createNote(body);
      ctx.toast('تم إرسال ملاحظتك لمسؤول العمارة');
      setState(() {
        _note = '';
        _noteSeq++;
      });
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
    }
  }

  Future<void> _regenerate(Ctx ctx) async {
    try {
      final n = await Api.I.regenerateAlerts(ctx.btype);
      await ctx.reload();
      ctx.toast('تم تحديث التنبيهات من البيانات ($n)');
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
    }
  }

  // Ready-made notification choices (title + body) the manager can pick, plus a
  // free-text option.
  static const _templates = [
    ['تذكير بدفع الاشتراك', 'نرجو سداد الاشتراك الشهري المستحق في أقرب وقت ممكن. شكراً لتعاونكم.'],
    ['صيانة المصعد', 'سيتم إجراء صيانة دورية للمصعد. نعتذر عن أي إزعاج.'],
    ['انقطاع الكهرباء', 'يوجد انقطاع مجدول للكهرباء عن المبنى. يرجى أخذ الاحتياط.'],
    ['اجتماع لجنة المبنى', 'يُعقد اجتماع لسكان المبنى لمناقشة شؤون العمارة. حضوركم مهم.'],
  ];

  /// Manager composes a notification: choose recipients (all / a specific unit /
  /// late payers / a floor), pick a ready template or write custom text, send.
  void _openCompose(Ctx ctx) {
    final units = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    final floors = units.map((u) => u.floor).toSet().toList()..sort();
    final unitWord = ctx.res ? 'شقة' : 'وحدة';
    String target = 'all';
    String unitNo = units.isNotEmpty ? units.first.no : '';
    int selFloor = floors.isNotEmpty ? floors.first : 0;
    String title = '';
    String body = '';
    int seq = 0; // bump to re-seed title/body fields when a template is chosen
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) {
          // Resolve the concrete recipient units for the chosen target. A
          // resident sees an alert whose target is 'all' or their own unit_no,
          // so non-'all' targets are sent as one alert per matched unit.
          final recips = target == 'unit'
              ? units.where((u) => u.no == unitNo).toList()
              : target == 'late'
                  ? units.where((u) => u.owed > 0).toList()
                  : target == 'floor'
                      ? units.where((u) => u.floor == selFloor).toList()
                      : units;
          // Every reason the notification can't be sent yet — the send button used
          // to just grey out and leave the manager guessing.
          final blockers = <String>[
            if (title.trim().isEmpty) 'عنوان الإشعار',
            if (body.trim().isEmpty) 'نص الإشعار',
            if (target != 'all' && recips.isEmpty) 'لا يوجد مستلمون مطابقون — غيّر المستلمين',
          ];
          final canSend = blockers.isEmpty;
          return SheetShell(
            title: 'إرسال إشعار',
            footer: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (blockers.isNotEmpty) ...[
                  FormBlockedHint(reasons: blockers, title: 'لإرسال الإشعار، أكمل ما يلي:'),
                  const SizedBox(height: 10),
                ],
                AppButton(
                  label: target == 'all' ? 'إرسال للجميع' : 'إرسال · ${recips.length} مستلم',
                  full: true,
                  size: BtnSize.lg,
                  icon: 'send',
                  disabled: !canSend,
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    try {
                      if (target == 'all') {
                        await Api.I.sendNotification(ctx.btype, {
                          'title': title.trim(),
                          'body': body.trim(),
                          'target': 'all',
                        });
                      } else {
                        for (final u in recips) {
                          await Api.I.sendNotification(ctx.btype, {
                            'title': title.trim(),
                            'body': body.trim(),
                            'target': u.no,
                          });
                        }
                      }
                      await ctx.reload();
                      final n = target == 'all' ? units.length : recips.length;
                      ctx.toast('تم إرسال الإشعار ($n مستلم)');
                    } catch (e) {
                      ctx.toast(apiErrorText(e), tone: 'late');
                    }
                  },
                ),
              ],
            ),
            children: [
              SelectField(
                label: 'المستلمون',
                icon: 'bell',
                options: [
                  const SelectOption('all', 'كل السكان'),
                  SelectOption('unit', '$unitWord محدد'),
                  const SelectOption('late', 'المتأخرون عن السداد'),
                  const SelectOption('floor', 'طابق محدد'),
                ],
                value: target,
                onChanged: (v) => setS(() => target = v as String),
              ),
              const SizedBox(height: 12),
              if (target == 'unit')
                SelectField(
                  label: unitWord,
                  icon: 'building',
                  options: [for (final u in units) SelectOption(u.no, '${u.no} — ${u.resident}')],
                  value: unitNo.isEmpty ? null : unitNo,
                  onChanged: (v) => setS(() => unitNo = v as String),
                ),
              if (target == 'floor')
                SelectField(
                  label: 'الطابق',
                  icon: 'building',
                  options: [for (final fl in floors) SelectOption(fl, 'الطابق $fl')],
                  value: selFloor,
                  onChanged: (v) => setS(() => selFloor = v as int),
                ),
              // The empty case now lives in the blockers list above the send button.
              if (target != 'all' && recips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'سيصل إلى ${recips.length} ${recips.length == 1 ? 'مستلم' : 'مستلمين'}: '
                        '${recips.take(4).map((u) => u.no).join('، ')}${recips.length > 4 ? '…' : ''}',
                    style: AppType.base(
                        size: 11.5, weight: FontWeight.w600, color: AppColors.ink500),
                  ),
                ),
              Text('اختيارات جاهزة',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _templates)
                  GestureDetector(
                    onTap: () => setS(() {
                      title = t[0];
                      body = t[1];
                      seq++;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: title == t[0] ? AppColors.navy700 : AppColors.surface,
                        border: Border.all(
                            color: title == t[0] ? AppColors.navy700 : AppColors.line2, width: 1.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t[0],
                          style: AppType.base(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: title == t[0] ? Colors.white : AppColors.ink600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Field(
              key: ValueKey('notif-title-$seq'),
              label: 'العنوان',
              icon: 'bell',
              value: title,
              placeholder: 'عنوان الإشعار',
              onChanged: (v) => setS(() => title = v),
            ),
            AppTextArea(
              key: ValueKey('notif-body-$seq'),
              label: 'النص',
              value: body,
              placeholder: 'اكتب نص الإشعار…',
              onChanged: (v) => setS(() => body = v),
            ),
          ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final isAdmin = ctx.role == AppRole.admin;
    final alerts = _visibleAlerts(ctx, isAdmin);

    return ScreenScaffold(
      header: AppHeader(
        title: 'التنبيهات والرسائل',
        onBack: ctx.back,
        right: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isAdmin) ...[
            RoundBtn(icon: 'refresh', onTap: () => _regenerate(ctx)),
            const SizedBox(width: 8),
          ],
          RoundBtn(icon: 'settings', onTap: () => setState(() => tab = 'settings')),
        ]),
      ),
      nav: isAdmin ? ctx.adminNav : ctx.resNav,
      fab: isAdmin && tab == 'alerts'
          ? AppFab(icon: 'send', label: 'إرسال إشعار', onTap: () => _openCompose(ctx))
          : null,
      children: [
        Segmented(
          value: tab,
          onChanged: (v) => setState(() => tab = v as String),
          options: const [
            SegOption('alerts', 'التنبيهات'),
            SegOption('settings', 'الإعدادات'),
          ],
        ),
        const SizedBox(height: 14),
        if (tab == 'alerts')
          ...alerts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  pad: 13,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconChip(icon: a.icon, tone: a.tone, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(a.title, style: AppType.base(size: 14, weight: FontWeight.w800)),
                                ),
                                const SizedBox(width: 8),
                                Text(a.time,
                                    style: AppType.base(size: 10.5, weight: FontWeight.w600, color: AppColors.ink400)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(a.body,
                                style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.ink600, height: 1.55)),
                            if (isAdmin && a.channel == 'whatsapp')
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: AppButton(
                                    label: 'إرسال تذكير واتساب',
                                    variant: BtnVariant.ghost,
                                    size: BtnSize.sm,
                                    icon: 'whatsapp',
                                    onTap: () => _openWa(ctx),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        // Manager inbox: notes residents sent (name + unit + body), tap to mark read.
        if (tab == 'alerts' && isAdmin) ..._residentNotes(ctx),
        // Residents can send a short note (≤ 50 chars) to the building admin.
        if (tab == 'alerts' && !isAdmin) ...[
          const SizedBox(height: 4),
          const SectionTitle(text: 'إرسال ملاحظة لمسؤول العمارة'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Field(
                  key: ValueKey('note$_noteSeq'),
                  icon: 'bell',
                  placeholder: 'اكتب ملاحظتك (حتى 50 حرفاً)…',
                  maxLength: 50,
                  marginBottom: 10,
                  hint: 'متبقٍ ${50 - _note.length} حرفاً',
                  onChanged: (v) => setState(() => _note = v),
                ),
                if (_note.trim().isEmpty) ...[
                  const FormBlockedHint(
                      reasons: ['اكتب ملاحظتك أولاً'], title: 'لإرسال الملاحظة:'),
                  const SizedBox(height: 10),
                ],
                AppButton(
                  label: 'إرسال',
                  full: true,
                  icon: 'send',
                  disabled: _note.trim().isEmpty,
                  onTap: () => _sendNote(ctx),
                ),
              ],
            ),
          ),
        ],
        if (tab == 'settings') ..._settings(ctx),
      ],
    );
  }

  List<Widget> _settings(Ctx ctx) {
    const rows = [
      ['اشتراك مستحق', 'wallet'],
      ['عقد المصعد', 'elevator'],
      ['تأمين المبنى', 'shield'],
      ['أجور النظافة', 'broom'],
      ['أجرة الحارس', 'user'],
      ['أجرة الباركينج', 'parking'],
    ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text('التنبيهات التلقائية',
            style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink500)),
      ),
      AppCard(
        pad: 6,
        child: Column(
          children: List.generate(rows.length, (i) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? const Border(bottom: BorderSide(color: AppColors.line))
                    : null,
              ),
              child: Row(children: [
                IconChip(icon: rows[i][1], tone: 'navy', size: 38),
                const SizedBox(width: 11),
                Expanded(child: Text(rows[i][0], style: AppType.base(size: 14, weight: FontWeight.w700))),
                _SettingsSwitch(initial: i % 3 != 2),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text('قنوات الإرسال',
            style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink500)),
      ),
      Row(children: [
        Expanded(child: _channelCard('whatsapp', 'واتساب', AppColors.ok700)),
        const SizedBox(width: 10),
        Expanded(child: _channelCard('bell', 'إشعار داخلي', AppColors.navy700)),
      ]),
      const SizedBox(height: 16),
      AppButton(
        label: 'الرسائل الجاهزة (واتساب)',
        variant: BtnVariant.outline,
        full: true,
        icon: 'send',
        onTap: () => _openWa(ctx),
      ),
    ];
  }

  Widget _channelCard(String icon, String label, Color color) => AppCard(
        pad: 14,
        child: Column(
          children: [
            AppIcon(icon, size: 26, color: color),
            const SizedBox(height: 6),
            Text(label, style: AppType.base(size: 13, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            const _SettingsSwitch(initial: true),
          ],
        ),
      );

  void _openWa(Ctx ctx) {
    showAppSheet(
      context,
      SheetShell(
        title: 'رسائل واتساب الجاهزة',
        children: kWaTemplates
            .map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AppBadge(label: t.label, tone: 'ok', icon: 'whatsapp'),
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                ctx.toast('تم إرسال الرسالة');
                              },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const AppIcon('send', size: 15, color: AppColors.ok700),
                                const SizedBox(width: 3),
                                Text('إرسال',
                                    style: AppType.base(size: 12.5, weight: FontWeight.w800, color: AppColors.ok700)),
                              ]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(t.text,
                            style: AppType.base(size: 13, weight: FontWeight.w500, color: AppColors.ink700, height: 1.6)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// Local toggle used in alert settings (decorative — persists in-session only).
class _SettingsSwitch extends StatefulWidget {
  const _SettingsSwitch({required this.initial});
  final bool initial;
  @override
  State<_SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<_SettingsSwitch> {
  late bool on = widget.initial;
  @override
  Widget build(BuildContext context) =>
      AppSwitch(checked: on, onChanged: (v) => setState(() => on = v));
}

// ───────────────────────────── Years & Months ─────────────────────────────

class YearsScreen extends StatefulWidget {
  const YearsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<YearsScreen> createState() => _YearsScreenState();
}

class _YearsScreenState extends State<YearsScreen> {
  late int year = kYears.isNotEmpty ? kYears.last : DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final units = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').length;
    final years = kYears.isNotEmpty ? kYears : [year];

    return ScreenScaffold(
      header: AppHeader(
        title: 'الترحيل السنوي',
        subtitle: 'متابعة الدفع شهرياً',
        onBack: ctx.back,
        right: RoundBtn(
            icon: 'refresh',
            // Years are derived automatically from recorded payments — don't
            // claim a fake "year added".
            onTap: () => ctx.toast('تُضاف السنوات تلقائياً عند تسجيل دفعات في سنة جديدة', tone: 'info')),
      ),
      nav: ctx.adminNav,
      children: [
        Row(
          children: years.map((y) {
            final on = year == y;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: y != years.last ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => year = y),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? AppColors.navy700 : AppColors.surface,
                      border: Border.all(color: on ? AppColors.navy700 : AppColors.line2),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: on ? AppShadows.sm : null,
                    ),
                    child: NumText('$y',
                        style: AppType.num(size: 14, weight: FontWeight.w800, color: on ? Colors.white : AppColors.ink600)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        AppCard(
          color: AppColors.gold50,
          borderColor: AppColors.gold200,
          child: Row(
            children: [
              const IconChip(icon: 'refresh', tone: 'gold', size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('الرصيد المُرحّل من ${year - 1}', style: AppType.base(size: 13.5, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('افتتاحي للسنة الحالية',
                        style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NumText(fmtUSD(kOpeningBalance), style: AppType.num(size: 16, weight: FontWeight.w800, color: AppColors.gold700)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionTitle(text: 'حالة الدفع الشهرية'),
        AppCard(
          pad: 6,
          child: Column(
            children: List.generate(kMonthsGrid.length, (i) {
              final m = kMonthsGrid[i];
              // Guard against total == 0 (fresh building): int / 0 → Infinity/NaN
              // and .round() would throw, crashing the whole screen.
              final pct = m.total > 0 ? ((m.paid / m.total) * 100).round().clamp(0, 100) : 0;
              final tone = pct == 100 ? 'ok' : pct == 0 ? 'late' : 'warn';
              final col = {'ok': AppColors.ok, 'late': AppColors.late, 'warn': AppColors.warn}[tone]!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                decoration: BoxDecoration(
                  border: i < kMonthsGrid.length - 1
                      ? const Border(bottom: BorderSide(color: AppColors.line))
                      : null,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(monthLabelNum(m.m), style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.ink700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pct / 100, // guarded above (no divide-by-zero)
                          minHeight: 8,
                          backgroundColor: AppColors.navy50,
                          valueColor: AlwaysStoppedAnimation(col),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    NumText('${m.paid}/${m.total}',
                        style: AppType.num(size: 12, weight: FontWeight.w700, color: AppColors.ink600)),
                    const SizedBox(width: 8),
                    AppBadge(label: pct == 100 ? 'مكتمل' : pct == 0 ? 'لم يبدأ' : '$pct%', tone: tone, small: true),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('$units ${ctx.res ? 'شقة' : 'وحدة'} فعّالة في $year',
              style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink400)),
        ),
      ],
    );
  }
}

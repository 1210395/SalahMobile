// عمارتي — Admin: Payments, Expenses, Workers, Parking.

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../common.dart';
import '../api/repository.dart';
import 'admin_reports.dart' show pendingReportTab;

// ───────────────────────────── Payments ─────────────────────────────

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String month = 'all';
  late int year = kYears.isNotEmpty ? kYears.last : DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final byYear = kPayments.where((p) => p.year == year).toList();
    final total = byYear.fold<int>(0, (s, p) => s + p.amount);
    final list = month == 'all'
        ? byYear
        : byYear.where((p) => p.month == int.parse(month)).toList();
    // Numbered month label for the hero (or the whole year when "all").
    final heroPeriod =
        month == 'all' ? '$year' : '${monthLabelNum(int.parse(month))} $year';

    return ScreenScaffold(
      header: AppHeader(
        title: 'الإيرادات',
        subtitle: 'الإيرادات والتحصيل',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'filter', onTap: () {}),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'دفعة جديدة', onTap: () => _openAdd(ctx)),
      children: [
        HeroBanner(
          gradient: const [AppColors.ok700, Color(0xFF0F5E3E)],
          shadow: const [BoxShadow(color: Color(0x52157A52), offset: Offset(0, 10), blurRadius: 26)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إجمالي التحصيل — $heroPeriod',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: Colors.white70)),
              const SizedBox(height: 6),
              NumText(fmtUSD(total),
                  style: AppType.num(size: 28, weight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 12),
              Row(children: [
                AppBadge(label: '${byYear.length} دفعة', tone: 'ok', icon: 'checkCircle'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('متوسط ${fmtUSD(byYear.isEmpty ? 0 : (total / byYear.length).round())}',
                      style: AppType.base(size: 12, weight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            // Numbered month filter — all 12 months reachable (scrollable).
            Expanded(
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 13,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (_, i) {
                    final val = i == 0 ? 'all' : '${i - 1}';
                    final label = i == 0 ? 'الكل' : monthLabelNum(i - 1);
                    final on = month == val;
                    return GestureDetector(
                      onTap: () => setState(() => month = val),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? AppColors.navy700 : AppColors.surface,
                          border: Border.all(color: on ? AppColors.navy700 : AppColors.line2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(label,
                            style: AppType.base(
                                size: 12.5, weight: FontWeight.w700, color: on ? Colors.white : AppColors.ink600)),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            _YearChip(
              year: year,
              onTap: () => _pickYear(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          pad: 6,
          child: list.isEmpty
              ? const EmptyState(icon: 'wallet', title: 'لا توجد دفعات', sub: 'لا توجد دفعات في هذا الشهر')
              : Column(
                  children: List.generate(list.length, (i) {
                    final p = list[i];
                    return GestureDetector(
                      onTap: () => _openDetail(ctx, p),
                      onLongPress: () => _openEdit(ctx, p),
                      child: ListRow(
                        leading: const IconChip(icon: 'wallet', tone: 'ok', size: 42),
                        title: p.name,
                        sub: 'وحدة ${p.unit} · ${_kindNoGuard(p.kind)} · ${p.method}',
                        dividerBelow: i < list.length - 1,
                        trailing: _amountTrailing('+${fmtUSD(p.amount)}', p.date, AppColors.ok700),
                      ),
                    );
                  }),
                ),
        ),
      ],
    );
  }

  void _openAdd(Ctx ctx) => showAppSheet(context, AddPaymentSheet(ctx: ctx));

  void _openEdit(Ctx ctx, Payment p) {
    final f = {'amount': '${p.amount}', 'kind': p.kind, 'method': p.method};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل الدفعة',
          footer: AppButton(
            label: 'حفظ التعديلات',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updatePayment(ctx.btype, p.id, {
                  'amount': int.tryParse(f['amount']!.trim()) ?? p.amount,
                  'kind': f['kind'],
                  'method': f['method'],
                });
                await ctx.reload();
                ctx.toast('تم حفظ التعديلات');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Text('${p.name} · وحدة ${p.unit}',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink600)),
            const SizedBox(height: 12),
            Field(label: 'المبلغ', icon: 'wallet', value: f['amount']!, ltr: true, keyboardType: TextInputType.number, onChanged: (v) => f['amount'] = v),
            Field(label: 'النوع', icon: 'receipt', value: f['kind']!, onChanged: (v) => f['kind'] = v),
            Field(label: 'طريقة الدفع', icon: 'wallet', value: f['method']!, onChanged: (v) => f['method'] = v),
            const SizedBox(height: 6),
            AppButton(
              label: 'حذف الدفعة',
              variant: BtnVariant.outline,
              full: true,
              icon: 'trash',
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await Api.I.deletePayment(ctx.btype, p.id);
                  await ctx.reload();
                  ctx.toast('تم حذف الدفعة');
                } catch (e) {
                  ctx.toast(apiErrorText(e), tone: 'late');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// List picker over [kYears] — replaces the old cycling chip.
  void _pickYear() {
    final years = kYears;
    showAppSheet(
      context,
      SheetShell(
        title: 'اختر السنة',
        children: [
          for (final y in years)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _YearPickRow(
                year: y,
                selected: y == year,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => year = y);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Open a read-only detail sheet for one payment with تعديل / حذف / سند قبض.
  void _openDetail(Ctx ctx, Payment p) {
    final u = _unitFor(ctx, p.unit);
    final unitWord = ctx.res ? 'الشقة' : 'المحل';
    showAppSheet(
      context,
      SheetShell(
        title: 'تفاصيل الدفعة',
        children: [
          DetailGrid(rows: [
            DetailRow('user', 'الساكن', p.name),
            DetailRow('building', unitWord, p.unit),
            DetailRow('wallet', 'المبلغ', fmtUSD(p.amount)),
            DetailRow('receipt', 'البند', _kindNoGuard(p.kind)),
            DetailRow('calendar', 'الشهر', '${monthLabelNum(p.month)} ${p.year}'),
            DetailRow('calendar', 'التاريخ', p.date, ltr: true),
            DetailRow('dollar', 'طريقة الدفع', p.method),
          ]),
          const SizedBox(height: 12),
          AppButton(
            label: 'كل دفعات ${ctx.res ? 'هذه الشقة' : 'هذا المحل'}',
            full: true,
            size: BtnSize.lg,
            variant: BtnVariant.outline,
            icon: 'list',
            onTap: () {
              Navigator.of(context).pop();
              _openUnitPayments(ctx, p.unit, p.name);
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'سند قبض',
            full: true,
            size: BtnSize.lg,
            icon: 'receipt',
            onTap: () {
              Navigator.of(context).pop();
              _openReceipt(ctx, p, u);
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'تعديل',
            variant: BtnVariant.outline,
            full: true,
            icon: 'edit',
            onTap: () {
              Navigator.of(context).pop();
              _openEdit(ctx, p);
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'حذف',
            variant: BtnVariant.outline,
            full: true,
            icon: 'trash',
            onTap: () async {
              Navigator.of(context).pop();
              try {
                await Api.I.deletePayment(ctx.btype, p.id);
                await ctx.reload();
                ctx.toast('تم حذف الدفعة');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
        ],
      ),
    );
  }

  /// Every payment recorded for one unit (newest first) + a running total.
  void _openUnitPayments(Ctx ctx, String unitNo, String name) {
    final list = kPayments.where((x) => x.unit == unitNo).toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        return byYear != 0 ? byYear : b.month.compareTo(a.month);
      });
    final total = list.fold<int>(0, (s, x) => s + x.amount);
    showAppSheet(
      context,
      SheetShell(
        title: 'كل الدفعات — $name',
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text('${list.length} دفعة بإجمالي ${fmtUSD(total)} لـ '
                '${ctx.res ? 'الشقة' : 'المحل'} $unitNo.',
                style: AppType.base(
                    size: 13, weight: FontWeight.w600, color: AppColors.ink600, height: 1.5)),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('لا توجد دفعات مسجّلة.',
                  textAlign: TextAlign.center,
                  style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink500)),
            )
          else
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.line, width: 1.5),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      const AppIcon('wallet', size: 18, color: AppColors.navy600),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${monthLabelNum(x.month)} ${x.year}',
                                style: AppType.base(size: 13.5, weight: FontWeight.w700)),
                            Text(_kindNoGuard(x.kind),
                                style: AppType.base(
                                    size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
                          ],
                        ),
                      ),
                      NumText(fmtUSD(x.amount),
                          style: AppType.num(size: 13.5, weight: FontWeight.w800, color: AppColors.ok)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Receipt (سند قبض): preview + share via WhatsApp / save as PDF.
  void _openReceipt(Ctx ctx, Payment p, Unit? u) {
    final unitWord = ctx.res ? 'شقة' : 'محل';
    final text = _receiptText(p, unitWord);
    showAppSheet(
      context,
      SheetShell(
        title: 'سند قبض',
        footer: AppButton(
          label: 'إرسال عبر واتساب',
          full: true,
          size: BtnSize.lg,
          icon: 'whatsapp',
          onTap: () async {
            Navigator.of(context).pop();
            final ph = (u?.phone ?? '').trim();
            await shareViaWhatsApp(phone: (ph.isEmpty || ph == '—') ? null : ph, text: text);
          },
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(text,
                style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink700, height: 1.7)),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'حفظ / طباعة PDF',
            variant: BtnVariant.outline,
            full: true,
            icon: 'download',
            onTap: () async {
              try {
                await _receiptPdf(p, unitWord);
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
        ],
      ),
    );
  }

  // Plain-text سند قبض — date, resident, unit, amount, kind, method.
  String _receiptText(Payment p, String unitWord) {
    return [
      'سند قبض — عمارتي',
      'التاريخ: ${p.date}',
      'الساكن: ${p.name}',
      'ال$unitWord: ${p.unit}',
      'المبلغ: ${fmtUSD(p.amount)}',
      'البند: ${_kindNoGuard(p.kind)}',
      'الشهر: ${monthLabelNum(p.month)} ${p.year}',
      'طريقة الدفع: ${p.method}',
      'استلمنا المبلغ أعلاه بالكامل، وشكراً لكم.',
    ].join('\n');
  }

  // Printable RTL/Cairo سند قبض. Local to this file; opens the share/print sheet.
  Future<void> _receiptPdf(Payment p, String unitWord) async {
    final base = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    pw.Widget row(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(k, style: pw.TextStyle(font: bold, fontSize: 12, color: PdfColors.grey700)),
              pw.Text(v, style: pw.TextStyle(font: base, fontSize: 12)),
            ],
          ),
        );
    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a5,
        theme: pw.ThemeData.withFont(base: base, bold: bold),
        margin: const pw.EdgeInsets.all(28),
        build: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('عمارتي',
                style: pw.TextStyle(font: bold, fontSize: 22, color: PdfColor.fromInt(0xFF232858))),
            pw.SizedBox(height: 2),
            pw.Text('سند قبض', style: pw.TextStyle(font: base, fontSize: 13, color: PdfColors.grey600)),
            pw.Divider(color: PdfColor.fromInt(0xFFC2A24E), thickness: 1.2),
            pw.SizedBox(height: 10),
            row('التاريخ', p.date),
            row('الساكن', p.name),
            row('ال$unitWord', p.unit),
            row('المبلغ', fmtUSD(p.amount)),
            row('البند', _kindNoGuard(p.kind)),
            row('الشهر', '${monthLabelNum(p.month)} ${p.year}'),
            row('طريقة الدفع', p.method),
            pw.SizedBox(height: 16),
            pw.Text('استلمنا المبلغ أعلاه بالكامل، وشكراً لكم.',
                style: pw.TextStyle(font: base, fontSize: 12, color: PdfColors.grey700)),
          ],
        ),
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: 'receipt.pdf');
  }

  // The unit behind a payment (for the resident phone on receipts), if loaded.
  Unit? _unitFor(Ctx ctx, String no) {
    final list = ctx.res ? kApartments : kShops;
    for (final u in list) {
      if (u.no == no) return u;
    }
    return null;
  }
}

// Drop any guard-fee ("اجرة/أجرة الحارس") segment from a payment kind label (#11).
String _kindNoGuard(String kind) {
  final parts = kind
      .split('+')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !s.contains('الحارس'))
      .toList();
  return parts.isEmpty ? kind.trim() : parts.join(' + ');
}

Widget _amountTrailing(String amount, String date, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        NumText(amount, style: AppType.num(size: 14.5, weight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        NumText(date, style: AppType.num(size: 10.5, weight: FontWeight.w600, color: AppColors.ink400)),
      ],
    );

class AddPaymentSheet extends StatefulWidget {
  const AddPaymentSheet({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<AddPaymentSheet> {
  // Default ONLY the monthly subscription ON; every other بند starts OFF.
  late final Map<String, bool> types = {
    for (final t in kPayTypes) t.id: _isSub(t),
  };
  static bool _isSub(PayType t) => t.id == 'sub' || t.label.contains('الاشتراك الشهري');
  Object unit = '';
  Object method = 'نقداً';
  // Months this payment covers — multi-select (one payment row saved per month).
  // Defaults to the current calendar month.
  late final Set<int> payMonths = {DateTime.now().month - 1};
  // Per-type override prices captured via the zero-fee popup (id → amount), so a
  // بند whose stored fee is 0 can be priced inline without re-opening settings.
  final Map<String, int> priceOverride = {};
  // Currency the amount is entered in + its rate to the building's base currency.
  late Object currency = activeCurrency;
  String rateStr = '';
  String dateIso = todayIso();
  // Editable total: seeded from the sum of ON items, manual override allowed.
  String amountStr = '';
  bool amountTouched = false;
  // Target: one unit / all units / a group of units.
  String target = 'one';
  final Set<String> selUnits = {};
  // Custom "Other" payment line.
  bool otherOn = false;
  String otherLabel = '';
  String otherAmount = '';

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    // Sum of the currently-ON بنود (+ the optional "أخرى" amount) — this seeds
    // the editable total field unless the admin has overridden it manually.
    int feeOf(PayType t) => priceOverride[t.id] ?? t.amount;
    final itemsSum = kPayTypes.where((t) => types[t.id] == true).fold<int>(0, (s, t) => s + feeOf(t)) +
        (otherOn ? (int.tryParse(otherAmount) ?? 0) : 0);
    final defaultStr = '$itemsSum';
    // The amount that actually gets saved (manual override wins).
    final total = amountTouched ? (int.tryParse(amountStr.trim()) ?? 0) : itemsSum;
    final unitList = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    final units = unitList.map((u) => SelectOption(u.no, '${u.no} — ${u.resident}')).toList();
    final unitWord = ctx.res ? 'شقة' : 'محل';

    String payIcon(String id) =>
        {'sub': 'wallet', 'elev': 'elevator', 'guard': 'shield'}[id] ?? 'parking';

    final sameCur = currency == activeCurrency;
    final rate = sameCur ? 1.0 : (double.tryParse(rateStr) ?? 0);
    final rateOk = sameCur || rate > 0;
    // The total expressed in the building's base currency (exchange applied) —
    // this is what reflects on the dashboard/reports, so the button shows it.
    final baseTotal = sameCur ? total : (total * rate).round();
    final canSave = ((target == 'one' && unit != '') ||
            (target == 'group' && selUnits.isNotEmpty) ||
            target == 'all') &&
        rateOk &&
        payMonths.isNotEmpty &&
        total > 0;

    return SheetShell(
      title: 'تسجيل دفعة جديدة',
      footer: AppButton(
        label: 'حفظ الدفعة · ${fmtMoney(baseTotal, activeCurrency)}',
        full: true,
        size: BtnSize.lg,
        icon: 'check',
        disabled: !canSave,
        onTap: () => _save(ctx, total, unitList),
      ),
      children: [
        // Target selector — all / one / group.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Segmented(
            small: true,
            value: target,
            onChanged: (v) => setState(() => target = v as String),
            options: [
              SegOption('one', ctx.res ? 'شقة واحدة' : 'محل واحد'),
              const SegOption('all', 'الجميع'),
              const SegOption('group', 'مجموعة'),
            ],
          ),
        ),
        if (target == 'one')
          SelectField(
            label: '$unitWord / الساكن',
            icon: 'building',
            options: units,
            value: unit == '' ? null : unit,
            onChanged: (v) => setState(() => unit = v),
          ),
        if (target == 'all')
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _infoNote(
                'سيتم تسجيل الدفعة لجميع ${ctx.res ? 'الشقق' : 'المحلات'} الفعّالة (${unitList.length}).'),
          ),
        if (target == 'group') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('اختر ${ctx.res ? 'الشقق' : 'المحلات'} (${selUnits.length})',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unitList.map((u) {
                final on = selUnits.contains(u.no);
                // Show the resident name (fallback to the unit number).
                final label = u.resident.trim().isNotEmpty ? u.resident : u.no;
                return GestureDetector(
                  onTap: () => setState(() => on ? selUnits.remove(u.no) : selUnits.add(u.no)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: on ? AppColors.navy700 : AppColors.surface,
                      border: Border.all(color: on ? AppColors.navy700 : AppColors.line2, width: 1.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label,
                        style: AppType.base(
                            size: 12.5, weight: FontWeight.w700, color: on ? Colors.white : AppColors.ink600)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text('بنود الدفع',
              style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
        ),
        ...kPayTypes.map((t) {
          final on = types[t.id] == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: on ? AppColors.navy50 : AppColors.surface,
                border: Border.all(color: on ? AppColors.navy100 : AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  AppIcon(payIcon(t.id), size: 20, color: on ? AppColors.navy700 : AppColors.ink400),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Text(t.label, style: AppType.base(size: 14, weight: FontWeight.w700)),
                          if (t.opt)
                            Text(' (اختياري)',
                                style: AppType.base(size: 11, weight: FontWeight.w600, color: AppColors.ink400)),
                        ]),
                        NumText(fmtUSD(feeOf(t)),
                            style: AppType.num(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                      ],
                    ),
                  ),
                  AppSwitch(
                      checked: on,
                      onChanged: (v) async {
                        // Turning ON a بند whose fee is 0 → ask for its price +
                        // service description first, and persist it as the new
                        // default (per client note: handle zero-fee checkboxes).
                        if (v && feeOf(t) <= 0) {
                          await _promptZeroFee(ctx, t);
                          return;
                        }
                        setState(() => types[t.id] = v);
                      }),
                ],
              ),
            ),
          );
        }),
        // Custom "Other" line — admin enters the type name and amount.
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: otherOn ? AppColors.navy50 : AppColors.surface,
              border: Border.all(color: otherOn ? AppColors.navy100 : AppColors.line, width: 1.5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              children: [
                Row(children: [
                  AppIcon('receipt', size: 20, color: otherOn ? AppColors.navy700 : AppColors.ink400),
                  const SizedBox(width: 11),
                  Expanded(child: Text('أخرى', style: AppType.base(size: 14, weight: FontWeight.w700))),
                  AppSwitch(checked: otherOn, onChanged: (v) => setState(() => otherOn = v)),
                ]),
                if (otherOn) ...[
                  const SizedBox(height: 10),
                  Field(
                      label: 'نوع الدفعة',
                      placeholder: 'مثال: غرامة تأخير',
                      marginBottom: 10,
                      onChanged: (v) => setState(() => otherLabel = v)),
                  Field(
                      label: 'المبلغ',
                      ltr: true,
                      suffix: '\$',
                      placeholder: '0',
                      keyboardType: TextInputType.number,
                      marginBottom: 0,
                      onChanged: (v) => setState(() => otherAmount = v)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Editable total — defaults to the sum of the ON بنود, override allowed.
        // The ValueKey re-seeds the field from the sum while it's untouched.
        Field(
          key: ValueKey(amountTouched ? 'manual' : defaultStr),
          label: 'المبلغ الإجمالي',
          icon: 'wallet',
          value: amountTouched ? amountStr : defaultStr,
          ltr: true,
          keyboardType: TextInputType.number,
          marginBottom: 8,
          onChanged: (v) => setState(() {
            amountTouched = true;
            amountStr = v;
          }),
        ),
        // Carry-over note — surplus rolls forward, shortfall stays due (#9).
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _infoNote(
              'المبلغ الزائد عن الاشتراك الشهري يُرحَّل كرصيد للأشهر التالية، '
              'والنقص يبقى مبلغاً مستحقاً.'),
        ),
        const SizedBox(height: 3),
        // Currency + exchange rate (when paying in a currency other than the base).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectField(
                label: 'العملة',
                icon: 'dollar',
                options: [for (final c in kCurrencyCodes) SelectOption(c, '$c (${currencySymbol(c)})')],
                value: currency,
                onChanged: (v) => setState(() => currency = v),
              ),
            ),
            if (currency != activeCurrency) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Field(
                    label: 'سعر الصرف → $activeCurrency',
                    icon: 'refresh',
                    placeholder: '3.75',
                    ltr: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => setState(() => rateStr = v)),
              ),
            ],
          ],
        ),
        if (currency != activeCurrency)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _infoNote(
                'المبلغ ${fmtMoney(total, currency as String)} يعادل '
                '${fmtMoney((total * (double.tryParse(rateStr) ?? 0)).round(), activeCurrency)} '
                '($activeCurrency) بعملة المبنى.'),
          ),
        // Months covered — multi-select. One payment row is saved per month, so
        // ticking 3 months records the bill three times for the chosen unit(s).
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text('الأشهر المشمولة (${payMonths.length})',
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => payMonths
                  ..clear()
                  ..add(DateTime.now().month - 1)),
                child: Text('الشهر الحالي',
                    style: AppType.base(size: 12, weight: FontWeight.w700, color: AppColors.navy600)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 12; i++)
                GestureDetector(
                  onTap: () => setState(() =>
                      payMonths.contains(i) ? payMonths.remove(i) : payMonths.add(i)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: payMonths.contains(i) ? AppColors.navy700 : AppColors.surface,
                      border: Border.all(
                          color: payMonths.contains(i) ? AppColors.navy700 : AppColors.line2,
                          width: 1.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(monthLabelNum(i),
                        style: AppType.base(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: payMonths.contains(i) ? Colors.white : AppColors.ink600)),
                  ),
                ),
            ],
          ),
        ),
        DateField(
          label: 'تاريخ الدفع',
          value: dateIso,
          onChanged: (v) => setState(() => dateIso = v),
        ),
        SelectField(
          label: 'طريقة الدفع',
          icon: 'dollar',
          options: const [
            SelectOption('نقداً', 'نقداً'),
            SelectOption('تحويل بنكي', 'تحويل بنكي'),
            SelectOption('محفظة رقمية', 'محفظة رقمية'),
            SelectOption('شيك', 'شيك'),
          ],
          value: method,
          onChanged: (v) => setState(() => method = v),
        ),
        const Field(label: 'ملاحظات', placeholder: 'ملاحظة اختيارية…'),
      ],
    );
  }

  /// A بند whose stored fee is 0 prompts for a price + service description when
  /// switched on; the price is saved as the new default (server) and applied to
  /// this payment immediately.
  Future<void> _promptZeroFee(Ctx ctx, PayType t) async {
    String priceStr = '';
    String serviceDesc = '';
    await showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تحديد سعر ${t.label}',
          footer: AppButton(
            label: 'حفظ كقيمة افتراضية',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: (int.tryParse(priceStr) ?? 0) <= 0,
            onTap: () async {
              final price = int.tryParse(priceStr) ?? 0;
              Navigator.of(sheetCtx).pop();
              setState(() {
                priceOverride[t.id] = price;
                types[t.id] = true;
              });
              if (t.dbId > 0) {
                try {
                  await Api.I.updatePayType(t.dbId, {'amount': price});
                  await ctx.reload();
                } catch (_) {}
              }
              final extra = serviceDesc.trim().isEmpty ? '' : ' — ${serviceDesc.trim()}';
              ctx.toast('تم تحديد سعر ${t.label}: ${fmtUSD(price)}$extra');
            },
          ),
          children: [
            _infoNote('قيمة هذا البند 0 حالياً. حدّد سعره ووصف الخدمة؛ سيُحفظ '
                'كقيمة افتراضية للمرات القادمة.'),
            const SizedBox(height: 12),
            Field(
                label: 'السعر',
                icon: 'wallet',
                placeholder: '0',
                ltr: true,
                keyboardType: TextInputType.number,
                onChanged: (v) => setS(() => priceStr = v)),
            AppTextArea(
                label: 'وصف الخدمة (اختياري)',
                placeholder: 'مثال: صيانة شاملة شهرية للمصعد',
                onChanged: (v) => serviceDesc = v),
          ],
        ),
      ),
    );
  }

  /// POST one payment per target unit, then refresh the bundle.
  Future<void> _save(Ctx ctx, int total, List<Unit> unitList) async {
    final targets = target == 'all'
        ? unitList.map((u) => u.no).toList()
        : target == 'group'
            ? selUnits.toList()
            : [unit as String];
    final labels = [
      for (final t in kPayTypes)
        if (types[t.id] == true) t.label,
      if (otherOn && otherLabel.trim().isNotEmpty) otherLabel.trim(),
    ];
    final kind = labels.isEmpty ? 'دفعة' : labels.join(' + ');
    final months = payMonths.isEmpty ? {DateTime.now().month - 1} : payMonths;
    final date = dateIso;
    // Year follows the picked date so the payment lands in the right report year.
    final year = int.tryParse(date.split('-').first) ?? DateTime.now().year;
    final cur = currency as String;
    final sameCur = cur == activeCurrency;
    final rate = sameCur ? 1.0 : (double.tryParse(rateStr) ?? 1);
    // Base (building-currency) amount the row stores. Server is authoritative too,
    // but we send the converted value so the contract is explicit.
    final baseAmount = sameCur ? total : (total * rate).round();
    final unitWord = ctx.res ? 'شقة' : 'محل';
    Navigator.of(context).pop();
    try {
      for (final no in targets) {
        Unit? u;
        for (final x in unitList) {
          if (x.no == no) { u = x; break; }
        }
        // One row per covered month.
        for (final m in months) {
          await Api.I.createPayment(ctx.btype, {
            'unit_no': no,
            if (u != null && u.resident.trim().isNotEmpty) 'name': u.resident,
            'amount': baseAmount,
            'original_amount': total,
            'currency': cur,
            'exchange_rate': rate,
            'kind': kind,
            'month': m,
            'year': year,
            'date': date,
            'method': method as String,
          });
        }
      }
      await ctx.reload();
      final who = target == 'all'
          ? (ctx.res ? 'جميع الشقق' : 'جميع المحلات')
          : target == 'group'
              ? '${targets.length} $unitWord'
              : '$unitWord $unit';
      final mLabel = months.length == 1 ? 'شهر واحد' : '${months.length} أشهر';
      ctx.toast('تم تسجيل دفعة بقيمة ${fmtMoney(total, cur)} لـ $who عن $mLabel');
    } catch (_) {
      ctx.toast('تعذّر حفظ الدفعة، تحقّق من الاتصال', tone: 'late');
    }
  }

  Widget _infoNote(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration:
            BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink600, height: 1.5)),
      );
}

// ───────────────────────────── Expenses ─────────────────────────────

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String cat = 'all';

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final total = kExpenses.fold<int>(0, (s, e) => s + e.amount);
    final list = cat == 'all' ? kExpenses : kExpenses.where((e) => e.cat == cat).toList();
    final cats = ['all', ...kExpCats];

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة المصروفات',
        subtitle: 'نفقات المبنى',
        onBack: () => ctx.go('home'),
        right: RoundBtn(
          icon: 'pie',
          onTap: () {
            pendingReportTab = 'expense';
            ctx.go('reports');
          },
        ),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'مصروف جديد', onTap: () => _openAdd(ctx)),
      children: [
        AppButton(
          label: 'الانتقال إلى تقرير المصروفات',
          variant: BtnVariant.outline,
          full: true,
          icon: 'pie',
          onTap: () {
            pendingReportTab = 'expense';
            ctx.go('reports');
          },
        ),
        const SizedBox(height: 12),
        HeroBanner(
          gradient: const [AppColors.late700, Color(0xFF8C2019)],
          shadow: const [BoxShadow(color: Color(0x4DAF2E26), offset: Offset(0, 10), blurRadius: 26)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إجمالي المصروفات — مايو 2026',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: Colors.white70)),
              const SizedBox(height: 6),
              NumText(fmtUSD(total),
                  style: AppType.num(size: 28, weight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cats.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final c = cats[i];
              final on = cat == c;
              return GestureDetector(
                onTap: () => setState(() => cat = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.navy700 : AppColors.surface,
                    border: Border.all(color: on ? AppColors.navy700 : AppColors.line2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(c == 'all' ? 'الكل' : c,
                      style: AppType.base(
                          size: 12.5, weight: FontWeight.w700, color: on ? Colors.white : AppColors.ink600)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          pad: 6,
          child: Column(
            children: List.generate(list.length, (i) {
              final e = list[i];
              return GestureDetector(
                onLongPress: () => _openEdit(ctx, e),
                child: ListRow(
                  leading: IconChip(icon: e.icon, tone: e.tone, size: 42),
                  title: e.supplier,
                  sub: '${e.cat} · ${e.desc}',
                  dividerBelow: i < list.length - 1,
                  trailing: _amountTrailing('-${fmtUSD(e.amount)}', e.date, AppColors.late700),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  void _openEdit(Ctx ctx, Expense e) {
    final f = {'supplier': e.supplier, 'amount': '${e.amount}', 'cat': e.cat};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل المصروف',
          footer: AppButton(
            label: 'حفظ التعديلات',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updateExpense(ctx.btype, e.id, {
                  'supplier': f['supplier'],
                  'amount': int.tryParse(f['amount']!.trim()) ?? e.amount,
                  'cat': f['cat'],
                });
                await ctx.reload();
                ctx.toast('تم حفظ التعديلات');
              } catch (err) {
                ctx.toast(apiErrorText(err), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'المورّد', icon: 'receipt', value: f['supplier']!, onChanged: (v) => f['supplier'] = v),
            Field(label: 'المبلغ', icon: 'wallet', value: f['amount']!, ltr: true, keyboardType: TextInputType.number, onChanged: (v) => f['amount'] = v),
            Field(label: 'التصنيف', icon: 'grid', value: f['cat']!, onChanged: (v) => f['cat'] = v),
            const SizedBox(height: 6),
            AppButton(
              label: 'حذف المصروف',
              variant: BtnVariant.outline,
              full: true,
              icon: 'trash',
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await Api.I.deleteExpense(ctx.btype, e.id);
                  await ctx.reload();
                  ctx.toast('تم حذف المصروف');
                } catch (err) {
                  ctx.toast(apiErrorText(err), tone: 'late');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Icon/tone per expense category (matches the seed styling).
  static const _expMeta = {
    'مصعد': ['elevator', 'navy'],
    'نظافة': ['broom', 'ok'],
    'كهرباء': ['alert', 'warn'],
    'صيانة': ['wrench', 'credit'],
    'أخرى': ['receipt', 'gold'],
  };

  void _openAdd(Ctx ctx) {
    final f = {
      'cat': kExpCats.first,
      'supplier': '',
      'amount': '',
      'date': todayIso(),
      'desc': '',
      'currency': activeCurrency,
      'rate': '',
    };
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) {
          final cur = f['currency']!;
          final sameCur = cur == activeCurrency;
          final rate = sameCur ? 1.0 : (double.tryParse(f['rate']!) ?? 0);
          final original = int.tryParse(f['amount']!) ?? 0;
          final baseAmount = sameCur ? original : (original * rate).round();
          final rateOk = sameCur || rate > 0;
          return SheetShell(
            title: 'تسجيل مصروف',
            footer: AppButton(
              label: 'حفظ المصروف · ${fmtMoney(baseAmount, activeCurrency)}',
              full: true,
              size: BtnSize.lg,
              icon: 'check',
              disabled: f['supplier']!.trim().isEmpty || original <= 0 || !rateOk,
              onTap: () async {
                final meta = _expMeta[f['cat']] ?? const ['receipt', 'gold'];
                Navigator.of(sheetCtx).pop();
                try {
                  await Api.I.createExpense(ctx.btype, {
                    'cat': f['cat'],
                    'icon': meta[0],
                    'tone': meta[1],
                    'supplier': f['supplier']!.trim(),
                    'amount': baseAmount,
                    'original_amount': original,
                    'currency': cur,
                    'exchange_rate': rate,
                    'date': f['date'],
                    'description': f['desc'],
                  });
                  await ctx.reload();
                  ctx.toast('تم تسجيل المصروف');
                } catch (_) {
                  ctx.toast('تعذّر حفظ المصروف، تحقّق من الاتصال', tone: 'late');
                }
              },
            ),
            children: [
              SelectField(
                label: 'التصنيف',
                icon: 'grid',
                options: [for (final c in kExpCats) SelectOption(c, c)],
                value: f['cat'],
                onChanged: (v) => setS(() => f['cat'] = v as String),
              ),
              Field(
                  label: 'المورّد / الجهة',
                  icon: 'store',
                  placeholder: 'اسم المورّد',
                  onChanged: (v) => setS(() => f['supplier'] = v)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: Field(
                          label: 'المبلغ',
                          icon: 'dollar',
                          placeholder: '0',
                          ltr: true,
                          suffix: currencySymbol(cur),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setS(() => f['amount'] = v))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: DateField(
                          label: 'التاريخ',
                          value: f['date']!,
                          onChanged: (v) => setS(() => f['date'] = v))),
                ],
              ),
              // Currency + exchange rate (mirrors payments) so a NIS/other-currency
              // expense is stored converted, not silently kept as dollars.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectField(
                      label: 'العملة',
                      icon: 'dollar',
                      options: [for (final c in kCurrencyCodes) SelectOption(c, '$c (${currencySymbol(c)})')],
                      value: cur,
                      onChanged: (v) => setS(() => f['currency'] = v as String),
                    ),
                  ),
                  if (!sameCur) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Field(
                          label: 'سعر الصرف → $activeCurrency',
                          icon: 'refresh',
                          placeholder: '3.75',
                          ltr: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => setS(() => f['rate'] = v)),
                    ),
                  ],
                ],
              ),
              if (!sameCur)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                    child: Text('المبلغ ${fmtMoney(original, cur)} يعادل '
                        '${fmtMoney(baseAmount, activeCurrency)} بعملة المبنى.',
                        style: AppType.base(
                            size: 13, weight: FontWeight.w600, color: AppColors.ink600, height: 1.5)),
                  ),
                ),
              AppTextArea(
                  label: 'الوصف',
                  placeholder: 'تفاصيل المصروف…',
                  onChanged: (v) => f['desc'] = v),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Workers ─────────────────────────────

class WorkersScreen extends StatelessWidget {
  const WorkersScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      header: AppHeader(
        title: 'العمال وشركات النظافة',
        subtitle: '${kWorkers.length} جهة مسجّلة',
        onBack: () => ctx.go('home'),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'إضافة', onTap: () => _openAdd(context, ctx)),
      children: [
        ...kWorkers.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                pad: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const IconChip(icon: 'broom', tone: 'ok', size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(w.name, style: AppType.base(size: 14.5, weight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('${w.type} · ${w.phone}',
                                  style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppBadge(label: w.cycle, tone: 'navy'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      MiniStat(label: 'المبلغ', value: fmtUSD(w.amount), tone: 'navy'),
                      const SizedBox(width: 8),
                      MiniStat(label: 'آخر دفعة', value: w.last, tone: 'ok', num: true),
                      const SizedBox(width: 8),
                      MiniStat(label: 'الاستحقاق القادم', value: w.next, tone: 'late', num: true),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: AppButton(
                            label: 'اتصال',
                            variant: BtnVariant.ghost,
                            size: BtnSize.sm,
                            full: true,
                            icon: 'phone',
                            onTap: () => ctx.toast('اتصال…', tone: 'info')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                            label: 'دفع',
                            size: BtnSize.sm,
                            full: true,
                            icon: 'wallet',
                            onTap: () => ctx.toast('تم تسجيل الدفعة')),
                      ),
                    ]),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  void _openAdd(BuildContext context, Ctx ctx) {
    final f = {'name': '', 'phone': '', 'address': '', 'cycle': 'شهري', 'amount': ''};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إضافة عامل / شركة',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['name']!.trim().isEmpty ||
                f['phone']!.trim().isEmpty ||
                (int.tryParse(f['amount']!) ?? 0) <= 0,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createWorker(ctx.btype, {
                  'name': f['name']!.trim(),
                  'phone': f['phone']!.trim(),
                  'address': f['address'],
                  'cycle': f['cycle'],
                  'amount': int.tryParse(f['amount']!) ?? 0,
                });
                await ctx.reload();
                ctx.toast('تمت إضافة ${f['name']!.trim()}');
              } catch (_) {
                ctx.toast('تعذّر الحفظ، تحقّق من الاتصال', tone: 'late');
              }
            },
          ),
          children: [
            Field(
                label: 'الاسم',
                icon: 'user',
                placeholder: 'اسم العامل أو الشركة',
                onChanged: (v) => setS(() => f['name'] = v)),
            Field(
                label: 'الجوال',
                icon: 'phone',
                placeholder: '5X XXX XXXX',
                ltr: true,
                keyboardType: TextInputType.phone,
                onChanged: (v) => setS(() => f['phone'] = v)),
            Field(
                label: 'العنوان',
                icon: 'pin',
                placeholder: 'العنوان',
                onChanged: (v) => f['address'] = v),
            SelectField(
              label: 'نوع الدفع',
              icon: 'calendar',
              options: const [
                SelectOption('يومي', 'يومي'),
                SelectOption('أسبوعي', 'أسبوعي'),
                SelectOption('شهري', 'شهري'),
              ],
              value: f['cycle'],
              onChanged: (v) => setS(() => f['cycle'] = v as String),
            ),
            Field(
                label: 'المبلغ',
                icon: 'dollar',
                placeholder: '0',
                ltr: true,
                suffix: '\$',
                keyboardType: TextInputType.number,
                onChanged: (v) => setS(() => f['amount'] = v)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Parking ─────────────────────────────

class ParkingScreen extends StatelessWidget {
  const ParkingScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    int countBy(String s) => kParking.where((p) => p.status == s).length;

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة الباركينج',
        subtitle: '${kParking.length} موقف',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'plus', onTap: () => _openAdd(context, ctx)),
      ),
      nav: ctx.adminNav,
      children: [
        Row(children: [
          MiniStat(label: 'مشغول', value: '${countBy('مشغول')}', tone: 'ok'),
          const SizedBox(width: 8),
          MiniStat(label: 'شاغر', value: '${countBy('شاغر')}', tone: 'navy'),
          const SizedBox(width: 8),
          MiniStat(label: 'صيانة', value: '${countBy('صيانة')}', tone: 'gold'),
        ]),
        const SizedBox(height: 14),
        gridRows(kParking.map((p) => _spot(context, p)).toList(), n: 2),
      ],
    );
  }

  Widget _spot(BuildContext context, ParkingSpot p) {
    final cols = {
      'مشغول': (AppColors.okBg, AppColors.ok700, AppColors.ok),
      'شاغر': (AppColors.navy50, AppColors.navy700, AppColors.navy300),
      'صيانة': (AppColors.warnBg, AppColors.gold700, AppColors.warn),
    }[p.status]!;
    return Pressable(
      onTap: () => _openDetail(context, ctx, p),
      scale: 0.97,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: cols.$1, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: AppIcon('parking', size: 24, color: cols.$2),
                ),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: cols.$3, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 10),
            NumText(p.no, style: AppType.num(size: 16, weight: FontWeight.w800, color: AppColors.ink900)),
            const SizedBox(height: 2),
            Text('${p.status}${p.unit.isNotEmpty ? ' · وحدة ${p.unit}' : ''}',
                style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, Ctx ctx, ParkingSpot p) {
    showAppSheet(
      context,
      SheetShell(
        title: 'موقف ${p.no}',
        children: [
          DetailGrid(rows: [
            DetailRow('parking', 'الحالة', p.status),
            DetailRow('building', 'الوحدة المرتبطة', p.unit.isEmpty ? 'غير مرتبط' : p.unit),
            DetailRow('key', 'رمز الدخول', p.code, ltr: true),
            DetailRow('wallet', 'أجرة الباركينج', '${fmtUSD(20)} (اختياري)'),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: RichText(
              text: TextSpan(
                style: AppType.base(size: 13, weight: FontWeight.w500, color: AppColors.ink600),
                children: [
                  TextSpan(text: 'ملاحظات: ', style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
                  TextSpan(text: p.note.isEmpty ? 'لا توجد ملاحظات' : p.note),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'تعديل الموقف',
            variant: BtnVariant.outline,
            full: true,
            icon: 'edit',
            onTap: () {
              Navigator.of(context).pop();
              _openEditParking(context, ctx, p);
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'حذف الموقف',
            variant: BtnVariant.outline,
            full: true,
            icon: 'trash',
            onTap: () async {
              Navigator.of(context).pop();
              try {
                await Api.I.deleteParking(ctx.btype, p.id);
                await ctx.reload();
                ctx.toast('تم حذف الموقف');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
        ],
      ),
    );
  }

  void _openAdd(BuildContext context, Ctx ctx) {
    final f = {'no': '', 'unit': '', 'code': '', 'note': ''};
    String status = 'شاغر';
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إضافة موقف',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['no']!.trim().isEmpty,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createParking(ctx.btype, {
                  'no': f['no']!.trim(),
                  'status': status,
                  'unit_no': f['unit']!.trim(),
                  'code': f['code']!.trim(),
                  'note': f['note']!.trim(),
                });
                await ctx.reload();
                ctx.toast('تمت إضافة الموقف');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'رقم الموقف', icon: 'parking', placeholder: 'P-01', ltr: true, onChanged: (v) => setS(() => f['no'] = v)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('الحالة', style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
            Segmented(
              value: status,
              onChanged: (v) => setS(() => status = v as String),
              options: const [
                SegOption('شاغر', 'شاغر'),
                SegOption('مشغول', 'مشغول'),
                SegOption('صيانة', 'صيانة'),
              ],
            ),
            const SizedBox(height: 12),
            Field(label: 'الوحدة المرتبطة (اختياري)', icon: 'building', ltr: true, onChanged: (v) => f['unit'] = v),
            Field(label: 'رمز الدخول (اختياري)', icon: 'key', ltr: true, onChanged: (v) => f['code'] = v),
            Field(label: 'ملاحظات (اختياري)', icon: 'edit', onChanged: (v) => f['note'] = v),
          ],
        ),
      ),
    );
  }

  void _openEditParking(BuildContext context, Ctx ctx, ParkingSpot p) {
    final f = {'no': p.no, 'unit': p.unit, 'code': p.code == '—' ? '' : p.code, 'note': p.note};
    String status = p.status;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل موقف ${p.no}',
          footer: AppButton(
            label: 'حفظ التعديلات',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updateParking(ctx.btype, p.id, {
                  'no': f['no']!.trim(),
                  'status': status,
                  'unit_no': f['unit']!.trim(),
                  'code': f['code']!.trim(),
                  'note': f['note']!.trim(),
                });
                await ctx.reload();
                ctx.toast('تم حفظ الموقف');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'رقم الموقف', icon: 'parking', value: f['no']!, ltr: true, onChanged: (v) => f['no'] = v),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('الحالة', style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
            Segmented(
              value: status,
              onChanged: (v) => setS(() => status = v as String),
              options: const [
                SegOption('شاغر', 'شاغر'),
                SegOption('مشغول', 'مشغول'),
                SegOption('صيانة', 'صيانة'),
              ],
            ),
            const SizedBox(height: 12),
            Field(label: 'الوحدة المرتبطة (اختياري)', icon: 'building', value: f['unit']!, ltr: true, onChanged: (v) => f['unit'] = v),
            Field(label: 'رمز الدخول (اختياري)', icon: 'key', value: f['code']!, ltr: true, onChanged: (v) => f['code'] = v),
            Field(label: 'ملاحظات (اختياري)', icon: 'edit', value: f['note']!, onChanged: (v) => f['note'] = v),
          ],
        ),
      ),
    );
  }
}

/// Compact tappable year chip — opens a list picker over [kYears].
class _YearChip extends StatelessWidget {
  const _YearChip({required this.year, required this.onTap});
  final int year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.navy700,
          borderRadius: BorderRadius.circular(11),
          boxShadow: AppShadows.sm,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AppIcon('calendar', size: 15, color: Colors.white),
          const SizedBox(width: 5),
          NumText('$year', style: AppType.num(size: 13, weight: FontWeight.w800, color: Colors.white)),
          const SizedBox(width: 3),
          const AppIcon('chevronDown', size: 14, color: Colors.white),
        ]),
      ),
    );
  }
}

/// One row in the year list picker.
class _YearPickRow extends StatelessWidget {
  const _YearPickRow({required this.year, required this.selected, required this.onTap});
  final int year;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy50 : AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? AppColors.navy700 : AppColors.line2, width: 1.5),
        ),
        child: Row(
          children: [
            AppIcon('calendar', size: 19, color: selected ? AppColors.navy700 : AppColors.ink400),
            const SizedBox(width: 10),
            Expanded(
              child: NumText('$year',
                  style: AppType.num(
                      size: 15,
                      weight: FontWeight.w700,
                      color: selected ? AppColors.navy700 : AppColors.ink900)),
            ),
            if (selected) const AppIcon('check', size: 18, color: AppColors.navy700),
          ],
        ),
      ),
    );
  }
}

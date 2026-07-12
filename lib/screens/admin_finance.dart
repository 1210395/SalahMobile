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

  /// #33: group الإيرادات by renter (tap → their payments for the active filter)
  /// instead of one row per individual payment.
  bool byRenter = true;

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
        onHome: ctx.role == AppRole.admin ? () => ctx.go('home') : null,
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
        // Month + year as dropdowns (droplists) — clearer than the chip strip.
        Row(
          children: [
            Expanded(
              child: SelectField(
                label: 'الشهر',
                icon: 'calendar',
                value: month,
                options: [
                  const SelectOption('all', 'كل الأشهر'),
                  for (var i = 0; i < 12; i++) SelectOption('$i', monthLabelNum(i)),
                ],
                onChanged: (v) => setState(() => month = v as String),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField(
                label: 'السنة',
                icon: 'calendar',
                value: '$year',
                options: [for (final y in kYears) SelectOption('$y', '$y')],
                onChanged: (v) => setState(() => year = int.tryParse('$v') ?? year),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // #33: view the الإيرادات grouped by renter, or as individual payments.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Segmented(
            small: true,
            value: byRenter ? 'renter' : 'payment',
            onChanged: (v) => setState(() => byRenter = v == 'renter'),
            options: const [
              SegOption('renter', 'حسب الساكن'),
              SegOption('payment', 'كل الدفعات'),
            ],
          ),
        ),
        AppCard(
          pad: 6,
          child: list.isEmpty
              ? const EmptyState(icon: 'wallet', title: 'لا توجد دفعات', sub: 'لا توجد دفعات في هذا الشهر')
              : (byRenter ? _renterRows(ctx, list) : _paymentRows(ctx, list)),
        ),
      ],
    );
  }

  /// One row per individual payment.
  Widget _paymentRows(Ctx ctx, List<Payment> list) => Column(
        children: List.generate(list.length, (i) {
          final p = list[i];
          return GestureDetector(
            onTap: () => _openDetail(ctx, p),
            onLongPress: () => _openEdit(ctx, p),
            child: ListRow(
              leading: const IconChip(icon: 'wallet', tone: 'ok', size: 42),
              title: p.name,
              // Show which month the payment COVERS (not just the pay date).
              sub: '${p.unit.isEmpty ? 'إيراد خاص' : '${ctx.res ? 'شقة' : 'وحدة'} ${p.unit}'}'
                  ' · عن ${monthLabelNum(p.month)} ${p.year} · ${p.method}',
              dividerBelow: i < list.length - 1,
              trailing: _amountTrailing('+${fmtUSD(p.amount)}', p.date, AppColors.ok700),
            ),
          );
        }),
      );

  /// #33: one row per RENTER (count + total for the active filter); tapping one
  /// opens all of that renter's payments within the same filter.
  Widget _renterRows(Ctx ctx, List<Payment> list) {
    final groups = <String, List<Payment>>{};
    for (final p in list) {
      groups.putIfAbsent(p.unit, () => []).add(p);
    }
    final keys = groups.keys.toList()..sort();
    return Column(
      children: List.generate(keys.length, (i) {
        final no = keys[i];
        final rows = groups[no]!;
        final sum = rows.fold<int>(0, (s, p) => s + p.amount);
        final name = rows.first.name;
        final special = no.isEmpty;
        return GestureDetector(
          onTap: () => _openUnitPayments(ctx, no, name, only: rows),
          child: ListRow(
            leading: IconChip(icon: special ? 'receipt' : 'user', tone: 'ok', size: 42),
            title: special ? 'إيرادات خاصة' : name,
            sub: special
                ? '${rows.length} إيراد'
                : '${ctx.res ? 'شقة' : 'وحدة'} $no · ${rows.length} دفعة',
            dividerBelow: i < keys.length - 1,
            trailing: _amountTrailing('+${fmtUSD(sum)}', '', AppColors.ok700),
          ),
        );
      }),
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
            Text(p.unit.isEmpty ? '${p.name} · إيراد خاص' : '${p.name} · وحدة ${p.unit}',
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

  /// Open a read-only detail sheet for one payment with تعديل / حذف / سند قبض.
  void _openDetail(Ctx ctx, Payment p) {
    final u = _unitFor(ctx, p.unit);
    final unitWord = ctx.res ? 'الشقة' : 'الوحدة';
    // ايراد خاص (#38/#39) has no renter and no unit — hide the unit-bound rows
    // and the "all payments of this unit" shortcut.
    final special = p.unit.isEmpty;
    showAppSheet(
      context,
      SheetShell(
        title: special ? 'تفاصيل الإيراد' : 'تفاصيل الدفعة',
        children: [
          DetailGrid(rows: [
            DetailRow('user', special ? 'المصدر' : 'الساكن', p.name),
            if (!special) DetailRow('building', unitWord, p.unit),
            DetailRow('wallet', 'المبلغ', fmtUSD(p.amount)),
            DetailRow('receipt', 'البند', _kindNoGuard(p.kind)),
            DetailRow('calendar', 'الشهر المدفوع عنه', '${monthLabelNum(p.month)} ${p.year}'),
            DetailRow('calendar', 'تاريخ الدفع', p.date, ltr: true),
            DetailRow('dollar', 'طريقة الدفع', p.method),
          ]),
          const SizedBox(height: 12),
          if (!special) ...[
            AppButton(
              label: 'كل دفعات ${ctx.res ? 'هذه الشقة' : 'هذه الوحدة'}',
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
          ],
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
  /// All payments for a unit. Pass [only] to scope the list to the caller's
  /// active filter (#33 — a renter row shows just that filter's payments).
  void _openUnitPayments(Ctx ctx, String unitNo, String name, {List<Payment>? only}) {
    final list = (only ?? kPayments.where((x) => x.unit == unitNo).toList()).toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        return byYear != 0 ? byYear : b.month.compareTo(a.month);
      });
    final total = list.fold<int>(0, (s, x) => s + x.amount);
    final special = unitNo.isEmpty;
    showAppSheet(
      context,
      SheetShell(
        title: special ? 'الإيرادات الخاصة' : 'كل الدفعات — $name',
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(
                special
                    ? '${list.length} إيراد بإجمالي ${fmtUSD(total)} خارج ذمم السكان.'
                    : '${list.length} دفعة بإجمالي ${fmtUSD(total)} لـ '
                        '${ctx.res ? 'الشقة' : 'الوحدة'} $unitNo.',
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
                // Tapping a row drills into the payment (تعديل / حذف / سند قبض) —
                // so the per-renter view (#33) is not a dead end.
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _openDetail(ctx, x);
                  },
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
                            style:
                                AppType.num(size: 13.5, weight: FontWeight.w800, color: AppColors.ok)),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Receipt (سند قبض): preview + share via WhatsApp / save as PDF.
  void _openReceipt(Ctx ctx, Payment p, Unit? u) {
    final unitWord = ctx.res ? 'شقة' : 'وحدة';
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
      p.unit.isEmpty ? 'المصدر: ${p.name}' : 'الساكن: ${p.name}',
      // ايراد خاص carries no unit — omit the line entirely rather than print an empty one.
      if (p.unit.isNotEmpty) 'ال$unitWord: ${p.unit}',
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
            row(p.unit.isEmpty ? 'المصدر' : 'الساكن', p.name),
            if (p.unit.isNotEmpty) row('ال$unitWord', p.unit),
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
  const AddPaymentSheet({super.key, required this.ctx, this.initialUnit});
  final Ctx ctx;

  /// Pre-selected renter (#22 — "تسجيل دفعة" on a unit opens this prefilled).
  final String? initialUnit;

  @override
  State<AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<AddPaymentSheet> {
  // The بند being paid (#23). Elevator/guard/parking fees are folded into the
  // single monthly fee, so a renter's charge is one monthly amount.
  PayItem item = PayItem.monthly;

  String target = 'one';
  late Object unit = widget.initialUnit ?? '';
  final Set<String> selUnits = {};

  // Monthly بند only: the covered year + months.
  int payYear = DateTime.now().year;
  late final Set<int> payMonths = {DateTime.now().month - 1};

  // The amount charged. No 0 default (#24) — empty until derived or typed.
  String amountStr = '';
  bool amountTouched = false;

  String otherLabel = ''; // "أخرى" description (#32)

  Object method = 'نقداً';
  String dateIso = todayIso();
  String chequeDate = '';
  String chequeNumber = '';

  late Object currency = activeCurrency;
  String rateStr = '';

  Unit? _unitOf(Ctx ctx, String no) {
    for (final u in (ctx.res ? kApartments : kShops)) {
      if (u.no == no) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final unitList = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    final unitWord = ctx.res ? 'شقة' : 'وحدة';

    // #38/#39: "ايراد خاص" is building income with NO renter — label + amount only.
    final special = target == 'special';

    final sel = target == 'one' ? _unitOf(ctx, '$unit') : null;
    final fee = sel?.sub ?? 0; // the all-in monthly charge
    final dues = sel == null ? 0 : duesOf(sel);

    // #29: ذمم is only selectable when the renter actually owes something.
    final duesAvailable = sel != null && dues > 0;
    if (item == PayItem.dues && !duesAvailable) item = PayItem.monthly;

    // #34: a fully-settled month can't be paid again.
    final settled = <int>{
      if (sel != null)
        for (var m = 0; m < 12; m++)
          if (monthSettled(sel, m, payYear)) m,
    };
    payMonths.removeWhere(settled.contains);
    final monthsCount = payMonths.isEmpty ? 1 : payMonths.length;

    // Suggested amount per بند (seeds the field; the admin may override).
    final suggested = special
        ? 0
        : switch (item) {
            PayItem.monthly => fee * monthsCount,
            PayItem.dues => dues,
            PayItem.other => 0,
          };
    final total = amountTouched ? (int.tryParse(amountStr.trim()) ?? 0) : suggested;

    final sameCur = currency == activeCurrency;
    final rate = sameCur ? 1.0 : (double.tryParse(rateStr) ?? 0);
    final rateOk = sameCur || rate > 0;
    final baseTotal = sameCur ? total : (total * rate).round();

    // #36: covering several months requires at least one month's fee for each.
    final perMonth = total ~/ monthsCount;
    final multiMonthOk = special ||
        item != PayItem.monthly ||
        monthsCount == 1 ||
        (fee > 0 && perMonth >= fee);

    // #26: a cheque needs a FUTURE date + a number.
    final chequeWhen = DateTime.tryParse(chequeDate);
    final chequeFuture = chequeWhen != null && chequeWhen.isAfter(DateTime.now());
    final chequeOk = method != 'شيك' || (chequeFuture && chequeNumber.trim().isNotEmpty);

    final targetOk = special ||
        (target == 'one' && '$unit'.isNotEmpty) ||
        (target == 'group' && selUnits.isNotEmpty) ||
        target == 'all';

    final canSave = targetOk &&
        rateOk &&
        chequeOk &&
        multiMonthOk &&
        total > 0 && // #30: never zero
        // A special income line (or an "أخرى" بند) must be described.
        (special ? otherLabel.trim().isNotEmpty : true) &&
        (special || item != PayItem.other || otherLabel.trim().isNotEmpty) &&
        (special || item != PayItem.dues || total <= dues) &&
        (special || item != PayItem.monthly || payMonths.isNotEmpty);

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
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Segmented(
            small: true,
            value: target,
            onChanged: (v) => setState(() => target = v as String),
            options: [
              SegOption('one', '$unitWord واحدة'),
              const SegOption('all', 'الجميع'),
              const SegOption('group', 'مجموعة'),
              const SegOption('special', 'ايراد خاص'), // #39 — income with no renter
            ],
          ),
        ),
        if (target == 'one')
          SelectField(
            label: unitWord,
            icon: 'building',
            options: [for (final u in unitList) SelectOption(u.no, '${u.no} — ${u.resident}')],
            value: '$unit'.isEmpty ? null : unit,
            onChanged: (v) => setState(() {
              unit = v as String;
              amountTouched = false;
            }),
          ),
        if (target == 'group') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('اختر ${ctx.res ? 'الشقق' : 'الوحدات'} (${selUnits.length})',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in unitList)
                  GestureDetector(
                    onTap: () => setState(() =>
                        selUnits.contains(u.no) ? selUnits.remove(u.no) : selUnits.add(u.no)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: selUnits.contains(u.no) ? AppColors.navy700 : AppColors.surface,
                        border: Border.all(
                            color: selUnits.contains(u.no) ? AppColors.navy700 : AppColors.line2,
                            width: 1.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(u.no,
                          style: AppType.base(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: selUnits.contains(u.no) ? Colors.white : AppColors.ink600)),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (target == 'all')
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _infoNote(
                'ستُسجَّل الدفعة لجميع ${ctx.res ? 'الشقق' : 'الوحدات'} الفعّالة (${unitList.length}).'),
          ),

        // #39: ايراد خاص — no renter, no بند; just a description + amount.
        if (special)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _infoNote(
                'إيراد للمبنى غير مرتبط بساكن (مثال: دفعة برج جوال). لا يُخصم من ذمم أحد.'),
          ),

        // بند الدفع (#23) — only the relevant fields show for each (#27).
        if (!special)
          SelectField(
            label: 'بند الدفع',
            icon: 'receipt',
            options: [
              SelectOption(PayItem.monthly, payItemLabel(PayItem.monthly)),
              if (duesAvailable) SelectOption(PayItem.dues, payItemLabel(PayItem.dues)),
              SelectOption(PayItem.other, payItemLabel(PayItem.other)),
            ],
            value: item,
            onChanged: (v) => setState(() {
              item = v as PayItem;
              amountTouched = false;
            }),
          ),
        if (sel != null && item == PayItem.monthly && fee > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _infoNote('الدفعة الشهرية: ${fmtMoney(fee, activeCurrency)} لكل شهر.'),
          ),
        if (sel != null && item == PayItem.dues)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _infoNote('الذمم المستحقة: ${fmtMoney(dues, activeCurrency)}.'),
          ),
        if (!special && item == PayItem.other)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _infoNote('الإيراد تحت بند "أخرى" لا يُخصم من ذمم الساكن.'),
          ),

        // #27/#31: year + months only for the monthly بند, admin only.
        if (!special && item == PayItem.monthly && ctx.role == AppRole.admin) ...[
          SelectField(
            label: 'سنة الأشهر المدفوعة',
            icon: 'calendar',
            options: [
              for (var y = DateTime.now().year; y >= DateTime.now().year - 6; y--)
                SelectOption(y, '$y'),
            ],
            value: payYear,
            onChanged: (v) => setState(() {
              payYear = v as int;
              amountTouched = false;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('الأشهر المشمولة',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
          ),
          GestureDetector(
            onTap: () => _pickMonths(settled),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line2, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(children: [
                const AppIcon('calendar', size: 20, color: AppColors.navy600),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(_monthsSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.base(size: 14, weight: FontWeight.w700, color: AppColors.ink900)),
                ),
                const AppIcon('chevronDown', size: 18, color: AppColors.ink400),
              ]),
            ),
          ),
          if (!multiMonthOk)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  'لتغطية ${payMonths.length} أشهر يجب ألا يقل المبلغ عن '
                  '${fmtMoney(fee * payMonths.length, activeCurrency)}.',
                  style: AppType.base(
                      size: 11.5, weight: FontWeight.w600, color: AppColors.late700, height: 1.5)),
            ),
        ],

        if (special || item == PayItem.other)
          Field(
            label: special ? 'وصف الإيراد الخاص' : 'وصف الإيراد',
            icon: 'receipt',
            value: otherLabel,
            placeholder: special ? 'مثال: دفعة برج جوال' : 'مثال: غرامة تأخير',
            onChanged: (v) => setState(() => otherLabel = v),
          ),

        // The amount — no 0 seed (#24), digits only (#16), never zero (#30).
        Field(
          key: ValueKey('amount-$item-$monthsCount-$unit-$payYear'),
          label: 'المبلغ',
          icon: 'wallet',
          value: amountTouched ? amountStr : (suggested > 0 ? '$suggested' : ''),
          placeholder: 'أدخل المبلغ',
          ltr: true,
          suffix: currencySymbol(currency as String),
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          onChanged: (v) => setState(() {
            amountTouched = true;
            amountStr = v;
          }),
        ),
        if (item == PayItem.dues && total > dues)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('المبلغ يتجاوز الذمم المستحقة (${fmtMoney(dues, activeCurrency)}).',
                style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.late700)),
          ),

        SelectField(
          label: 'عملة الدفع',
          icon: 'dollar',
          options: [for (final c in kCurrencyCodes) SelectOption(c, '$c (${currencySymbol(c)})')],
          value: currency,
          onChanged: (v) => setState(() {
            currency = v as String;
            rateStr = '';
          }),
        ),
        if (!sameCur) ...[
          Field(
            label: 'سعر الصرف إلى $activeCurrency',
            icon: 'refresh',
            value: rateStr,
            placeholder: '3.75',
            ltr: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalOnly,
            onChanged: (v) => setState(() => rateStr = v),
          ),
          if (rateOk)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _infoNote('المبلغ ${fmtMoney(total, currency as String)} يعادل '
                  '${fmtMoney(baseTotal, activeCurrency)} بعملة المبنى.'),
            ),
        ],

        DateField(
          label: 'تاريخ الدفع',
          value: dateIso,
          onChanged: (v) => setState(() => dateIso = v),
        ),
        SelectField(
          label: 'طريقة الدفع',
          icon: 'wallet',
          options: const [
            SelectOption('نقداً', 'نقداً'),
            SelectOption('تحويل بنكي', 'تحويل بنكي'),
            SelectOption('شيك', 'شيك'),
            SelectOption('محفظة رقمية', 'محفظة رقمية'),
          ],
          value: method,
          onChanged: (v) => setState(() => method = v as String),
        ),
        // #26: cheque → a future due-date + the cheque number.
        if (method == 'شيك') ...[
          DateField(
            label: 'تاريخ الشيك (مستقبلي)',
            value: chequeDate,
            onChanged: (v) => setState(() => chequeDate = v),
          ),
          if (chequeDate.isNotEmpty && !chequeFuture)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('تاريخ الشيك يجب أن يكون في المستقبل.',
                  style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.late700)),
            ),
          Field(
            label: 'رقم الشيك',
            icon: 'receipt',
            value: chequeNumber,
            ltr: true,
            placeholder: '123456',
            onChanged: (v) => setState(() => chequeNumber = v),
          ),
        ],
      ],
    );
  }

  /// Summary text for the months dropdown.
  String _monthsSummary() {
    if (payMonths.isEmpty) return 'اختر الأشهر';
    final cur = DateTime.now().month - 1;
    if (payMonths.length == 1) {
      final m = payMonths.first;
      return m == cur ? 'الشهر الحالي (${monthLabelNum(m)})' : monthLabelNum(m);
    }
    final sorted = payMonths.toList()..sort();
    return sorted.map(monthLabelNum).join('، ');
  }

  /// Multi-select months. A month already SETTLED for this unit/year shows as
  /// paid and cannot be selected again (#34).
  void _pickMonths(Set<int> settled) {
    final cur = DateTime.now().month - 1;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'الأشهر المشمولة',
          footer: AppButton(
            label: 'تم · ${payMonths.length} شهر',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: payMonths.isEmpty,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              setState(() => amountTouched = false);
            },
          ),
          children: [
            for (var i = 0; i < 12; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: settled.contains(i)
                      ? AppColors.surface2
                      : (payMonths.contains(i) ? AppColors.navy50 : AppColors.surface),
                  border: Border.all(
                      color: payMonths.contains(i) ? AppColors.navy100 : AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${monthLabelNum(i)}'
                        '${i == cur ? ' — الحالي' : ''}'
                        '${settled.contains(i) ? ' — مسدّد' : ''}',
                        style: AppType.base(
                            size: 14,
                            weight: FontWeight.w700,
                            color: settled.contains(i) ? AppColors.ink400 : AppColors.ink900)),
                  ),
                  if (settled.contains(i))
                    const AppIcon('checkCircle', size: 20, color: AppColors.ok700)
                  else
                    AppSwitch(
                      checked: payMonths.contains(i),
                      onChanged: (v) => setS(() => v ? payMonths.add(i) : payMonths.remove(i)),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(Ctx ctx, int total, List<Unit> unitList) async {
    final cur = currency as String;
    final sameCur = cur == activeCurrency;
    final rate = sameCur ? 1.0 : (double.tryParse(rateStr) ?? 1);

    // #38/#39: "ايراد خاص" — one row, no renter, never settles dues (the backend
    // forces applies_to_dues=false when unit_no is absent).
    if (target == 'special') {
      final base = sameCur ? total : (total * rate).round();
      Navigator.of(context).pop();
      try {
        await Api.I.createPayment(ctx.btype, {
          'name': otherLabel.trim(),
          'amount': base,
          'original_amount': total,
          'currency': cur,
          'exchange_rate': rate,
          'kind': 'ايراد خاص',
          'month': DateTime.now().month - 1,
          'year': DateTime.now().year,
          'date': dateIso,
          'method': method as String,
          if (method == 'شيك') 'cheque_date': chequeDate,
          if (method == 'شيك') 'cheque_number': chequeNumber.trim(),
        });
        await ctx.reload();
        ctx.toast('تم تسجيل إيراد خاص بقيمة ${fmtMoney(base, activeCurrency)}');
      } catch (e) {
        ctx.toast(apiErrorText(e), tone: 'late');
      }
      return;
    }

    final targets = target == 'all'
        ? unitList.map((u) => u.no).toList()
        : (target == 'group' ? selUnits.toList() : ['$unit']);

    final kind = switch (item) {
      PayItem.monthly => 'دفعة شهرية',
      PayItem.dues => 'ذمم',
      PayItem.other => 'أخرى — ${otherLabel.trim()}',
    };
    // #28: an "أخرى" line is income only and must not settle dues.
    final appliesToDues = item != PayItem.other;

    // The monthly بند settles the chosen months (one row each, sharing the
    // total); ذمم/أخرى record a single row against the current month.
    final months = item == PayItem.monthly
        ? (payMonths.toList()..sort())
        : [DateTime.now().month - 1];
    final year = item == PayItem.monthly ? payYear : DateTime.now().year;

    // Split the total across the covered months (remainder onto the first).
    final n = months.isEmpty ? 1 : months.length;
    final each = total ~/ n;
    final first = each + (total - each * n);

    Navigator.of(context).pop();
    try {
      for (final no in targets) {
        Unit? u;
        for (final x in unitList) {
          if (x.no == no) {
            u = x;
            break;
          }
        }
        for (var i = 0; i < months.length; i++) {
          final amt = i == 0 ? first : each;
          final base = sameCur ? amt : (amt * rate).round();
          await Api.I.createPayment(ctx.btype, {
            'unit_no': no,
            if (u != null && u.resident.trim().isNotEmpty) 'name': u.resident,
            'amount': base,
            'original_amount': amt,
            'currency': cur,
            'exchange_rate': rate,
            'kind': kind,
            'month': months[i],
            'year': year,
            'date': dateIso,
            'method': method as String,
            'applies_to_dues': appliesToDues,
            if (method == 'شيك') 'cheque_date': chequeDate,
            if (method == 'شيك') 'cheque_number': chequeNumber.trim(),
          });
        }
      }
      await ctx.reload();
      final baseTotal = sameCur ? total : (total * rate).round();
      ctx.toast('تم تسجيل دفعة بقيمة ${fmtMoney(baseTotal, activeCurrency)}');
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
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
        onHome: ctx.role == AppRole.admin ? () => ctx.go('home') : null,
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
                onTap: () => _openEdit(ctx, e),
                onLongPress: () => _openEdit(ctx, e),
                child: ListRow(
                  leading: IconChip(icon: e.icon, tone: e.tone, size: 42),
                  title: e.supplier,
                  // Show the entered (foreign) amount when it differs from the
                  // building's base currency, so "375 ₪" isn't hidden as its base value.
                  sub: '${e.cat}'
                      '${e.foreignCurrency ? ' · ${fmtMoney(e.originalAmount, e.currency)}' : ''}'
                      '${e.desc.isNotEmpty ? ' · ${e.desc}' : ''}',
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
        onBack: ctx.back,
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
                    const SizedBox(height: 10),
                    // Attendance + payment status for the current cycle.
                    Row(children: [
                      AppBadge(
                        label: w.came ? 'حضر' : 'لم يحضر',
                        tone: w.came ? 'ok' : 'late',
                        icon: w.came ? 'checkCircle' : 'xCircle',
                      ),
                      const SizedBox(width: 8),
                      AppBadge(
                        label: _payStatusLabel(w.payStatus),
                        tone: w.payStatus == 'full'
                            ? 'ok'
                            : w.payStatus == 'partial'
                                ? 'gold'
                                : 'late',
                      ),
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
                            onTap: () async {
                              final ph = w.phone.trim();
                              await shareViaWhatsApp(
                                  phone: (ph.isEmpty || ph == '—') ? null : ph,
                                  text: 'مرحباً ${w.name}');
                            }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                            label: 'تحديث الحالة',
                            size: BtnSize.sm,
                            full: true,
                            icon: 'check',
                            onTap: () => _openVisit(context, ctx, w)),
                      ),
                    ]),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  static String _payStatusLabel(String s) =>
      s == 'full' ? 'مدفوع بالكامل' : (s == 'partial' ? 'مدفوع جزئياً' : 'غير مدفوع');

  /// Record this cycle's attendance (came?) + payment status (full/partial/none).
  void _openVisit(BuildContext context, Ctx ctx, Worker w) {
    bool came = w.came;
    String payStatus = w.payStatus;
    String partial = w.paidAmount > 0 ? '${w.paidAmount}' : '';
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تحديث حالة ${w.name}',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updateWorker(ctx.btype, w.id, {
                  'came': came,
                  if (came) 'last_visit': todayIso(),
                  'pay_status': payStatus,
                  if (payStatus == 'partial') 'paid_amount': int.tryParse(partial) ?? 0,
                  if (payStatus == 'none') 'paid_amount': 0,
                });
                await ctx.reload();
                ctx.toast('تم تحديث حالة ${w.name}');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: came ? AppColors.navy50 : AppColors.surface,
                border: Border.all(color: came ? AppColors.navy100 : AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(children: [
                const AppIcon('checkCircle', size: 20, color: AppColors.navy700),
                const SizedBox(width: 11),
                Expanded(child: Text('حضر في هذه الدورة', style: AppType.base(size: 14, weight: FontWeight.w700))),
                AppSwitch(checked: came, onChanged: (v) => setS(() => came = v)),
              ]),
            ),
            const SizedBox(height: 14),
            Text('حالة الدفع',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            const SizedBox(height: 8),
            Segmented(
              small: true,
              value: payStatus,
              onChanged: (v) => setS(() => payStatus = v as String),
              options: const [
                SegOption('none', 'لم يُدفع'),
                SegOption('partial', 'جزئي'),
                SegOption('full', 'كامل'),
              ],
            ),
            if (payStatus == 'partial') ...[
              const SizedBox(height: 12),
              Field(
                label: 'المبلغ المدفوع',
                icon: 'wallet',
                value: partial,
                ltr: true,
                keyboardType: TextInputType.number,
                marginBottom: 0,
                onChanged: (v) => setS(() => partial = v),
              ),
            ],
            const SizedBox(height: 14),
            AppButton(
              label: 'حذف العامل / الشركة',
              variant: BtnVariant.outline,
              full: true,
              icon: 'trash',
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await Api.I.deleteWorker(ctx.btype, w.id);
                  await ctx.reload();
                  ctx.toast('تم حذف ${w.name}');
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
                suffix: currencySymbol(activeCurrency),
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
        onBack: ctx.back,
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


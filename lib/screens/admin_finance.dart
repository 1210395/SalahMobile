// عمارتي — Admin: Payments, Expenses, Workers, Parking.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';

// ───────────────────────────── Payments ─────────────────────────────

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String month = 'all';
  int year = 2026;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final byYear = kPayments.where((p) => p.year == year).toList();
    final total = byYear.fold<int>(0, (s, p) => s + p.amount);
    final list = month == 'all'
        ? byYear
        : byYear.where((p) => p.month == int.parse(month)).toList();

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة الدفعات',
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
              Text('إجمالي التحصيل — مايو 2026',
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
            Expanded(
              child: Segmented(
                small: true,
                value: month,
                onChanged: (v) => setState(() => month = v as String),
                options: const [
                  SegOption('all', 'الكل'),
                  SegOption('4', 'مايو'),
                  SegOption('3', 'أبريل'),
                  SegOption('2', 'مارس'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _YearChip(
              year: year,
              onChanged: (y) => setState(() => year = y),
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
                      onLongPress: () => _confirmDelete(ctx, p),
                      child: ListRow(
                        leading: const IconChip(icon: 'wallet', tone: 'ok', size: 42),
                        title: p.name,
                        sub: 'وحدة ${p.unit} · ${p.kind} · ${p.method}',
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

  void _confirmDelete(Ctx ctx, Payment p) {
    showAppSheet(
      context,
      SheetShell(
        title: 'حذف الدفعة',
        children: [
          Text('حذف دفعة ${fmtUSD(p.amount)} للوحدة ${p.unit}؟ لا يمكن التراجع.',
              style: AppType.base(size: 14, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
          const SizedBox(height: 14),
          AppButton(
            label: 'حذف الدفعة',
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
  late final Map<String, bool> types = {for (final t in kPayTypes) t.id: t.on};
  Object unit = '';
  Object method = 'تحويل بنكي';
  Object payMonth = 4;
  // Currency the amount is entered in + its rate to the building's base currency.
  late Object currency = activeCurrency;
  String rateStr = '';
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
    final base = kPayTypes.where((t) => types[t.id] == true).fold<int>(0, (s, t) => s + t.amount);
    final extra = otherOn ? (int.tryParse(otherAmount) ?? 0) : 0;
    final total = base + extra;
    final unitList = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    final units = unitList.map((u) => SelectOption(u.no, '${u.no} — ${u.resident}')).toList();

    String payIcon(String id) =>
        {'sub': 'wallet', 'elev': 'elevator', 'guard': 'shield'}[id] ?? 'parking';

    final sameCur = currency == activeCurrency;
    final rateOk = sameCur || (double.tryParse(rateStr) ?? 0) > 0;
    final canSave = ((target == 'one' && unit != '') ||
            (target == 'group' && selUnits.isNotEmpty) ||
            target == 'all') &&
        rateOk;

    return SheetShell(
      title: 'تسجيل دفعة جديدة',
      footer: AppButton(
        label: 'حفظ الدفعة · ${fmtMoney(total, currency as String)}',
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
            options: const [
              SegOption('one', 'وحدة واحدة'),
              SegOption('all', 'الجميع'),
              SegOption('group', 'مجموعة'),
            ],
          ),
        ),
        if (target == 'one')
          SelectField(
            label: 'الوحدة / الساكن',
            icon: 'building',
            options: units,
            value: unit == '' ? null : unit,
            onChanged: (v) => setState(() => unit = v),
          ),
        if (target == 'all')
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _infoNote('سيتم تسجيل الدفعة لجميع الوحدات الفعّالة (${unitList.length} وحدة).'),
          ),
        if (target == 'group') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('اختر الوحدات (${selUnits.length})',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unitList.map((u) {
                final on = selUnits.contains(u.no);
                return GestureDetector(
                  onTap: () => setState(() => on ? selUnits.remove(u.no) : selUnits.add(u.no)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: on ? AppColors.navy700 : AppColors.surface,
                      border: Border.all(color: on ? AppColors.navy700 : AppColors.line2, width: 1.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(u.no,
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
                        NumText(fmtUSD(t.amount),
                            style: AppType.num(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                      ],
                    ),
                  ),
                  AppSwitch(checked: on, onChanged: (v) => setState(() => types[t.id] = v)),
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
        const SizedBox(height: 7),
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
                'بعملة المبنى.'),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectField(
                label: 'الشهر',
                options: [for (var i = 0; i < arMonths.length; i++) SelectOption(i, arMonths[i])],
                value: payMonth,
                onChanged: (v) => setState(() => payMonth = v),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Field(label: 'التاريخ', value: '2026-05-06', ltr: true)),
          ],
        ),
        SelectField(
          label: 'طريقة الدفع',
          icon: 'dollar',
          options: const [
            SelectOption('تحويل بنكي', 'تحويل بنكي'),
            SelectOption('نقداً', 'نقداً'),
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
    final m = payMonth as int;
    final date = '2026-${(m + 1).toString().padLeft(2, '0')}-01';
    final cur = currency as String;
    final sameCur = cur == activeCurrency;
    final rate = sameCur ? 1.0 : (double.tryParse(rateStr) ?? 1);
    Navigator.of(context).pop();
    try {
      for (final no in targets) {
        await Api.I.createPayment(ctx.btype, {
          'unit_no': no,
          'original_amount': total,
          'currency': cur,
          'exchange_rate': rate,
          'kind': kind,
          'month': m,
          'year': 2026,
          'date': date,
          'method': method as String,
        });
      }
      await ctx.reload();
      final who = target == 'all'
          ? 'جميع الوحدات'
          : target == 'group'
              ? '${targets.length} وحدة'
              : 'وحدة $unit';
      ctx.toast('تم تسجيل دفعة بقيمة ${fmtMoney(total, cur)} لـ $who');
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
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'مصروف جديد', onTap: () => _openAdd(ctx)),
      children: [
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
                onLongPress: () => _confirmDelete(ctx, e),
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

  void _confirmDelete(Ctx ctx, Expense e) {
    showAppSheet(
      context,
      SheetShell(
        title: 'حذف المصروف',
        children: [
          Text('حذف مصروف ${e.supplier} (${fmtUSD(e.amount)})؟ لا يمكن التراجع.',
              style: AppType.base(size: 14, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
          const SizedBox(height: 14),
          AppButton(
            label: 'حذف المصروف',
            full: true,
            icon: 'trash',
            onTap: () async {
              Navigator.of(context).pop();
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
    final f = {'cat': kExpCats.first, 'supplier': '', 'amount': '', 'date': '2026-05-06', 'desc': ''};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تسجيل مصروف',
          footer: AppButton(
            label: 'حفظ المصروف',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['supplier']!.trim().isEmpty || (int.tryParse(f['amount']!) ?? 0) <= 0,
            onTap: () async {
              final meta = _expMeta[f['cat']] ?? const ['receipt', 'gold'];
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createExpense(ctx.btype, {
                  'cat': f['cat'],
                  'icon': meta[0],
                  'tone': meta[1],
                  'supplier': f['supplier']!.trim(),
                  'amount': int.tryParse(f['amount']!) ?? 0,
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
                        suffix: '\$',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setS(() => f['amount'] = v))),
                const SizedBox(width: 10),
                Expanded(
                    child: Field(
                        label: 'التاريخ',
                        value: f['date']!,
                        ltr: true,
                        onChanged: (v) => f['date'] = v)),
              ],
            ),
            AppTextArea(
                label: 'الوصف',
                placeholder: 'تفاصيل المصروف…',
                onChanged: (v) => f['desc'] = v),
          ],
        ),
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
}

/// Compact tappable year chip (cycles through the tracked years).
class _YearChip extends StatelessWidget {
  const _YearChip({required this.year, required this.onChanged});
  final int year;
  final ValueChanged<int> onChanged;
  static const _years = [2024, 2025, 2026];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final i = _years.indexOf(year);
        onChanged(_years[(i + 1) % _years.length]);
      },
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
        ]),
      ),
    );
  }
}

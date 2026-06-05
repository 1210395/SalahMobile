// عمارتي — Admin: Payments, Expenses, Workers, Parking.

import 'package:flutter/material.dart';

import '../common.dart';

// ───────────────────────────── Payments ─────────────────────────────

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String month = 'all';

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final total = kPayments.fold<int>(0, (s, p) => s + p.amount);
    final list = month == 'all'
        ? kPayments
        : kPayments.where((p) => p.month == int.parse(month)).toList();

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
                AppBadge(label: '${kPayments.length} دفعة', tone: 'ok', icon: 'checkCircle'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('متوسط ${fmtUSD((total / kPayments.length).round())}',
                      style: AppType.base(size: 12, weight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Segmented(
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
        const SizedBox(height: 12),
        AppCard(
          pad: 6,
          child: list.isEmpty
              ? const EmptyState(icon: 'wallet', title: 'لا توجد دفعات', sub: 'لا توجد دفعات في هذا الشهر')
              : Column(
                  children: List.generate(list.length, (i) {
                    final p = list[i];
                    return ListRow(
                      leading: const IconChip(icon: 'wallet', tone: 'ok', size: 42),
                      title: p.name,
                      sub: 'وحدة ${p.unit} · ${p.kind} · ${p.method}',
                      dividerBelow: i < list.length - 1,
                      trailing: _amountTrailing('+${fmtUSD(p.amount)}', p.date, AppColors.ok700),
                    );
                  }),
                ),
        ),
      ],
    );
  }

  void _openAdd(Ctx ctx) => showAppSheet(context, AddPaymentSheet(ctx: ctx));
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

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final total = kPayTypes.where((t) => types[t.id] == true).fold<int>(0, (s, t) => s + t.amount);
    final units = (ctx.res ? kApartments : kShops)
        .where((u) => u.status != 'vacant')
        .map((u) => SelectOption(u.no, '${u.no} — ${u.resident}'))
        .toList();

    String payIcon(String id) =>
        {'sub': 'wallet', 'elev': 'elevator', 'guard': 'shield'}[id] ?? 'parking';

    return SheetShell(
      title: 'تسجيل دفعة جديدة',
      footer: AppButton(
        label: 'حفظ الدفعة · ${fmtUSD(total)}',
        full: true,
        size: BtnSize.lg,
        icon: 'check',
        disabled: unit == '',
        onTap: () {
          Navigator.of(context).pop();
          ctx.toast('تم تسجيل دفعة بقيمة ${fmtUSD(total)}');
        },
      ),
      children: [
        SelectField(
          label: 'الوحدة / الساكن',
          icon: 'building',
          options: units,
          value: unit == '' ? null : unit,
          onChanged: (v) => setState(() => unit = v),
        ),
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
        const SizedBox(height: 7),
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
              return ListRow(
                leading: IconChip(icon: e.icon, tone: e.tone, size: 42),
                title: e.supplier,
                sub: '${e.cat} · ${e.desc}',
                dividerBelow: i < list.length - 1,
                trailing: _amountTrailing('-${fmtUSD(e.amount)}', e.date, AppColors.late700),
              );
            }),
          ),
        ),
      ],
    );
  }

  void _openAdd(Ctx ctx) {
    showAppSheet(
      context,
      SheetShell(
        title: 'تسجيل مصروف',
        footer: AppButton(
          label: 'حفظ المصروف',
          full: true,
          size: BtnSize.lg,
          icon: 'check',
          onTap: () {
            Navigator.of(context).pop();
            ctx.toast('تم تسجيل المصروف');
          },
        ),
        children: [
          SelectField(
            label: 'التصنيف',
            icon: 'grid',
            options: [for (final c in kExpCats) SelectOption(c, c)],
            value: 'مصعد',
            onChanged: (_) {},
          ),
          const Field(label: 'المورّد / الجهة', icon: 'store', placeholder: 'اسم المورّد'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                  child: Field(
                      label: 'المبلغ', icon: 'dollar', placeholder: '0', ltr: true, suffix: '\$', keyboardType: TextInputType.number)),
              SizedBox(width: 10),
              Expanded(child: Field(label: 'التاريخ', value: '2026-05-06', ltr: true)),
            ],
          ),
          const AppTextArea(label: 'الوصف', placeholder: 'تفاصيل المصروف…'),
        ],
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
    showAppSheet(
      context,
      SheetShell(
        title: 'إضافة عامل / شركة',
        footer: AppButton(
          label: 'حفظ',
          full: true,
          size: BtnSize.lg,
          icon: 'check',
          onTap: () {
            Navigator.of(context).pop();
            ctx.toast('تمت الإضافة');
          },
        ),
        children: [
          const Field(label: 'الاسم', icon: 'user', placeholder: 'اسم العامل أو الشركة'),
          const Field(label: 'الجوال', icon: 'phone', placeholder: '5X XXX XXXX', ltr: true),
          const Field(label: 'العنوان', icon: 'pin', placeholder: 'العنوان'),
          SelectField(
            label: 'نوع الدفع',
            icon: 'calendar',
            options: const [
              SelectOption('يومي', 'يومي'),
              SelectOption('أسبوعي', 'أسبوعي'),
              SelectOption('شهري', 'شهري'),
            ],
            value: 'شهري',
            onChanged: (_) {},
          ),
          const Field(label: 'المبلغ', icon: 'dollar', placeholder: '0', ltr: true, suffix: '\$', keyboardType: TextInputType.number),
        ],
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
        right: RoundBtn(icon: 'plus', onTap: () => ctx.toast('إضافة موقف', tone: 'info')),
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
      onTap: () => _openDetail(context, p),
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

  void _openDetail(BuildContext context, ParkingSpot p) {
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
        ],
      ),
    );
  }
}

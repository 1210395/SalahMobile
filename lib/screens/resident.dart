// عمارتي — Resident screens + admin "More" hub.

import 'package:flutter/material.dart';

import '../common.dart';
import 'admin_services.dart' show kElevPhone;

// Placeholder used when there is no occupied unit yet (empty/live data). Status
// 'vacant' + zeroed fields lets callers detect "no real unit" via [_hasUnit].
const Unit _noUnit = Unit(
  id: '',
  no: '',
  floor: 0,
  resident: '',
  kind: '',
  phone: '—',
  sub: 0,
  status: 'vacant',
  balance: 0,
  payer: '—',
);

// First occupied unit for the current role, or [_noUnit] when the list is empty
// / all vacant — orElse keeps empty data from throwing (resHome/resReport/…).
Unit _meUnit(Ctx ctx) => (ctx.res ? kApartments : kShops)
    .firstWhere((u) => u.status != 'vacant', orElse: () => _noUnit);

// Whether [me] is a real occupied unit (vs the empty-data placeholder).
bool _hasUnit(Unit me) => me.status != 'vacant';

class ResidentHome extends StatelessWidget {
  const ResidentHome({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final me = _meUnit(ctx);
    final res = ctx.res;
    final paid = me.status != 'late';

    final header = AppHeader(
      accent: true,
      logo: true,
      right: Row(mainAxisSize: MainAxisSize.min, children: [
        RoundBtn(icon: 'switch', dark: true, onTap: ctx.openRole),
        const SizedBox(width: 8),
        RoundBtn(icon: 'bell', dark: true, badge: true, onTap: () => ctx.go('alerts')),
        const SizedBox(width: 8),
        RoundBtn(
            icon: 'logout',
            dark: true,
            onTap: () => showConfirmSheet(
                  context,
                  title: 'تسجيل الخروج',
                  message: 'هل تريد تسجيل الخروج؟ ستحتاج إلى تسجيل الدخول مرة أخرى للوصول إلى حسابك.',
                  confirmLabel: 'تسجيل الخروج',
                  onConfirm: () => ctx.signOut(),
                )),
      ]),
    );

    // No occupied unit yet (empty / live data) — show a friendly placeholder.
    if (!_hasUnit(me)) {
      return ScreenScaffold(
        header: header,
        nav: ctx.resNav,
        children: const [
          SizedBox(height: 40),
          EmptyState(
            icon: 'building',
            title: 'لا توجد بيانات وحدة بعد',
            sub: 'سيظهر اشتراكك وتقاريرك هنا بعد ربط وحدتك بالمبنى.',
          ),
        ],
      );
    }

    return ScreenScaffold(
      header: header,
      nav: ctx.resNav,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            children: [
              Avatar(name: me.resident, size: 40, tone: 'gold'),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('أهلاً، ${me.resident.split(' ').first}',
                      style: AppType.base(size: 15, weight: FontWeight.w800)),
                  const SizedBox(height: 1),
                  Text('${floorUnitLabel(me, res)} · ${ctx.building.name}',
                      style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                ],
              ),
            ],
          ),
        ),
        // My status hero.
        HeroBanner(
          gradient: paid
              ? const [AppColors.ok700, Color(0xFF0F5E3E)]
              : const [AppColors.late700, Color(0xFF8C2019)],
          shadow: AppShadows.md,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('حالة اشتراكي — ${monthLabelNum(DateTime.now().month - 1)}',
                            style: AppType.base(size: 12.5, weight: FontWeight.w500, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(paid ? 'مسدّد بالكامل' : 'يوجد مبلغ متأخر',
                            style: AppType.base(size: 22, weight: FontWeight.w800, color: Colors.white)),
                      ],
                    ),
                  ),
                  AppIcon(paid ? 'checkCircle' : 'alert', size: 30, color: Colors.white),
                ],
              ),
              if (!paid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  // balance is negative when owing; show the overdue amount as a
                  // positive figure ("المتأخر: $80", not "-$80").
                  child: NumText('المتأخر: ${fmtUSD(me.balance.abs())}',
                      style: AppType.num(size: 14, weight: FontWeight.w700, color: Colors.white)),
                ),
              const SizedBox(height: 14),
              AppButton(
                label: paid ? 'عرض إيصالاتي' : 'سدّد الآن',
                variant: BtnVariant.white,
                full: true,
                icon: paid ? 'receipt' : 'wallet',
                onTap: () =>
                    paid ? ctx.go('resReport') : ctx.toast('فتح صفحة الدفع', tone: 'info'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionTitle(text: 'ملخص عام للمبنى'),
        Row(children: [
          Expanded(child: StatCard(label: 'إيرادات الشهر', value: fmtUSD(Summary.revenueM), icon: 'trend', tone: 'ok')),
          const SizedBox(width: 10),
          Expanded(child: StatCard(label: 'مصروفات الشهر', value: fmtUSD(Summary.expenseM), icon: 'expense', tone: 'late')),
        ]),
        const SizedBox(height: 16),
        const SectionTitle(text: 'روابط سريعة'),
        gridRows([
          QuickTile(label: 'تقريري', sub: 'سجل مدفوعاتي', icon: 'pie', tone: 'credit', onTap: () => ctx.go('resReport')),
          QuickTile(label: 'المصعد', sub: paid ? 'رقم الهاتف' : 'مغلق', icon: 'elevator', tone: 'navy', onTap: () => ctx.go('resElevator')),
          QuickTile(label: 'الصنايعية', sub: 'أرقام موثوقة', icon: 'wrench', tone: 'gold', onTap: () => ctx.go('craftsmen')),
          QuickTile(label: 'التنبيهات', sub: 'إشعاراتي', icon: 'bell', tone: 'ok', badge: 2, onTap: () => ctx.go('alerts')),
        ], n: 2),
      ],
    );
  }
}

class ResidentReport extends StatefulWidget {
  const ResidentReport({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ResidentReport> createState() => _ResidentReportState();
}

class _ResidentReportState extends State<ResidentReport> {
  int selYear = DateTime.now().year;
  int selMonth = -1; // -1 = كل الأشهر

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final me = _meUnit(ctx);
    final res = ctx.res;

    // No occupied unit yet — render the empty state instead of an empty report.
    if (!_hasUnit(me)) {
      return ScreenScaffold(
        header: AppHeader(
          title: 'تقريري',
          onBack: () => ctx.go('resHome'),
        ),
        nav: ctx.resNav,
        children: const [
          SizedBox(height: 40),
          EmptyState(
            icon: 'pie',
            title: 'لا توجد بيانات وحدة بعد',
            sub: 'سيظهر سجل مدفوعاتك ونسبة سدادك هنا بعد ربط وحدتك.',
          ),
        ],
      );
    }
    final myPays = kPayments
        .where((p) =>
            p.unit == me.no &&
            p.year == selYear &&
            (selMonth == -1 || p.month == selMonth))
        .toList();
    final s = kStatusMap[me.status]!;

    // "المسدّد" = the resident's ACTUAL payments for the year — NOT sub×12+balance
    // (that conflated the annual requirement with the carry-over ledger and, for
    // a credited resident, showed more than they really paid — e.g. paid 600 but
    // shown 909). The month filter only narrows the history list below; the
    // ratio/donut always reflect the whole selected year.
    final paidYear = kPayments
        .where((p) => p.unit == me.no && p.year == selYear)
        .fold<int>(0, (sum, p) => sum + p.amount);
    final required = me.sub * 12;
    final paidAmt = paidYear.clamp(0, required).toInt(); // clamped for the donut
    final remaining = (required - paidYear).clamp(0, required).toInt();
    final pct = required > 0 ? ((paidYear / required) * 100).round().clamp(0, 100) : 0;

    final years = kYears.map((y) => SelectOption(y, '$y')).toList();
    final months = <SelectOption>[
      const SelectOption(-1, 'كل الأشهر'),
      for (var i = 0; i < 12; i++) SelectOption(i, monthLabelNum(i)),
    ];

    return ScreenScaffold(
      header: AppHeader(
        title: 'تقريري',
        subtitle: floorUnitLabel(me, res),
        onBack: () => ctx.go('resHome'),
        right: RoundBtn(icon: 'download', onTap: () => ctx.toast('تصدير تقريري PDF')),
      ),
      nav: ctx.resNav,
      children: [
        // Year / month selectors — payment history filters by the chosen period.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectField(
                label: 'السنة',
                icon: 'calendar',
                options: years,
                value: selYear,
                onChanged: (v) => setState(() => selYear = v as int),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField(
                label: 'الشهر',
                options: months,
                value: selMonth,
                onChanged: (v) => setState(() => selMonth = v as int),
              ),
            ),
          ],
        ),
        // Payment-ratio donut.
        AppCard(
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Donut(data: [
                      ChartDatum(label: 'مسدّد', value: paidAmt, color: AppColors.ok),
                      ChartDatum(label: 'متبقٍ', value: remaining, color: AppColors.gold500),
                    ]),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NumText('$pct%',
                            style: AppType.num(size: 20, weight: FontWeight.w800, color: AppColors.ink900)),
                        Text('نسبة السداد',
                            style: AppType.base(size: 10, weight: FontWeight.w600, color: AppColors.ink500)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ratioRow(AppColors.ok, 'المسدّد', fmtUSD(paidAmt)),
                    const SizedBox(height: 8),
                    _ratioRow(AppColors.gold500, 'المتبقّي', fmtUSD(remaining)),
                    const SizedBox(height: 8),
                    _ratioRow(AppColors.navy600, 'المطلوب سنوياً', fmtUSD(required)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Avatar(name: me.resident, size: 46, tone: 'gold'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(me.resident, style: AppType.base(size: 15, weight: FontWeight.w800)),
                        const SizedBox(height: 1),
                        Text('${me.kind} · اشتراك ${fmtUSD(me.sub)}/شهر',
                            style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppBadge(label: s.label, tone: s.tone),
                ],
              ),
              const SizedBox(height: 14),
              DetailGrid(rows: [
                DetailRow('wallet', 'المطلوب ($selYear)', fmtUSD(me.sub * 12)),
                DetailRow('checkCircle', 'المسدّد', fmtUSD(paidYear), tone: 'ok'),
                DetailRow('dollar', 'الرصيد', fmtUSD(me.balance), tone: me.balance < 0 ? 'late' : 'ok'),
                DetailRow('calendar', 'آخر دفعة', myPays.isNotEmpty ? myPays.first.date : '—', ltr: true),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionTitle(text: 'سجل مدفوعاتي'),
        AppCard(
          pad: 6,
          child: myPays.isEmpty
              ? const EmptyState(icon: 'wallet', title: 'لا توجد مدفوعات بعد')
              : Column(
                  children: List.generate(myPays.length, (i) {
                    final p = myPays[i];
                    return ListRow(
                      leading: const IconChip(icon: 'wallet', tone: 'ok', size: 40),
                      title: p.kind,
                      sub: p.method,
                      dividerBelow: i < myPays.length - 1,
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NumText('+${fmtUSD(p.amount)}', style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.ok700)),
                          const SizedBox(height: 2),
                          NumText(p.date, style: AppType.num(size: 10.5, weight: FontWeight.w600, color: AppColors.ink400)),
                        ],
                      ),
                    );
                  }),
                ),
        ),
        const SizedBox(height: 14),
        const SectionTitle(text: 'التقرير العام للمبنى'),
        AppCard(child: BarChart(data: Summary.bars)),
      ],
    );
  }

  Widget _ratioRow(Color color, String label, String value) => Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label,
                style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink600)),
          ),
          NumText(value, style: AppType.num(size: 12.5, weight: FontWeight.w800)),
        ],
      );
}

class ResidentElevator extends StatelessWidget {
  const ResidentElevator({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final me = _meUnit(ctx);
    final paid = me.status != 'late';

    // No occupied unit yet — nothing to gate the elevator number on.
    if (!_hasUnit(me)) {
      return ScreenScaffold(
        header: AppHeader(title: 'المصعد', onBack: () => ctx.go('resHome')),
        nav: ctx.resNav,
        children: const [
          SizedBox(height: 40),
          EmptyState(
            icon: 'elevator',
            title: 'لا توجد بيانات وحدة بعد',
            sub: 'سيظهر رقم هاتف المصعد هنا بعد ربط وحدتك بالمبنى.',
          ),
        ],
      );
    }

    return ScreenScaffold(
      header: AppHeader(title: 'المصعد', onBack: () => ctx.go('resHome')),
      nav: ctx.resNav,
      children: [
        const SizedBox(height: 12),
        if (paid)
          AppCard(
            raised: true,
            pad: 26,
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(22)),
                  alignment: Alignment.center,
                  child: const AppIcon('elevator', size: 36, color: AppColors.ok700),
                ),
                const SizedBox(height: 14),
                const AppBadge(label: 'اشتراكك مسدّد', tone: 'ok', icon: 'checkCircle'),
                const SizedBox(height: 14),
                Text('رقم هاتف المصعد الخاص بك',
                    style: AppType.base(size: 14, weight: FontWeight.w600, color: AppColors.ink600)),
                const SizedBox(height: 6),
                NumText(kElevPhone,
                    style: AppType.num(size: 26, weight: FontWeight.w800, color: AppColors.navy700, letterSpacing: 0.5)),
                const SizedBox(height: 18),
                AppButton(
                  label: 'اتصال بالمصعد',
                  full: true,
                  icon: 'phone',
                  onTap: () => ctx.toast('جارٍ الاتصال بالمصعد…', tone: 'info'),
                ),
              ],
            ),
          )
        else
          AppCard(
            raised: true,
            pad: 26,
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: AppColors.lateBg, borderRadius: BorderRadius.circular(22)),
                  alignment: Alignment.center,
                  child: const AppIcon('lock', size: 34, color: AppColors.late700),
                ),
                const SizedBox(height: 14),
                const AppBadge(label: 'الوصول للمصعد موقوف', tone: 'late', icon: 'alert'),
                const SizedBox(height: 14),
                Text('يوجد مبلغ متأخر بقيمة ${fmtUSD(me.balance)}',
                    textAlign: TextAlign.center,
                    style: AppType.base(size: 14.5, weight: FontWeight.w700, color: AppColors.ink700)),
                const SizedBox(height: 6),
                Text('يرجى سداد المستحقات لتفعيل خدمة المصعد وإظهار رقم الهاتف.',
                    textAlign: TextAlign.center,
                    style: AppType.base(size: 13, weight: FontWeight.w500, color: AppColors.ink600, height: 1.6)),
                const SizedBox(height: 18),
                AppButton(
                  label: 'سدّد الآن لتفعيل المصعد',
                  variant: BtnVariant.gold,
                  full: true,
                  icon: 'wallet',
                  onTap: () => ctx.toast('فتح صفحة الدفع', tone: 'info'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class MoreHub extends StatelessWidget {
  const MoreHub({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final res = ctx.res;
    final groups = <(String, List<(String, String, String)>)>[
      ('الإدارة', [
        ('building', 'إدارة المبنى', 'building2'),
        ('units', res ? 'الشقق السكنية' : 'الوحدات التجارية', res ? 'building' : 'store'),
        ('approvals', 'طلبات الانضمام', 'users'),
        ('subscribe', 'الاشتراك بالتطبيق', 'shield'),
        ('years', 'الترحيل السنوي', 'calendar'),
      ]),
      ('المالية', [
        ('payments', 'الإيرادات', 'wallet'),
        ('expenses', 'المصروفات', 'expense'),
        ('reports', 'التقارير', 'pie'),
      ]),
      ('الخدمات', [
        ('workers', 'العمال والنظافة', 'broom'),
        ('parking', 'الباركينج', 'parking'),
        ('guard', 'الحارس', 'shield'),
        ('elevator', 'المصعد', 'elevator'),
        ('craftsmen', 'الصنايعية', 'wrench'),
        ('alerts', 'التنبيهات', 'bell'),
      ]),
    ];
    const toneFor = {
      'building': 'navy', 'units': 'navy', 'years': 'credit', 'approvals': 'gold',
      'subscribe': 'navy',
      'payments': 'ok', 'expenses': 'late', 'reports': 'credit',
      'workers': 'ok', 'parking': 'gold', 'guard': 'navy',
      'elevator': 'navy', 'craftsmen': 'gold', 'alerts': 'warn',
    };

    return ScreenScaffold(
      header: const AppHeader(accent: true, title: 'المزيد', subtitle: 'كل أدوات الإدارة'),
      nav: ctx.adminNav,
      children: [
        ...groups.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle(text: g.$1),
                  AppCard(
                    pad: 6,
                    child: Column(
                      children: List.generate(g.$2.length, (i) {
                        final it = g.$2[i];
                        return ListRow(
                          leading: IconChip(icon: it.$3, tone: toneFor[it.$1] ?? 'navy', size: 40),
                          title: it.$2,
                          chevron: true,
                          dividerBelow: i < g.$2.length - 1,
                          onTap: () => ctx.go(it.$1),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            )),
        AppCard(
          pad: 6,
          child: Column(
            children: [
              ListRow(
                leading: const IconChip(icon: 'switch', tone: 'credit', size: 40),
                title: 'تبديل الدور / الحساب',
                chevron: true,
                dividerBelow: true,
                onTap: ctx.openRole,
              ),
              ListRow(
                leading: const IconChip(icon: 'logout', tone: 'late', size: 40),
                title: 'تسجيل الخروج',
                onTap: () => showConfirmSheet(
                  context,
                  title: 'تسجيل الخروج',
                  message: 'هل تريد تسجيل الخروج؟ ستحتاج إلى تسجيل الدخول مرة أخرى للوصول إلى حسابك.',
                  confirmLabel: 'تسجيل الخروج',
                  onConfirm: () => ctx.signOut(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

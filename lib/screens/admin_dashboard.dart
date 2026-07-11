// عمارتي — Admin: Dashboard (hero layout) + Building settings.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // Dashboard period: a year + an optional 0-based month (null = whole year).
  // Prefer the current year when it has data on record; else the latest year.
  late int selYear = kYears.contains(DateTime.now().year)
      ? DateTime.now().year
      : (kYears.isNotEmpty ? kYears.last : DateTime.now().year);
  int? selMonth; // null = whole year (matches the bundle's default summary)
  bool _loadingPeriod = false;

  @override
  void initState() {
    super.initState();
    // The bundle's first /summary is for the current year with no month; if the
    // dashboard's default period differs (e.g. a later record year), the quick
    // summary looks empty until the user touches a dropdown. Align it on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPeriod();
    });
  }

  String get _periodLabel =>
      selMonth == null ? 'سنة $selYear' : '${monthLabelNum(selMonth!)} $selYear';

  Future<void> _applyPeriod({int? year, Object? month = _unset}) async {
    setState(() {
      if (year != null) selYear = year;
      if (!identical(month, _unset)) selMonth = month as int?;
      _loadingPeriod = true;
    });
    try {
      await Api.I.fetchSummary(widget.ctx.btype, year: selYear, month: selMonth);
    } catch (_) {}
    if (mounted) setState(() => _loadingPeriod = false);
  }

  static const _unset = Object();

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final res = ctx.res;
    final b = ctx.building;
    final tiles = [
      QuickTile(label: res ? 'الشقق السكنية' : 'الوحدات التجارية', sub: res ? 'الشقق والملاك' : 'الوحدات والملاك', icon: res ? 'building' : 'store', tone: 'navy', onTap: () => ctx.go('units')),
      QuickTile(label: 'الإيرادات', sub: 'تسجيل ومتابعة دفعات السكان', icon: 'wallet', tone: 'gold', onTap: () => ctx.go('payments')),
      QuickTile(label: 'المصروفات', sub: 'إدارة المصروفات', icon: 'expense', tone: 'late', onTap: () => ctx.go('expenses')),
      QuickTile(label: 'التقارير', sub: 'تقارير شاملة', icon: 'pie', tone: 'credit', onTap: () => ctx.go('reports')),
      QuickTile(label: 'المصعد', sub: 'صلاحية الوصول', icon: 'elevator', tone: 'navy', onTap: () => ctx.go('elevator')),
      QuickTile(label: 'التنبيهات', sub: 'إشعارات وتذكير', icon: 'bell', tone: 'ok', badge: kAlerts.length, onTap: () => ctx.go('alerts')),
    ];

    return ScreenScaffold(
      header: AppHeader(
        accent: true,
        logo: true,
        right: Row(mainAxisSize: MainAxisSize.min, children: [
          RoundBtn(icon: 'bell', dark: true, badge: kAlerts.isNotEmpty, onTap: () => ctx.go('alerts')),
          const SizedBox(width: 8),
          RoundBtn(
              icon: 'logout',
              dark: true,
              onTap: () => showConfirmSheet(
                    context,
                    title: 'تسجيل الخروج',
                    message: 'هل تريد تسجيل الخروج من حساب الإدارة؟ ستحتاج إلى تسجيل الدخول مرة أخرى.',
                    confirmLabel: 'تسجيل الخروج',
                    onConfirm: () => ctx.signOut(),
                  )),
        ]),
      ),
      nav: ctx.adminNav,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.name.trim().isNotEmpty ? b.name : 'لوحة التحكم',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.base(size: 17, weight: FontWeight.w800, color: AppColors.ink900)),
              if (b.address.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(b.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink500)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: appGradient(const [AppColors.navy700, AppColors.navy800]),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  boxShadow: AppShadows.navy,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(b.name.trim().isNotEmpty ? b.name : (res ? 'المبنى السكني' : 'المبنى التجاري'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.base(size: 12.5, weight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('${res ? 'سكني' : 'تجاري'} · ${b.units} وحدة · ${b.currency}',
                        style: AppType.base(size: 10, weight: FontWeight.w500, color: AppColors.navy300)),
                    const SizedBox(height: 12),
                    Text('الرصيد الحالي',
                        style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.navy300)),
                    const SizedBox(height: 6),
                    NumText(fmtUSD(Summary.balance),
                        style: AppType.num(size: 22, weight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 4),
                    // رصيد الصندوق = إجمالي الإيرادات ناقص المصروفات.
                    Text('الإيرادات − المصروفات · للعام $selYear',
                        style: AppType.base(size: 10, weight: FontWeight.w500, color: AppColors.navy300)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(builder: (_) {
                // ذمم السكان: موجب = مطلوب من السكان (مدين)، سالب = رصيد دائن لهم.
                final credit = Summary.due < 0;
                final tone = credit ? AppColors.credit700 : AppColors.late700;
                final bg = credit ? AppColors.creditBg : AppColors.lateBg;
                final border = credit ? AppColors.credit : AppColors.late;
                return Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: border.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الذمم',
                          style: AppType.base(size: 11.5, weight: FontWeight.w600, color: tone)),
                      const SizedBox(height: 6),
                      NumText(fmtUSD(Summary.due.abs()),
                          style: AppType.num(size: 22, weight: FontWeight.w800, color: tone)),
                      const SizedBox(height: 4),
                      Text(credit ? 'رصيد دائن للسكان' : 'مطلوب من السكان (مدين)',
                          style: AppType.base(size: 10, weight: FontWeight.w500, color: tone)),
                    ],
                  ),
                );
              }),
            ),
          ],
          ),
        ),
        const SizedBox(height: 14),
        gridRows(tiles, n: 3),
        const SizedBox(height: 16),
        SectionTitle(
          text: 'ملخص سريع — $_periodLabel',
          action: 'عرض التقارير',
          onAction: () => ctx.go('reports'),
        ),
        // Period filter — the totals below (and the cash balance) follow it.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectField(
                  label: 'السنة',
                  icon: 'calendar',
                  options: [for (final y in (kYears.isNotEmpty ? kYears : [selYear])) SelectOption(y, '$y')],
                  value: selYear,
                  onChanged: (v) => _applyPeriod(year: v as int),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectField(
                  label: 'الفترة',
                  icon: 'calendar',
                  options: [
                    const SelectOption(-1, 'كل السنة'),
                    for (var i = 0; i < 12; i++) SelectOption(i, monthLabelNum(i)),
                  ],
                  value: selMonth ?? -1,
                  onChanged: (v) {
                    final m = v as int;
                    _applyPeriod(month: m < 0 ? null : m);
                  },
                ),
              ),
            ],
          ),
        ),
        if (_loadingPeriod)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        // ثلاثة أعمدة فقط، القيمة فوق كل عمود (label2). الذمم بالقيمة المطلقة.
        AppCard(
          child: BarChart(data: [
            ChartDatum(
                label: 'الاشتراكات',
                value: Summary.revenueM,
                color: AppColors.ok,
                label2: fmtUSD(Summary.revenueM)),
            ChartDatum(
                label: 'المصروفات',
                value: Summary.expenseM,
                color: AppColors.late,
                label2: fmtUSD(Summary.expenseM)),
            ChartDatum(
                label: 'الذمم',
                value: Summary.due.abs(),
                color: AppColors.gold500,
                label2: fmtUSD(Summary.due.abs())),
          ]),
        ),
      ],
    );
  }
}

class BuildingScreen extends StatelessWidget {
  const BuildingScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final b = ctx.building;
    final res = ctx.res;

    Widget row(String icon, String label, Widget value, {String tone = 'navy', bool divider = true}) =>
        ListRow(
          leading: IconChip(icon: icon, tone: tone, size: 40),
          title: label,
          trailing: value,
          dividerBelow: divider,
        );

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة المبنى',
        subtitle: 'الإعدادات العامة',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'edit', onTap: () => _openEdit(context, ctx, b, res)),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: appGradient(const [AppColors.navy700, AppColors.navy800]),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.navy,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(15)),
                        alignment: Alignment.center,
                        child: AppIcon(res ? 'building2' : 'store', size: 28, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(b.name,
                                style: AppType.base(size: 18, weight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const AppIcon('pin', size: 14, color: AppColors.navy300),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(b.address,
                                      style: AppType.base(
                                          size: 12.5, weight: FontWeight.w500, color: AppColors.navy300)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppBadge(label: res ? 'سكني' : 'تجاري', tone: 'gold', icon: res ? 'building' : 'store'),
                      AppBadge(label: '${b.floors} أدوار', tone: 'navy', icon: 'layers'),
                      AppBadge(label: '${b.units} وحدة', tone: 'navy', icon: 'grid'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'الإعدادات الافتراضية'),
        AppCard(
          pad: 6,
          child: Column(
            children: [
              row('wallet', 'الاشتراك الافتراضي',
                  Text('${fmtUSD(b.subscription)} / شهر',
                      style: AppType.base(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
                  tone: 'gold'),
              row('dollar', 'العملة',
                  Text('${b.currency} (${currencySymbol(b.currency)})',
                      style: AppType.base(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
                  tone: 'ok'),
              row('elevator', 'رسوم المصعد',
                  Text(fmtUSD(b.elevatorFee),
                      style: AppType.base(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
                  divider: false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'إدارة سريعة'),
        gridRows([
          QuickTile(label: res ? 'الشقق' : 'الوحدات', sub: 'الوحدات والملاك', icon: res ? 'building' : 'store', tone: 'navy', onTap: () => ctx.go('units')),
          QuickTile(label: 'الباركينج', sub: 'المواقف', icon: 'parking', tone: 'gold', onTap: () => ctx.go('parking')),
          QuickTile(label: 'الحارس', sub: 'بيانات الحارس', icon: 'shield', tone: 'ok', onTap: () => ctx.go('guard')),
          QuickTile(label: 'الترحيل السنوي', sub: 'الأرصدة الافتتاحية والترحيل', icon: 'calendar', tone: 'credit', onTap: () => ctx.go('years')),
          QuickTile(label: 'طلبات الانضمام', sub: 'الموافقة على السكان', icon: 'users', tone: 'gold', onTap: () => ctx.go('approvals')),
          QuickTile(label: 'الاشتراك بالتطبيق', sub: 'تفعيل الاشتراك بالتطبيق', icon: 'shield', tone: 'navy', onTap: () => ctx.go('subscribe')),
          QuickTile(label: 'مسؤول مساعد', sub: 'إضافة مسؤول للمبنى', icon: 'users', tone: 'credit', onTap: () => _openCoAdmin(context, ctx)),
          QuickTile(label: 'الرسوم', sub: 'تعريف بنود الرسوم وقيمها الافتراضية', icon: 'wallet', tone: 'gold', onTap: () => _openPayTypes(context, ctx)),
        ], n: 2),
      ],
    );
  }

  /// Edit the building's general settings (mock-saves with a toast).
  void _openEdit(BuildContext context, Ctx ctx, Building b, bool res) {
    final f = {
      'name': b.name,
      'address': b.address,
      'floors': '${b.floors}',
      'units': '${b.units}',
      'sub': '${b.subscription}',
      'elevator': '${b.elevatorFee}',
    };
    BType type = ctx.btype;
    Object currency = b.currency;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل بيانات المبنى',
          footer: AppButton(
            label: 'حفظ التعديلات',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updateBuilding(ctx.btype, {
                  'name': f['name'],
                  'address': f['address'],
                  'floors': int.tryParse(f['floors']!.trim()) ?? b.floors,
                  'units_count': int.tryParse(f['units']!.trim()) ?? b.units,
                  'subscription': int.tryParse(f['sub']!.trim()) ?? b.subscription,
                  'currency': currency,
                  'elevator_fee': int.tryParse(f['elevator']!.trim()) ?? b.elevatorFee,
                });
                await ctx.reload();
                ctx.toast('تم حفظ بيانات المبنى');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'اسم المبنى', icon: 'building2', value: f['name']!, onChanged: (v) => f['name'] = v),
            Field(label: 'العنوان', icon: 'pin', value: f['address']!, onChanged: (v) => f['address'] = v),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('نوع المبنى',
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
            Segmented(
              value: type,
              onChanged: (v) => setS(() => type = v as BType),
              options: const [
                SegOption(BType.residential, 'سكني (شقق)', icon: 'building'),
                SegOption(BType.commercial, 'تجاري (وحدات)', icon: 'store'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Field(
                      label: 'عدد الطوابق',
                      icon: 'layers',
                      value: f['floors']!,
                      ltr: true,
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                      onChanged: (v) => f['floors'] = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Field(
                      label: res ? 'عدد الشقق' : 'عدد الوحدات',
                      icon: 'grid',
                      value: f['units']!,
                      ltr: true,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => f['units'] = v),
                ),
              ],
            ),
            Field(
                label: 'الاشتراك الشهري',
                icon: 'wallet',
                value: f['sub']!,
                ltr: true,
                suffix: currencySymbol(currency as String),
                keyboardType: TextInputType.number,
                onChanged: (v) => f['sub'] = v),
            SelectField(
              label: 'عملة المبنى',
              icon: 'dollar',
              options: [for (final c in kCurrencyCodes) SelectOption(c, '$c (${currencySymbol(c)})')],
              value: currency,
              onChanged: (v) => setS(() => currency = v),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Field(
                      label: 'رسوم المصعد',
                      icon: 'elevator',
                      value: f['elevator']!,
                      ltr: true,
                      suffix: currencySymbol(currency as String),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => f['elevator'] = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Building admin creates a co-admin for the same building.
  void _openCoAdmin(BuildContext context, Ctx ctx) {
    final f = {'name': '', 'email': '', 'password': ''};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إضافة مسؤول مساعد',
          footer: AppButton(
            label: 'إنشاء المسؤول',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['name']!.trim().isEmpty ||
                f['email']!.trim().isEmpty ||
                f['password']!.trim().length < 6,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createCoAdmin(ctx.btype, {
                  'name': f['name']!.trim(),
                  'email': f['email']!.trim(),
                  'password': f['password']!.trim(),
                });
                ctx.toast('تم إنشاء حساب المسؤول المساعد');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Text('سيتمكّن هذا المسؤول من إدارة نفس المبنى (الدفعات والمصروفات والوحدات…).',
                style: AppType.base(size: 12, weight: FontWeight.w500, color: AppColors.ink500, height: 1.5)),
            const SizedBox(height: 12),
            Field(label: 'الاسم', icon: 'user', placeholder: 'اسم المسؤول', onChanged: (v) => setS(() => f['name'] = v)),
            Field(
                label: 'البريد الإلكتروني',
                icon: 'mail',
                placeholder: 'admin@email.com',
                ltr: true,
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => setS(() => f['email'] = v)),
            Field(
                label: 'كلمة المرور',
                icon: 'lock',
                placeholder: '6 أحرف على الأقل',
                ltr: true,
                onChanged: (v) => setS(() => f['password'] = v)),
          ],
        ),
      ),
    );
  }

  /// List the building's payment types/fees; tap ✎ to edit amount + enabled.
  void _openPayTypes(BuildContext context, Ctx ctx) {
    showAppSheet(
      context,
      SheetShell(
        title: 'الرسوم وأنواع الدفعات',
        children: [
          for (final pt in kPayTypes)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(child: Text(pt.label, style: AppType.base(size: 14, weight: FontWeight.w700))),
                NumText(fmtUSD(pt.amount),
                    style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.gold700)),
                const SizedBox(width: 10),
                RoundBtn(icon: 'edit', onTap: () {
                  Navigator.of(context).pop();
                  _openEditPayType(context, ctx, pt);
                }),
              ]),
            ),
          const SizedBox(height: 4),
          Text('اضغط ✎ لتعديل قيمة أو تفعيل أي رسم.',
              style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
        ],
      ),
    );
  }

  void _openEditPayType(BuildContext context, Ctx ctx, PayType pt) {
    final f = {'amount': '${pt.amount}'};
    bool enabled = pt.on;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل: ${pt.label}',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updatePayType(pt.dbId, {
                  'amount': int.tryParse(f['amount']!.trim()) ?? pt.amount,
                  'enabled': enabled,
                });
                await ctx.reload();
                ctx.toast('تم تحديث الرسم');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'القيمة', icon: 'wallet', value: f['amount']!, ltr: true, keyboardType: TextInputType.number, onChanged: (v) => f['amount'] = v),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(child: Text('مُفعّل', style: AppType.base(size: 14, weight: FontWeight.w700))),
                AppSwitch(checked: enabled, onChanged: (v) => setS(() => enabled = v)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

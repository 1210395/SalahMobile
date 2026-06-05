// عمارتي — Admin: Reports, Alerts & Messages, Years.

import 'package:flutter/material.dart';

import '../common.dart';

// ───────────────────────────── Reports ─────────────────────────────

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String tab = 'monthly';

  static const List<ChartDatum> _expData = [
    ChartDatum(label: 'مصعد', value: 350, color: AppColors.navy600),
    ChartDatum(label: 'نظافة', value: 200, color: AppColors.ok),
    ChartDatum(label: 'كهرباء', value: 180, color: AppColors.warn),
    ChartDatum(label: 'صيانة', value: 90, color: AppColors.credit),
    ChartDatum(label: 'أخرى', value: 60, color: AppColors.gold500),
  ];

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final lateUnits =
        (ctx.res ? kApartments : kShops).where((u) => u.status == 'late').toList();
    final expTotal = _expData.fold<num>(0, (s, d) => s + d.value).toInt();

    return ScreenScaffold(
      header: AppHeader(
        title: 'التقارير',
        subtitle: 'تحليل شامل للمبنى',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'download', onTap: () => ctx.toast('تم تصدير التقرير PDF')),
      ),
      nav: ctx.adminNav,
      children: [
        Segmented(
          small: true,
          value: tab,
          onChanged: (v) => setState(() => tab = v as String),
          options: const [
            SegOption('monthly', 'شهري'),
            SegOption('annual', 'سنوي'),
            SegOption('unit', 'وحدة'),
            SegOption('expense', 'مصروفات'),
          ],
        ),
        const SizedBox(height: 14),
        if (tab == 'monthly') ..._monthly(lateUnits),
        if (tab == 'annual') ..._annual(),
        if (tab == 'unit') ..._unit(ctx),
        if (tab == 'expense') ..._expense(expTotal),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: AppButton(
                label: 'PDF', variant: BtnVariant.outline, full: true, icon: 'file', onTap: () => ctx.toast('تصدير PDF')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
                label: 'Excel', variant: BtnVariant.outline, full: true, icon: 'excel', onTap: () => ctx.toast('تصدير Excel')),
          ),
        ]),
      ],
    );
  }

  List<Widget> _monthly(List<Unit> lateUnits) => [
        Row(children: [
          Expanded(child: StatCard(label: 'إجمالي محصّل', value: fmtUSD(Summary.revenueM), icon: 'trend', tone: 'ok')),
          const SizedBox(width: 10),
          Expanded(child: StatCard(label: 'متبقٍ', value: fmtUSD(Summary.due), icon: 'alert', tone: 'gold')),
        ]),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(text: 'الحركة الشهرية', margin: EdgeInsets.only(bottom: 10)),
              BarChart(data: Summary.bars),
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
              ...List.generate(lateUnits.length, (i) {
                final u = lateUnits[i];
                return ListRow(
                  leading: Avatar(name: u.resident, size: 38, tone: 'navy'),
                  title: u.resident,
                  sub: 'وحدة ${u.no}',
                  dividerBelow: i < lateUnits.length - 1,
                  trailing: NumText(fmtUSD(u.balance),
                      style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.late700)),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ];

  List<Widget> _annual() => [
        HeroBanner(
          gradient: const [AppColors.navy700, AppColors.navy800],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الرصيد النهائي — 2026',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.navy300)),
              const SizedBox(height: 6),
              NumText(fmtUSD(Summary.balance),
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
              BarChart(data: Summary.trend),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatCard(label: 'إجمالي الإيرادات', value: fmtUSD(38400), icon: 'trend', tone: 'ok')),
          const SizedBox(width: 10),
          Expanded(child: StatCard(label: 'إجمالي المصروفات', value: fmtUSD(22150), icon: 'expense', tone: 'late')),
        ]),
        const SizedBox(height: 12),
      ];

  List<Widget> _unit(Ctx ctx) => [
        SelectField(
          label: 'اختر الوحدة',
          icon: 'building',
          options: (ctx.res ? kApartments : kShops)
              .where((u) => u.status != 'vacant')
              .map((u) => SelectOption(u.no, '${u.no} — ${u.resident}'))
              .toList(),
          value: '101',
          onChanged: (_) {},
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Avatar(name: 'أحمد العامري', size: 46),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('أحمد العامري', style: AppType.base(size: 15, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('شقة 101 · مالك',
                          style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                    ],
                  ),
                  const Spacer(),
                  const AppBadge(label: 'مسدد', tone: 'ok', icon: 'checkCircle'),
                ],
              ),
              const SizedBox(height: 14),
              DetailGrid(rows: [
                DetailRow('wallet', 'المطلوب سنوياً', fmtUSD(480)),
                DetailRow('checkCircle', 'المسدّد', fmtUSD(480), tone: 'ok'),
                DetailRow('dollar', 'الرصيد', fmtUSD(0), tone: 'ok'),
                DetailRow('calendar', 'آخر دفعة', '2026-05-01', ltr: true),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ];

  List<Widget> _expense(int expTotal) => [
        AppCard(
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Donut(data: _expData),
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
                  children: _expData
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

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final isAdmin = ctx.role == AppRole.admin;

    return ScreenScaffold(
      header: AppHeader(
        title: 'التنبيهات والرسائل',
        onBack: () => ctx.go(isAdmin ? 'home' : 'resHome'),
        right: RoundBtn(icon: 'settings', onTap: () => setState(() => tab = 'settings')),
      ),
      nav: isAdmin ? ctx.adminNav : ctx.resNav,
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
          ...kAlerts.map((a) => Padding(
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
  int year = 2026;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final units = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').length;

    return ScreenScaffold(
      header: AppHeader(
        title: 'السنوات والأشهر',
        subtitle: 'متابعة الدفع شهرياً',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'plus', onTap: () => ctx.toast('تمت إضافة سنة جديدة')),
      ),
      nav: ctx.adminNav,
      children: [
        Row(
          children: [2024, 2025, 2026].map((y) {
            final on = year == y;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: y != 2026 ? 8 : 0),
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
              final pct = ((m.paid / m.total) * 100).round();
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
                      width: 44,
                      child: Text(arMonths[m.m], style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.ink700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: m.paid / m.total,
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
          child: Text('$units وحدة فعّالة في $year',
              style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink400)),
        ),
      ],
    );
  }
}

// عمارتي — Admin: Dashboard (hero layout) + Building settings.

import 'package:flutter/material.dart';

import '../common.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final res = ctx.res;
    final tiles = [
      QuickTile(label: res ? 'الوحدات' : 'المحلات', sub: res ? 'الشقق والملاك' : 'المحلات والملاك', icon: res ? 'building' : 'store', tone: 'navy', onTap: () => ctx.go('units')),
      QuickTile(label: 'المستحقات', sub: 'متابعة التحصيل', icon: 'wallet', tone: 'gold', onTap: () => ctx.go('payments')),
      QuickTile(label: 'المصروفات', sub: 'إدارة المصروفات', icon: 'expense', tone: 'late', onTap: () => ctx.go('expenses')),
      QuickTile(label: 'التقارير', sub: 'تقارير شاملة', icon: 'pie', tone: 'credit', onTap: () => ctx.go('reports')),
      QuickTile(label: 'المصعد', sub: 'صلاحية الوصول', icon: 'elevator', tone: 'navy', onTap: () => ctx.go('elevator')),
      QuickTile(label: 'التنبيهات', sub: 'إشعارات وتذكير', icon: 'bell', tone: 'ok', badge: 3, onTap: () => ctx.go('alerts')),
    ];

    return ScreenScaffold(
      header: AppHeader(
        accent: true,
        logo: true,
        right: Row(mainAxisSize: MainAxisSize.min, children: [
          RoundBtn(icon: 'switch', dark: true, onTap: ctx.openRole),
          const SizedBox(width: 8),
          RoundBtn(icon: 'bell', dark: true, badge: true, onTap: () => ctx.go('alerts')),
        ]),
      ),
      nav: ctx.adminNav,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
          child: Text('لوحة التحكم · ${ctx.building.name}',
              style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink500)),
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
                    Text('الرصيد الحالي',
                        style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.navy300)),
                    const SizedBox(height: 6),
                    NumText(fmtUSD(Summary.balance),
                        style: AppType.num(size: 22, weight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.gold50,
                  border: Border.all(color: AppColors.gold200),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('المستحقات',
                        style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.gold700)),
                    const SizedBox(height: 6),
                    NumText(fmtUSD(Summary.due),
                        style: AppType.num(size: 22, weight: FontWeight.w800, color: AppColors.gold700)),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
        const SizedBox(height: 14),
        gridRows(tiles, n: 3),
        const SizedBox(height: 16),
        SectionTitle(
          text: 'ملخص سريع — هذا الشهر',
          action: 'عرض التقارير',
          onAction: () => ctx.go('reports'),
        ),
        AppCard(child: BarChart(data: Summary.bars)),
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
        right: RoundBtn(icon: 'edit', onTap: () => ctx.toast('وضع التعديل', tone: 'info')),
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
              const BranchMotif(),
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
                  Text('دولار أمريكي (\$)',
                      style: AppType.base(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
                  tone: 'ok'),
              row('elevator', 'رسوم المصعد',
                  Text(fmtUSD(15),
                      style: AppType.base(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700))),
              row('refresh', 'سعر الصرف',
                  NumText('\$1 = 3.75 ﷼',
                      style: AppType.num(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
                  tone: 'credit', divider: false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'إدارة سريعة'),
        gridRows([
          QuickTile(label: res ? 'الشقق' : 'المحلات', sub: 'الوحدات والملاك', icon: res ? 'building' : 'store', tone: 'navy', onTap: () => ctx.go('units')),
          QuickTile(label: 'الباركينج', sub: 'المواقف', icon: 'parking', tone: 'gold', onTap: () => ctx.go('parking')),
          QuickTile(label: 'الحارس', sub: 'بيانات الحارس', icon: 'shield', tone: 'ok', onTap: () => ctx.go('guard')),
          QuickTile(label: 'السنوات', sub: 'الأشهر والأرصدة', icon: 'calendar', tone: 'credit', onTap: () => ctx.go('years')),
        ], n: 2),
      ],
    );
  }
}

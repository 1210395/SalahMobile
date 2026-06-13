// عمارتي — Admin: Dashboard (hero layout) + Building settings.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';

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
          QuickTile(label: 'طلبات الانضمام', sub: 'الموافقة على السكان', icon: 'users', tone: 'gold', onTap: () => ctx.go('approvals')),
          QuickTile(label: 'الاشتراك والإعداد', sub: 'تفعيل ثم إعداد المبنى', icon: 'shield', tone: 'navy', onTap: () => ctx.go('subscribe')),
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
    };
    BType type = ctx.btype;
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
                SegOption(BType.commercial, 'تجاري (محلات)', icon: 'store'),
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
                      keyboardType: TextInputType.number,
                      onChanged: (v) => f['floors'] = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Field(
                      label: res ? 'عدد الشقق' : 'عدد المحلات',
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
                suffix: '\$',
                marginBottom: 0,
                keyboardType: TextInputType.number,
                onChanged: (v) => f['sub'] = v),
          ],
        ),
      ),
    );
  }
}

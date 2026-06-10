// عمارتي — Admin: Guard, Elevator access, Craftsmen.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';

const String kElevPhone = '+966 92 000 1234';

// ───────────────────────────── Guard ─────────────────────────────

class GuardScreen extends StatelessWidget {
  const GuardScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final g = kGuard;
    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة الحارس',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'edit', onTap: () => ctx.toast('تعديل البيانات', tone: 'info')),
      ),
      nav: ctx.adminNav,
      children: [
        AppCard(
          raised: true,
          child: Column(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(color: AppColors.navy50, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const AppIcon('user', size: 48, color: AppColors.navy300),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.gold500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                        alignment: Alignment.center,
                        child: const AppIcon('camera', size: 16, color: Color(0xFF3A2F0C)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(g.name, style: AppType.base(size: 19, weight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('حارس المبنى',
                  style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink500)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: AppButton(
                      label: 'اتصال', variant: BtnVariant.ghost, full: true, icon: 'phone', onTap: () => ctx.toast('اتصال…', tone: 'info')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                      label: 'واتساب', variant: BtnVariant.ghost, full: true, icon: 'whatsapp', onTap: () => ctx.toast('فتح واتساب', tone: 'info')),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'البيانات'),
        AppCard(
          pad: 6,
          child: Column(
            children: [
              ListRow(
                leading: const IconChip(icon: 'phone', tone: 'navy', size: 40),
                title: 'الجوال',
                dividerBelow: true,
                trailing: NumText(g.phone, style: AppType.num(size: 13.5, weight: FontWeight.w700, color: AppColors.ink700)),
              ),
              ListRow(
                leading: const IconChip(icon: 'pin', tone: 'credit', size: 40),
                title: 'العنوان',
                dividerBelow: true,
                trailing: Text(g.address, style: AppType.base(size: 12.5, weight: FontWeight.w700, color: AppColors.ink700)),
              ),
              ListRow(
                leading: const IconChip(icon: 'wallet', tone: 'gold', size: 40),
                title: 'الأجرة الشهرية (اختياري)',
                trailing: NumText(fmtUSD(g.fee), style: AppType.num(size: 14, weight: FontWeight.w800, color: AppColors.gold700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'الدفعات'),
        Row(children: [
          Expanded(child: _payCard('آخر دفعة', g.last, AppColors.ok700)),
          const SizedBox(width: 10),
          Expanded(child: _payCard('الاستحقاق القادم', g.next, AppColors.late700)),
        ]),
        const SizedBox(height: 14),
        AppButton(
          label: 'تسجيل دفعة جديدة',
          full: true,
          icon: 'wallet',
          onTap: () => ctx.toast('تم تسجيل دفعة الحارس'),
        ),
      ],
    );
  }

  Widget _payCard(String label, String value, Color color) => AppCard(
        pad: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
            const SizedBox(height: 6),
            NumText(value, style: AppType.num(size: 15, weight: FontWeight.w800, color: color)),
          ],
        ),
      );
}

// ───────────────────────────── Elevator access ─────────────────────────────

class ElevatorScreen extends StatefulWidget {
  const ElevatorScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ElevatorScreen> createState() => _ElevatorScreenState();
}

class _ElevatorScreenState extends State<ElevatorScreen> {
  late final List<Unit> base =
      (widget.ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
  late final Map<String, bool> access = {for (final u in base) u.id: u.status != 'late'};

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final allowed = access.values.where((v) => v).length;

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة الوصول للمصعد',
        subtitle: '$allowed من ${base.length} مصرّح لهم',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'download', onTap: () => ctx.toast('تم تصدير قائمة المصرّح لهم')),
      ),
      nav: ctx.adminNav,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: appGradient(const [AppColors.navy700, AppColors.navy800]),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: const AppIcon('elevator', size: 26, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('رقم هاتف المصعد (للمصرّح لهم)',
                        style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.navy300)),
                    const SizedBox(height: 3),
                    NumText(kElevPhone, style: AppType.num(size: 17, weight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text('فعّل الوصول للوحدات المسدّدة. الوحدات المتأخرة تُمنع تلقائياً.',
              style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
        ),
        AppCard(
          pad: 6,
          child: Column(
            children: List.generate(base.length, (i) {
              final u = base[i];
              final on = access[u.id]!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                decoration: BoxDecoration(
                  border: i < base.length - 1
                      ? const Border(bottom: BorderSide(color: AppColors.line))
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.navy700, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: NumText(u.no, style: AppType.num(size: 13, weight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(u.resident,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.base(size: 14, weight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Row(children: [
                            AppIcon(on ? 'checkCircle' : 'xCircle', size: 14, color: on ? AppColors.ok700 : AppColors.late700),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                on ? 'مصرّح — يظهر رقم المصعد' : 'ممنوع — رسالة تذكير بالسداد',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.base(
                                    size: 11.5,
                                    weight: FontWeight.w700,
                                    color: on ? AppColors.ok700 : AppColors.late700),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppSwitch(checked: on, onChanged: (v) => setState(() => access[u.id] = v)),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: 'تصدير قائمة المصرّح لهم',
          variant: BtnVariant.outline,
          full: true,
          icon: 'download',
          onTap: () => ctx.toast('تم تصدير القائمة'),
        ),
      ],
    );
  }
}

// ───────────────────────────── Craftsmen ─────────────────────────────

class CraftsmenScreen extends StatefulWidget {
  const CraftsmenScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<CraftsmenScreen> createState() => _CraftsmenScreenState();
}

class _CraftsmenScreenState extends State<CraftsmenScreen> {
  String q = '';
  String job = 'all';

  static const Map<String, String> _jobIcon = {
    'سباكة': 'wrench',
    'كهرباء': 'alert',
    'نجارة': 'wrench',
    'تكييف': 'refresh',
    'دهان': 'edit',
  };

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final isAdmin = ctx.role == AppRole.admin;
    final jobs = ['all', ...{for (final c in kCraftsmen) c.job}];
    final list = kCraftsmen.where((c) {
      final matchJob = job == 'all' || c.job == job;
      final matchQ = q.isEmpty || c.name.contains(q) || c.job.contains(q);
      return matchJob && matchQ;
    }).toList();

    return ScreenScaffold(
      header: AppHeader(
        title: 'قائمة الصنايعية',
        subtitle: 'أرقام موثوقة للصيانة',
        onBack: () => ctx.go('home'),
        right: isAdmin ? RoundBtn(icon: 'plus', onTap: () => _openAdd(ctx)) : null,
      ),
      nav: isAdmin ? ctx.adminNav : ctx.resNav,
      fab: isAdmin ? AppFab(icon: 'plus', label: 'إضافة', onTap: () => _openAdd(ctx)) : null,
      children: [
        Field(
          icon: 'search',
          placeholder: 'ابحث بالاسم أو المهنة',
          onChanged: (v) => setState(() => q = v),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final j = jobs[i];
              final on = job == j;
              return GestureDetector(
                onTap: () => setState(() => job = j),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.navy700 : AppColors.surface,
                    border: Border.all(color: on ? AppColors.navy700 : AppColors.line2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(j == 'all' ? 'الكل' : j,
                      style: AppType.base(size: 12.5, weight: FontWeight.w700, color: on ? Colors.white : AppColors.ink600)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(icon: 'wrench', title: 'لا يوجد صنايعية', sub: 'جرّب بحثاً آخر')
        else
          ...List.generate(list.length, (i) {
            final c = list[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < list.length - 1 ? 10 : 0),
              child: AppCard(
                pad: 13,
                child: Row(
                  children: [
                    IconChip(icon: _jobIcon[c.job] ?? 'wrench', tone: 'gold', size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.name, style: AppType.base(size: 14.5, weight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Row(children: [
                            AppBadge(label: c.job, tone: 'navy', small: true),
                            if (c.note.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(c.note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pressable(
                      onTap: () => ctx.toast('اتصال بـ ${c.name}', tone: 'info'),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: const AppIcon('phone', size: 22, color: AppColors.ok700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _openAdd(Ctx ctx) {
    final f = {'name': '', 'job': '', 'phone': '', 'note': ''};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إضافة صنايعي',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['name']!.trim().isEmpty ||
                f['job']!.trim().isEmpty ||
                f['phone']!.trim().isEmpty,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createCraftsman({
                  'name': f['name']!.trim(),
                  'job': f['job']!.trim(),
                  'phone': f['phone']!.trim(),
                  'note': f['note'],
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
                placeholder: 'اسم الصنايعي',
                onChanged: (v) => setS(() => f['name'] = v)),
            Field(
                label: 'المهنة',
                icon: 'wrench',
                placeholder: 'سباكة، كهرباء…',
                onChanged: (v) => setS(() => f['job'] = v)),
            Field(
                label: 'الجوال',
                icon: 'phone',
                placeholder: '5X XXX XXXX',
                ltr: true,
                keyboardType: TextInputType.phone,
                onChanged: (v) => setS(() => f['phone'] = v)),
            AppTextArea(
                label: 'ملاحظات',
                placeholder: 'ملاحظة اختيارية…',
                rows: 2,
                onChanged: (v) => f['note'] = v),
          ],
        ),
      ),
    );
  }
}

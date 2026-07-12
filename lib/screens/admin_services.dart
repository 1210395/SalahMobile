// عمارتي — Admin: Guard, Elevator access, Craftsmen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../api/repository.dart';

const String kElevPhone = '+966 92 000 1234';

/// Phone-friendly input filter: digits, a leading/inline '+', and spaces
/// (e.g. "+966 5X XXX XXXX"). Rejects letters while keeping numbers usable.
final phoneChars = [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))];

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
        onBack: ctx.back,
        right: RoundBtn(icon: 'edit', label: 'تعديل', onTap: () => _openEdit(context, ctx, g)),
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
          // Records the guard's wage as a real expense (shows up in expenses +
          // reports) — previously this only showed a toast without saving.
          onTap: () async {
            if (g.fee <= 0) {
              ctx.toast('حدّد أجرة الحارس الشهرية أولاً', tone: 'late');
              return;
            }
            try {
              await Api.I.createExpense(ctx.btype, {
                'cat': 'أخرى',
                'icon': 'user',
                'tone': 'gold',
                'supplier': 'أجرة الحارس — ${g.name}',
                'amount': g.fee,
                'original_amount': g.fee,
                'currency': activeCurrency,
                'date': todayIso(),
                'description': 'دفعة أجرة الحارس الشهرية',
              });
              await ctx.reload();
              ctx.toast('تم تسجيل دفعة الحارس (${fmtUSD(g.fee)})');
            } catch (e) {
              ctx.toast(apiErrorText(e), tone: 'late');
            }
          },
        ),
      ],
    );
  }

  void _openEdit(BuildContext context, Ctx ctx, Guard g) {
    final f = {'name': g.name, 'phone': g.phone, 'address': g.address, 'fee': '${g.fee}'};
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل بيانات الحارس',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.setGuard(ctx.btype, {
                  'name': f['name'],
                  'phone': f['phone'],
                  'address': f['address'],
                  'fee': int.tryParse(f['fee']!.trim()) ?? g.fee,
                });
                await ctx.reload();
                ctx.toast('تم حفظ بيانات الحارس');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'اسم الحارس', icon: 'user', value: f['name']!, onChanged: (v) => f['name'] = v),
            Field(label: 'رقم الجوال', icon: 'phone', value: f['phone']!, ltr: true, keyboardType: TextInputType.phone, inputFormatters: phoneChars, onChanged: (v) => f['phone'] = v),
            Field(label: 'العنوان', icon: 'pin', value: f['address']!, onChanged: (v) => f['address'] = v),
            Field(label: 'الأجرة الشهرية', icon: 'wallet', value: f['fee']!, ltr: true, keyboardType: TextInputType.number, inputFormatters: digitsOnly, onChanged: (v) => f['fee'] = v),
          ],
        ),
      ),
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
  // Local elevator-access toggles, keyed by unit id. Reconciled with the live
  // unit list on every build so newly added/removed units are reflected.
  final Map<String, bool> access = {};

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final b = ctx.building;
    // Recompute from live data each build (was `late final` → stale after edits).
    final base = (ctx.res ? kApartments : kShops).where((u) => u.status != 'vacant').toList();
    for (final u in base) {
      access.putIfAbsent(u.id, () => u.status != 'late');
    }
    final allowed = base.where((u) => access[u.id] ?? true).length;

    return ScreenScaffold(
      header: AppHeader(
        title: 'إدارة المصعد',
        subtitle: '$allowed من ${base.length} مصرّح لهم',
        onBack: ctx.back,
        right: RoundBtn(icon: 'edit', label: 'تعديل', onTap: () => _editContract(ctx, b)),
      ),
      nav: ctx.adminNav,
      children: [
        // Maintenance contract + periodic-inspection reminder.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const IconChip(icon: 'elevator', tone: 'navy', size: 42),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('عقد صيانة المصعد', style: AppType.base(size: 14.5, weight: FontWeight.w800)),
                      Text(b.elevatorCompany.isEmpty ? 'لم تُضف شركة الصيانة' : b.elevatorCompany,
                          style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink500)),
                    ],
                  ),
                ),
                AppButton(
                  label: 'تعديل',
                  variant: BtnVariant.ghost,
                  size: BtnSize.sm,
                  icon: 'edit',
                  onTap: () => _editContract(ctx, b),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                MiniStat(
                    label: 'بداية العقد',
                    value: b.elevatorContractStart.isEmpty ? '—' : b.elevatorContractStart,
                    tone: 'ok',
                    num: true),
                const SizedBox(width: 8),
                MiniStat(
                    label: 'نهاية العقد',
                    value: b.elevatorContractEnd.isEmpty ? '—' : b.elevatorContractEnd,
                    tone: 'late',
                    num: true),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                MiniStat(
                    label: 'تاريخ آخر فحص دوري',
                    value: b.elevatorLastCheck.isEmpty ? '—' : b.elevatorLastCheck,
                    tone: 'navy',
                    num: true),
                const SizedBox(width: 8),
                MiniStat(
                    label: 'تذكير الفحص',
                    value: b.elevatorCheckNotify ? 'كل ${b.elevatorCheckInterval} شهر' : 'متوقّف',
                    tone: b.elevatorCheckNotify ? 'ok' : 'navy'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
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
                    NumText(b.elevatorPhone.isEmpty ? kElevPhone : b.elevatorPhone,
                        style: AppType.num(size: 17, weight: FontWeight.w800, color: Colors.white)),
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

  /// Edit the elevator maintenance contract + the periodic-inspection reminder.
  void _editContract(Ctx ctx, Building b) {
    final f = {
      'company': b.elevatorCompany,
      'phone': b.elevatorPhone,
      'start': b.elevatorContractStart,
      'end': b.elevatorContractEnd,
      'check': b.elevatorLastCheck,
    };
    bool notify = b.elevatorCheckNotify;
    int interval = b.elevatorCheckInterval;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'عقد المصعد والصيانة',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.updateBuilding(ctx.btype, {
                  'elevator_company': f['company'],
                  'elevator_phone': f['phone'],
                  'elevator_contract_start': f['start']!.isEmpty ? null : f['start'],
                  'elevator_contract_end': f['end']!.isEmpty ? null : f['end'],
                  'elevator_last_check': f['check']!.isEmpty ? null : f['check'],
                  'elevator_check_notify': notify,
                  'elevator_check_interval': interval,
                });
                await ctx.reload();
                ctx.toast('تم حفظ بيانات المصعد');
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(
                label: 'شركة الصيانة',
                icon: 'building',
                value: f['company']!,
                placeholder: 'اسم الشركة',
                onChanged: (v) => f['company'] = v),
            Field(
                label: 'هاتف الشركة',
                icon: 'phone',
                value: f['phone']!,
                ltr: true,
                placeholder: '+966 ...',
                inputFormatters: phoneChars,
                onChanged: (v) => f['phone'] = v),
            Row(children: [
              Expanded(
                child: DateField(
                    label: 'بداية العقد',
                    value: f['start']!,
                    onChanged: (v) => setS(() => f['start'] = v)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DateField(
                    label: 'نهاية العقد',
                    value: f['end']!,
                    onChanged: (v) => setS(() => f['end'] = v)),
              ),
            ]),
            DateField(
                label: 'تاريخ آخر فحص دوري للمصعد',
                value: f['check']!,
                onChanged: (v) => setS(() => f['check'] = v)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: notify ? AppColors.navy50 : AppColors.surface,
                border: Border.all(color: notify ? AppColors.navy100 : AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(children: [
                const AppIcon('bell', size: 20, color: AppColors.navy700),
                const SizedBox(width: 11),
                Expanded(
                    child: Text('تذكير بالفحص الدوري القادم',
                        style: AppType.base(size: 14, weight: FontWeight.w700))),
                AppSwitch(checked: notify, onChanged: (v) => setS(() => notify = v)),
              ]),
            ),
            if (notify) ...[
              const SizedBox(height: 12),
              SelectField(
                label: 'الفترة بين الفحوصات',
                icon: 'calendar',
                options: const [
                  SelectOption(1, 'كل شهر'),
                  SelectOption(3, 'كل 3 أشهر'),
                  SelectOption(6, 'كل 6 أشهر'),
                  SelectOption(12, 'كل سنة'),
                ],
                value: interval,
                onChanged: (v) => setS(() => interval = v as int),
              ),
            ],
          ],
        ),
      ),
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
        onBack: ctx.back,
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
                inputFormatters: phoneChars,
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

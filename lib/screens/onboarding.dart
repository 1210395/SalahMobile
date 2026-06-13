// عمارتي — onboarding flow: subscription activation, building setup wizard
// (which promotes the actor to admin), resident self-join (invite/QR target),
// and admin approval of join requests. All wired to the live Laravel API.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/auth_store.dart';
import '../api/repository.dart';

int? _i(String s) => int.tryParse(s.trim());

// ───────────────────────────── Subscription gate ─────────────────────────────

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  final f = {'card': '', 'name': '', 'exp': '', 'cvc': ''};

  bool get _valid =>
      f['card']!.replaceAll(' ', '').length >= 12 &&
      f['name']!.trim().isNotEmpty &&
      f['exp']!.isNotEmpty &&
      f['cvc']!.length >= 3;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'تفعيل الاشتراك',
        subtitle: 'اشتراك إدارة المبنى',
        onBack: () => ctx.go(ctx.role == AppRole.admin ? 'home' : 'guestHome'),
      ),
      children: [
        HeroBanner(
          gradient: const [AppColors.navy700, AppColors.navy800],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('باقة إدارة المبنى',
                  style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.gold400)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                NumText(fmtUSD(299),
                    style: AppType.num(size: 30, weight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('/ سنوياً',
                      style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.navy300)),
                ),
              ]),
              const SizedBox(height: 10),
              Text('وحدات غير محدودة · تقارير · تنبيهات واتساب · نسخ احتياطي',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.navy300, height: 1.6)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'بيانات البطاقة البنكية'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                  label: 'رقم البطاقة',
                  icon: 'wallet',
                  placeholder: '0000 0000 0000 0000',
                  ltr: true,
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => f['card'] = v)),
              Field(
                  label: 'الاسم على البطاقة',
                  icon: 'user',
                  placeholder: 'الاسم كما يظهر على البطاقة',
                  onChanged: (v) => setState(() => f['name'] = v)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Field(
                        label: 'تاريخ الانتهاء',
                        placeholder: 'MM/YY',
                        ltr: true,
                        marginBottom: 0,
                        onChanged: (v) => setState(() => f['exp'] = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Field(
                        label: 'CVC',
                        placeholder: '123',
                        ltr: true,
                        keyboardType: TextInputType.number,
                        marginBottom: 0,
                        onChanged: (v) => setState(() => f['cvc'] = v)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const AppIcon('lock', size: 14, color: AppColors.ink400),
          const SizedBox(width: 6),
          Expanded(
            child: Text('دفع آمن ومشفّر. لن يتم تخزين بيانات بطاقتك على الجهاز.',
                style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
          ),
        ]),
        const SizedBox(height: 16),
        AppButton(
          label: 'الدفع والمتابعة · ${fmtUSD(299)}',
          size: BtnSize.lg,
          full: true,
          icon: 'check',
          disabled: !_valid || ctx.busy,
          // Card capture is simulated; the subscription is actually activated on
          // the server in the building-setup step (for the chosen building type).
          onTap: () {
            ctx.toast('تم قبول الدفع — أكمل إعداد المبنى');
            ctx.go('buildingSetup');
          },
        ),
      ],
    );
  }
}

// ───────────────────────────── Building setup wizard ─────────────────────────────

class BuildingSetupScreen extends StatefulWidget {
  const BuildingSetupScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<BuildingSetupScreen> createState() => _BuildingSetupScreenState();
}

class _BuildingSetupScreenState extends State<BuildingSetupScreen> {
  final f = {'name': '', 'address': '', 'floors': '', 'units': '', 'sub': ''};
  BType type = BType.residential;
  bool _saving = false;

  bool get _valid =>
      f['name']!.trim().isNotEmpty &&
      f['address']!.trim().isNotEmpty &&
      _i(f['floors']!) != null &&
      _i(f['units']!) != null;

  Future<void> _save() async {
    final ctx = widget.ctx;
    if (!AuthStore.I.isAuthed) {
      ctx.toast('سجّل الدخول أولاً لإعداد المبنى', tone: 'late');
      ctx.go('login');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.I.activateSubscription(type);
      await Api.I.setupBuilding(type, {
        'name': f['name']!.trim(),
        'address': f['address']!.trim(),
        'floors': _i(f['floors']!),
        'units_count': _i(f['units']!),
      });
      if (_i(f['sub']!) != null) {
        await Api.I.updateBuilding(type, {'subscription': _i(f['sub']!)});
      }
      ctx.toast('تم تفعيل الاشتراك وحفظ بيانات المبنى');
      await ctx.becomeAdmin(type); // refreshes role → admin, lands on home
      if (mounted) ctx.go('units');
    } catch (e) {
      if (mounted) ctx.toast(apiErrorText(e), tone: 'late');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final res = type == BType.residential;
    return ScreenScaffold(
      header: AppHeader(
        title: 'إعداد المبنى',
        subtitle: 'الخطوة الأخيرة قبل البدء',
        onBack: () => ctx.go('subscribe'),
      ),
      children: [
        const SectionTitle(text: 'بيانات المبنى'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                  label: 'اسم المبنى',
                  icon: 'building2',
                  placeholder: 'مثال: عمارة الياسمين',
                  onChanged: (v) => setState(() => f['name'] = v)),
              Field(
                  label: 'العنوان',
                  icon: 'pin',
                  placeholder: 'الحي، الشارع، المدينة',
                  onChanged: (v) => setState(() => f['address'] = v)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('نوع المبنى',
                    style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
              ),
              Segmented(
                value: type,
                onChanged: (v) => setState(() => type = v as BType),
                options: const [
                  SegOption(BType.residential, 'سكني (شقق)', icon: 'building'),
                  SegOption(BType.commercial, 'تجاري (محلات)', icon: 'store'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'التفاصيل'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Field(
                        label: 'عدد الطوابق',
                        icon: 'layers',
                        placeholder: '6',
                        ltr: true,
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() => f['floors'] = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Field(
                        label: res ? 'عدد الشقق' : 'عدد المحلات',
                        icon: 'grid',
                        placeholder: '12',
                        ltr: true,
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() => f['units'] = v)),
                  ),
                ],
              ),
              Field(
                  label: 'الاشتراك الشهري الافتراضي',
                  icon: 'wallet',
                  placeholder: '40',
                  ltr: true,
                  suffix: '\$',
                  keyboardType: TextInputType.number,
                  marginBottom: 0,
                  onChanged: (v) => setState(() => f['sub'] = v)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: _saving ? 'جارٍ الحفظ…' : 'حفظ والبدء',
          size: BtnSize.lg,
          full: true,
          iconRight: 'arrowL',
          disabled: !_valid || _saving,
          onTap: _save,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('بعد الحفظ: أضف الوحدات يدوياً أو بالدعوة عبر واتساب / QR',
              textAlign: TextAlign.center,
              style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
        ),
      ],
    );
  }
}

// ───────────────────────────── Resident self-join (invite/QR target) ─────────────────────────────

class JoinUnitScreen extends StatefulWidget {
  const JoinUnitScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<JoinUnitScreen> createState() => _JoinUnitScreenState();
}

class _JoinUnitScreenState extends State<JoinUnitScreen> {
  final f = {'name': '', 'phone': '', 'floor': '', 'no': '', 'email': ''};
  bool _sending = false;

  bool get _valid =>
      f['name']!.trim().isNotEmpty && f['phone']!.trim().isNotEmpty && f['no']!.trim().isNotEmpty;

  Future<void> _send() async {
    final ctx = widget.ctx;
    if (!AuthStore.I.isAuthed) {
      ctx.toast('سجّل الدخول أولاً لإرسال طلب الانضمام', tone: 'late');
      ctx.go('login');
      return;
    }
    setState(() => _sending = true);
    try {
      await Api.I.createJoinRequest(ctx.btype, {
        'name': f['name']!.trim(),
        'phone': f['phone']!.trim(),
        'floor': _i(f['floor']!),
        'unit_no': f['no']!.trim(),
      });
      ctx.toast('تم إرسال طلبك — بانتظار موافقة مسؤول العمارة');
      ctx.go(ctx.role == AppRole.resident ? 'resHome' : 'guestHome');
    } catch (e) {
      if (mounted) ctx.toast(apiErrorText(e), tone: 'late');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'الانضمام إلى العمارة',
        subtitle: ctx.building.name,
        onBack: () => ctx.go(ctx.role == AppRole.resident ? 'resHome' : 'guestHome'),
      ),
      children: [
        AppCard(
          color: AppColors.navy50,
          borderColor: AppColors.navy100,
          child: Row(children: [
            const IconChip(icon: 'building2', tone: 'navy', size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text('أنت على وشك الانضمام إلى «${ctx.building.name}». بعد إرسال الطلب '
                  'سيقوم مسؤول العمارة بالموافقة عليه.',
                  style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'بياناتك'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                  label: 'الاسم الرباعي',
                  icon: 'user',
                  placeholder: 'الاسم الكامل',
                  onChanged: (v) => setState(() => f['name'] = v)),
              Field(
                  label: 'رقم الجوال',
                  icon: 'phone',
                  placeholder: '5X XXX XXXX',
                  ltr: true,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => setState(() => f['phone'] = v)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Field(
                        label: 'الطابق',
                        icon: 'layers',
                        placeholder: '2',
                        ltr: true,
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() => f['floor'] = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Field(
                        label: 'رقم الشقة',
                        icon: 'grid',
                        placeholder: '203',
                        ltr: true,
                        onChanged: (v) => setState(() => f['no'] = v)),
                  ),
                ],
              ),
              Field(
                  label: 'البريد الإلكتروني (اختياري)',
                  icon: 'mail',
                  placeholder: 'name@email.com',
                  ltr: true,
                  marginBottom: 0,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => f['email'] = v)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: _sending ? 'جارٍ الإرسال…' : 'إرسال طلب الانضمام',
          size: BtnSize.lg,
          full: true,
          icon: 'send',
          disabled: !_valid || _sending,
          onTap: _send,
        ),
      ],
    );
  }
}

// ───────────────────────────── Admin: join-request approvals ─────────────────────────────

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<Map<String, dynamic>>? _requests;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.I.listJoinRequests(widget.ctx.btype);
      if (mounted) setState(() => _requests = list);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(e));
    }
  }

  Future<void> _act(int id, bool approve, String name, String unit) async {
    final ctx = widget.ctx;
    try {
      if (approve) {
        await Api.I.approveJoinRequest(ctx.btype, id);
        ctx.toast('تمت الموافقة على $name — وحدة $unit');
      } else {
        await Api.I.rejectJoinRequest(ctx.btype, id);
        ctx.toast('تم رفض الطلب', tone: 'late');
      }
      await _load();
    } catch (e) {
      if (mounted) ctx.toast(apiErrorText(e), tone: 'late');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final pending = (_requests ?? []).where((r) => r['status'] == 'pending').toList();

    return ScreenScaffold(
      header: AppHeader(
        title: 'طلبات الانضمام',
        subtitle: _requests == null
            ? '...'
            : '${pending.length} طلب بانتظار الموافقة',
        onBack: () => ctx.go('more'),
      ),
      nav: ctx.adminNav,
      children: [
        if (_error != null)
          EmptyState(icon: 'alert', title: 'تعذّر التحميل', sub: _error)
        else if (_requests == null)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: AppColors.navy700)),
          )
        else if (pending.isEmpty)
          const EmptyState(icon: 'users', title: 'لا توجد طلبات', sub: 'ستظهر هنا طلبات الانضمام الجديدة')
        else
          ...pending.map((r) {
            final id = (r['id'] as num).toInt();
            final name = '${r['name']}';
            final unit = '${r['unit_no'] ?? '—'}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Avatar(name: name, size: 46, tone: 'gold'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name, style: AppType.base(size: 15, weight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            NumText('${r['phone'] ?? ''}',
                                style: AppType.num(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                          ],
                        ),
                      ),
                      AppBadge(label: 'وحدة $unit', tone: 'navy', small: true),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: AppButton(
                          label: 'رفض',
                          variant: BtnVariant.ghost,
                          size: BtnSize.sm,
                          full: true,
                          icon: 'xCircle',
                          onTap: () => _act(id, false, name, unit),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          label: 'قبول',
                          size: BtnSize.sm,
                          full: true,
                          icon: 'checkCircle',
                          onTap: () => _act(id, true, name, unit),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

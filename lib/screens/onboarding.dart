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
  // The annual subscription price shown on the gateway, in the base currency.
  static const _amount = 299;

  // True while we fake the redirect hop to the bank's payment page.
  bool _redirecting = false;

  // SIMULATION — bank e-payment redirect (Note 4: "transferred to the bank's
  // electronic payment screen to pay the subscription"). We round-trip a fake
  // gateway entirely in-app: no real checkout URL, no card capture. A real
  // integration would push the user to the bank's hosted page via env-keyed
  // credentials (merchant id / API key) and confirm the result with a *signed
  // webhook* — never trust the client. This mirrors the backend's own
  // subscription-activate simulation note. The seam: replace _payViaGateway
  // with a url_launcher hop + server-verified payment_ref, then keep the same
  // activate-on-return path below.
  Future<void> _payViaGateway() async {
    final ctx = widget.ctx;
    setState(() => _redirecting = true);
    // Brief "redirecting to the gateway" beat before the checkout sheet.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _redirecting = false);

    final paid = await showAppSheet<bool>(context, _GatewaySheet(amount: _amount));
    if (paid != true || !mounted) return;

    // Gateway approved. The subscription is actually activated on the server in
    // the building-setup step (for the chosen building type) — keep that path
    // intact and just hand off to it, exactly as before.
    ctx.toast('تم الدفع بنجاح — أكمل إعداد المبنى');
    ctx.go('buildingSetup');
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'تفعيل الاشتراك',
        subtitle: 'اشتراك إدارة المبنى',
        onBack: ctx.back,
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
                NumText(fmtUSD(_amount),
                    style: AppType.num(size: 30, weight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('/ سنوياً',
                      style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.navy300)),
                ),
              ]),
              const SizedBox(height: 10),
              Text('شقق ووحدات غير محدودة · تقارير · تنبيهات واتساب · نسخ احتياطي',
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.navy300, height: 1.6)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'الدفع عبر البوابة البنكية'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const IconChip(icon: 'building2', tone: 'navy', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('بوابة الدفع البنكية',
                          style: AppType.base(size: 14.5, weight: FontWeight.w800, color: AppColors.ink900)),
                      const SizedBox(height: 3),
                      Text('سيتم تحويلك إلى صفحة الدفع الإلكتروني الخاصة بالبنك لإتمام الاشتراك.',
                          style: AppType.base(size: 12, weight: FontWeight.w500, color: AppColors.ink500, height: 1.55)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.navy50,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.navy100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('المبلغ المستحق',
                        style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
                    NumText(fmtUSD(_amount),
                        style: AppType.num(size: 18, weight: FontWeight.w800, color: AppColors.navy700)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const AppIcon('lock', size: 14, color: AppColors.ink400),
          const SizedBox(width: 6),
          Expanded(
            child: Text('دفع آمن عبر بوابة البنك. لا يتم تخزين بيانات بطاقتك على الجهاز.',
                style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
          ),
        ]),
        const SizedBox(height: 16),
        AppButton(
          label: _redirecting ? 'جارٍ التحويل إلى بوابة الدفع البنكية…' : 'الدفع عبر البوابة البنكية',
          size: BtnSize.lg,
          full: true,
          icon: _redirecting ? null : 'wallet',
          disabled: _redirecting || ctx.busy,
          onTap: _payViaGateway,
        ),
      ],
    );
  }
}

// Simulated bank checkout, presented via showAppSheet and styled as the bank's
// hosted payment page. Pops `true` on "تأكيد الدفع", `false`/null otherwise.
// SIMULATION: a real gateway would render the bank's own page (or an in-app
// webview / url_launcher hop) and the approval would arrive via a signed webhook.
class _GatewaySheet extends StatelessWidget {
  const _GatewaySheet({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'بوابة الدفع البنكية',
      onClose: () => Navigator.of(context).pop(false),
      footer: Row(children: [
        Expanded(
          child: AppButton(
            label: 'إلغاء',
            variant: BtnVariant.ghost,
            size: BtnSize.lg,
            full: true,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton(
            label: 'تأكيد الدفع',
            size: BtnSize.lg,
            full: true,
            icon: 'check',
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navy700, AppColors.navy800],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const AppIcon('shield', size: 16, color: AppColors.gold400),
                const SizedBox(width: 6),
                Text('دفع إلكتروني آمن',
                    style: AppType.base(size: 12.5, weight: FontWeight.w700, color: AppColors.gold400)),
              ]),
              const SizedBox(height: 14),
              Text('المبلغ',
                  style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.navy300)),
              const SizedBox(height: 4),
              NumText(fmtUSD(amount),
                  style: AppType.num(size: 30, weight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text('اشتراك إدارة المبنى · سنوياً',
                  style: AppType.base(size: 12, weight: FontWeight.w500, color: AppColors.navy300)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const AppIcon('lock', size: 14, color: AppColors.ink400),
          const SizedBox(width: 6),
          Expanded(
            child: Text('بيئة محاكاة للدفع. عند الربط الفعلي، تتم العملية على صفحة البنك '
                'ويُؤكَّد القبول عبر إشعار موقّع من البنك.',
                style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400, height: 1.55)),
          ),
        ]),
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

// First-time manager onboarding: one essential question per step (no elevator),
// then save + land on the dashboard.
class _BuildingSetupScreenState extends State<BuildingSetupScreen> {
  final f = {'name': '', 'address': '', 'floors': '', 'units': '', 'sub': ''};
  BType type = BType.residential;
  String currency = kDefaultCurrency;
  int step = 0;
  bool _saving = false;

  static const _steps = ['name', 'address', 'type', 'floors', 'units', 'currency', 'sub'];

  bool get _res => type == BType.residential;

  // Whether the current step's answer is acceptable to advance.
  bool get _stepValid {
    switch (_steps[step]) {
      case 'name':
        return f['name']!.trim().isNotEmpty;
      case 'address':
        return f['address']!.trim().isNotEmpty;
      case 'floors':
        final n = _i(f['floors']!);
        return n != null && n >= 1; // at least one floor
      case 'units':
        final n = _i(f['units']!);
        return n != null && n >= 1; // at least one unit
      case 'sub':
        final n = _i(f['sub']!);
        return n != null && n >= 0; // last step → save (fee may be 0)
      default:
        return true; // type + currency always have a value
    }
  }

  void _next() {
    if (step < _steps.length - 1) {
      setState(() => step++);
    } else {
      _save();
    }
  }

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
      await Api.I.updateBuilding(type, {
        'currency': currency,
        if (_i(f['sub']!) != null) 'subscription': _i(f['sub']!),
      });
      ctx.toast('تم حفظ بيانات المبنى');
      await ctx.becomeAdmin(type); // refreshes role → admin, lands on home
      if (mounted) ctx.go('home');
    } catch (e) {
      if (mounted) ctx.toast(apiErrorText(e), tone: 'late');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // The question (title + hint + input) for the active step.
  ({String title, String hint, Widget input}) _stepContent() {
    switch (_steps[step]) {
      case 'name':
        return (
          title: 'ما اسم المبنى؟',
          hint: 'الاسم الذي يظهر في لوحة التحكم والتقارير.',
          input: Field(
              key: const ValueKey('s-name'),
              icon: 'building2',
              value: f['name']!,
              placeholder: 'مثال: عمارة الياسمين',
              marginBottom: 0,
              onChanged: (v) => setState(() => f['name'] = v)),
        );
      case 'address':
        return (
          title: 'ما عنوان المبنى؟',
          hint: 'الحي، الشارع، المدينة.',
          input: Field(
              key: const ValueKey('s-address'),
              icon: 'pin',
              value: f['address']!,
              placeholder: 'الحي، الشارع، المدينة',
              marginBottom: 0,
              onChanged: (v) => setState(() => f['address'] = v)),
        );
      case 'type':
        return (
          title: 'نوع المبنى؟',
          hint: 'يحدّد ما إذا كانت الوحدات شققاً أو وحدات.',
          input: Segmented(
            value: type,
            onChanged: (v) => setState(() => type = v as BType),
            options: const [
              SegOption(BType.residential, 'سكني (شقق)', icon: 'building'),
              SegOption(BType.commercial, 'تجاري (وحدات)', icon: 'store'),
            ],
          ),
        );
      case 'floors':
        return (
          title: 'كم عدد الطوابق؟',
          hint: 'العدد الإجمالي لطوابق المبنى.',
          input: Field(
              key: const ValueKey('s-floors'),
              icon: 'layers',
              value: f['floors']!,
              placeholder: '6',
              ltr: true,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              marginBottom: 0,
              onChanged: (v) => setState(() => f['floors'] = v)),
        );
      case 'units':
        return (
          title: _res ? 'كم عدد الشقق؟' : 'كم عدد الوحدات؟',
          hint: 'يمكنك إضافة الوحدات تفصيلياً لاحقاً.',
          input: Field(
              key: const ValueKey('s-units'),
              icon: 'grid',
              value: f['units']!,
              placeholder: '12',
              ltr: true,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              marginBottom: 0,
              onChanged: (v) => setState(() => f['units'] = v)),
        );
      case 'currency':
        return (
          title: 'عملة المبنى؟',
          hint: 'تُستخدم لعرض جميع المبالغ والتقارير.',
          input: SelectField(
            icon: 'dollar',
            options: [for (final c in kCurrencyCodes) SelectOption(c, '$c (${currencySymbol(c)})')],
            value: currency,
            onChanged: (v) => setState(() => currency = v as String),
          ),
        );
      default: // sub
        return (
          title: 'الاشتراك الشهري الافتراضي؟',
          hint: 'القيمة الافتراضية لاشتراك كل وحدة (يمكن تعديلها لكل وحدة).',
          input: Field(
              key: const ValueKey('s-sub'),
              icon: 'wallet',
              value: f['sub']!,
              placeholder: '40',
              ltr: true,
              suffix: currencySymbol(currency),
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              marginBottom: 0,
              onChanged: (v) => setState(() => f['sub'] = v)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final q = _stepContent();
    final isLast = step == _steps.length - 1;
    return ScreenScaffold(
      header: AppHeader(
        title: 'إعداد المبنى',
        subtitle: 'سؤال ${step + 1} من ${_steps.length}',
        onBack: () => step == 0 ? ctx.go('subscribe') : setState(() => step--),
      ),
      children: [
        // Progress dots.
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(left: i == _steps.length - 1 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.navy700 : AppColors.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(q.title, style: AppType.base(size: 18, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(q.hint,
                  style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.ink500, height: 1.6)),
              const SizedBox(height: 16),
              q.input,
            ],
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: _saving
              ? 'جارٍ الحفظ…'
              : isLast
                  ? 'حفظ والبدء'
                  : 'التالي',
          size: BtnSize.lg,
          full: true,
          iconRight: isLast ? 'check' : 'arrowL',
          disabled: !_stepValid || _saving,
          onTap: _next,
        ),
        if (step > 0) ...[
          const SizedBox(height: 8),
          AppButton(
            label: 'السابق',
            variant: BtnVariant.ghost,
            size: BtnSize.lg,
            full: true,
            disabled: _saving,
            onTap: () => setState(() => step--),
          ),
        ],
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
      f['name']!.trim().isNotEmpty &&
      f['phone']!.trim().isNotEmpty &&
      f['no']!.trim().isNotEmpty &&
      _floorOk;

  // #20 — the floor is optional, but if one is entered and the building's floor
  // count is known (>= 1), it must not exceed the building's total floors.
  bool get _floorOk {
    final floor = _i(f['floor']!);
    if (floor == null) return true; // optional — blank is fine
    final total = widget.ctx.building.floors;
    return total < 1 || floor <= total;
  }

  // Scan the unit's QR (e.g. a sticker on the door) to prefill the unit number.
  // QRs in this app encode a raw short code; if it's a plain unit number we use
  // it directly, otherwise we drop any "unit:"/"no:" prefix.
  Future<void> _scanUnit() async {
    final raw = await scanQr(context);
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    final code = raw.trim().split(RegExp(r'[:#/]')).last.trim();
    setState(() => f['no'] = code);
  }

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
        onBack: ctx.back,
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
                  label: 'الاسم',
                  icon: 'user',
                  placeholder: 'الاسم الكامل',
                  onChanged: (v) => setState(() => f['name'] = v)),
              Field(
                  label: 'رقم الموبايل',
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
                        inputFormatters: digitsOnly,
                        onChanged: (v) => setState(() => f['floor'] = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Field(
                        // Key on the scanned value so a QR scan remounts the
                        // field and shows the prefilled number.
                        key: ValueKey('unit-${f['no']}'),
                        label: ctx.res ? 'رقم الشقة' : 'رقم الوحدة',
                        icon: 'grid',
                        placeholder: '203',
                        value: f['no']!,
                        ltr: true,
                        onChanged: (v) => setState(() => f['no'] = v)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'مسح رمز QR',
                variant: BtnVariant.outline,
                size: BtnSize.sm,
                full: true,
                icon: 'qr',
                onTap: _scanUnit,
              ),
              const SizedBox(height: 14),
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
    final noun = ctx.res ? 'شقة' : 'وحدة';
    try {
      if (approve) {
        await Api.I.approveJoinRequest(ctx.btype, id);
        ctx.toast('تمت الموافقة على $name — $noun $unit');
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
        onBack: ctx.back,
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
                      AppBadge(label: '${ctx.res ? 'شقة' : 'وحدة'} $unit', tone: 'navy', small: true),
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

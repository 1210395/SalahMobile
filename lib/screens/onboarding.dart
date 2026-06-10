// عمارتي — onboarding flow: subscription activation, building setup wizard,
// resident self-join (invite/QR target), and admin approval of join requests.
//
// Persistence here is in-memory/mock (confirms with a toast and updates the
// shared [OnboardingStore]); wiring to real Laravel endpoints + a payment
// provider is the documented next step (see docs/CLIENT-FEEDBACK-PLAN.md).

import 'package:flutter/material.dart';

import '../common.dart';

// ───────────────────────────── Shared store ─────────────────────────────

class JoinRequest {
  JoinRequest({
    required this.name,
    required this.phone,
    required this.floor,
    required this.unitNo,
    this.email = '',
    this.status = 'pending',
  });
  final String name;
  final String phone;
  final String floor;
  final String unitNo;
  final String email;
  String status; // pending | approved | rejected
}

/// In-memory store for pending resident join requests (mock backend).
class OnboardingStore {
  OnboardingStore._();
  static final OnboardingStore I = OnboardingStore._();

  bool subscriptionActive = false;

  final List<JoinRequest> requests = [
    JoinRequest(name: 'بدر العتيبي', phone: '+966 50 555 1212', floor: '2', unitNo: '203'),
    JoinRequest(name: 'هند الشمري', phone: '+966 55 888 3434', floor: '4', unitNo: '404'),
  ];

  int get pending => requests.where((r) => r.status == 'pending').length;
}

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
        onBack: () => ctx.go('home'),
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
                NumText(fmtUSD(99),
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
          label: 'تفعيل الاشتراك · ${fmtUSD(99)}',
          size: BtnSize.lg,
          full: true,
          icon: 'check',
          disabled: !_valid,
          onTap: () {
            OnboardingStore.I.subscriptionActive = true;
            ctx.toast('تم تفعيل الاشتراك بنجاح');
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

  bool get _valid =>
      f['name']!.trim().isNotEmpty &&
      f['floors']!.isNotEmpty &&
      f['units']!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final res = type == BType.residential;
    return ScreenScaffold(
      header: AppHeader(
        title: 'إعداد المبنى',
        subtitle: 'الخطوة الأخيرة قبل البدء',
        onBack: () => ctx.go('home'),
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
          label: 'حفظ والبدء',
          size: BtnSize.lg,
          full: true,
          iconRight: 'arrowL',
          disabled: !_valid,
          onTap: () {
            ctx.toast('تم حفظ بيانات المبنى — يمكنك الآن إضافة الوحدات');
            ctx.go('units');
          },
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

  bool get _valid =>
      f['name']!.trim().isNotEmpty && f['phone']!.trim().isNotEmpty && f['no']!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'الانضمام إلى العمارة',
        subtitle: ctx.building.name,
        onBack: () => ctx.go('guestHome'),
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
          label: 'إرسال طلب الانضمام',
          size: BtnSize.lg,
          full: true,
          icon: 'send',
          disabled: !_valid,
          onTap: () {
            OnboardingStore.I.requests.add(JoinRequest(
              name: f['name']!.trim(),
              phone: f['phone']!.trim(),
              floor: f['floor']!,
              unitNo: f['no']!,
              email: f['email']!,
            ));
            ctx.toast('تم إرسال طلبك — بانتظار موافقة مسؤول العمارة');
            ctx.go('guestHome');
          },
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
  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final pending = OnboardingStore.I.requests.where((r) => r.status == 'pending').toList();

    return ScreenScaffold(
      header: AppHeader(
        title: 'طلبات الانضمام',
        subtitle: '${pending.length} طلب بانتظار الموافقة',
        onBack: () => ctx.go('more'),
      ),
      nav: ctx.adminNav,
      children: [
        if (pending.isEmpty)
          const EmptyState(icon: 'users', title: 'لا توجد طلبات', sub: 'ستظهر هنا طلبات الانضمام الجديدة')
        else
          ...pending.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Avatar(name: r.name, size: 46, tone: 'gold'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.name, style: AppType.base(size: 15, weight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              NumText(r.phone,
                                  style: AppType.num(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                            ],
                          ),
                        ),
                        AppBadge(label: 'شقة ${r.unitNo}', tone: 'navy', small: true),
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
                            onTap: () => setState(() {
                              r.status = 'rejected';
                              ctx.toast('تم رفض الطلب', tone: 'late');
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(
                            label: 'قبول',
                            size: BtnSize.sm,
                            full: true,
                            icon: 'checkCircle',
                            onTap: () => setState(() {
                              r.status = 'approved';
                              ctx.toast('تمت الموافقة على ${r.name} — شقة ${r.unitNo}');
                            }),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

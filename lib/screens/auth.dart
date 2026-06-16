// عمارتي — auth screens: Splash, Guest, Login.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.navy600, AppColors.navy800, AppColors.navy900],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            // Decorative skyline.
            Positioned(
              left: 0,
              right: 0,
              bottom: 150,
              child: Opacity(
                opacity: 0.08,
                child: SizedBox(
                  height: 240,
                  child: CustomPaint(painter: _SkylinePainter()),
                ),
              ),
            ),
            // Gold glow.
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x59C2A24E), Color(0x00C2A24E)],
                    stops: [0, 0.7],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(32, pad.top, 32, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Brand.logoUrl.isNotEmpty
                            ? Image.network(Brand.logoUrl,
                                width: 230,
                                errorBuilder: (c, e, s) =>
                                    Image.asset('assets/images/logo-light.png', width: 230))
                            : Image.asset('assets/images/logo-light.png', width: 230),
                        const SizedBox(height: 26),
                        Text(Brand.slogan,
                            textAlign: TextAlign.center,
                            style: AppType.base(
                                size: 26, weight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 290),
                          child: Text(
                            Brand.description,
                            textAlign: TextAlign.center,
                            style: AppType.base(
                                size: 14.5,
                                weight: FontWeight.w500,
                                color: AppColors.navy300,
                                height: 1.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + pad.bottom),
                  child: Column(
                    children: [
                      AppButton(
                        label: 'تجربة التطبيق كزائر',
                        variant: BtnVariant.gold,
                        size: BtnSize.lg,
                        full: true,
                        icon: 'eye',
                        onTap: () => ctx.enterGuest(ctx.btype),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'تسجيل الدخول / إنشاء حساب',
                        variant: BtnVariant.white,
                        size: BtnSize.lg,
                        full: true,
                        iconRight: 'arrowL',
                        onTap: () => ctx.go('login'),
                      ),
                      const SizedBox(height: 18),
                      Text(Brand.tagline,
                          style: AppType.base(
                              size: 12, weight: FontWeight.w600, color: AppColors.navy300)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white;
    final w = size.width / 392; // design width reference
    final h = size.height / 240;
    final rects = [
      [20, 0, 50, 240],
      [80, -40, 60, 280],
      [150, 30, 44, 210],
      [210, -60, 64, 300],
      [285, -10, 50, 250],
      [345, 40, 40, 200],
    ];
    for (final r in rects) {
      final top = (120 + r[1]) * h; // shift so taller buildings rise
      canvas.drawRect(
        Rect.fromLTWH(r[0] * w, top.clamp(0, size.height),
            r[2] * w, size.height - top.clamp(0, size.height)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GuestHome extends StatelessWidget {
  const GuestHome({super.key, required this.ctx});
  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      header: AppHeader(
        accent: true,
        logo: true,
        right: const AppBadge(label: 'زائر', tone: 'gold', icon: 'eye'),
      ),
      nav: ctx.guestNav,
      children: [
        HeroBanner(
          gradient: const [AppColors.navy700, AppColors.navy800],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ملخص عام — ${ctx.building.name}',
                  style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.gold400)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _guestStat(fmtUSD(Summary.revenueM), 'إيرادات الشهر')),
                  Container(width: 1, height: 44, color: Colors.white.withValues(alpha: 0.15)),
                  Expanded(child: _guestStat(fmtUSD(Summary.expenseM), 'مصروفات الشهر')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionTitle(text: 'نظرة عامة على الحركة'),
        AppCard(child: BarChart(data: Summary.bars)),
        const SizedBox(height: 14),
        AppCard(
          child: Row(
            children: [
              const IconChip(icon: 'pie', tone: 'gold'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('التقارير العامة',
                        style: AppType.base(size: 14.5, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('إجماليات الإيرادات والمصروفات على مستوى المبنى',
                        style: AppType.base(size: 12.5, weight: FontWeight.w500, color: AppColors.ink500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const AppBadge(label: 'متاح', tone: 'ok'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Locked CTA.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.gold50,
            border: Border.all(color: AppColors.gold400, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: AppColors.gold100, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const AppIcon('lock', size: 26, color: AppColors.gold700),
              ),
              const SizedBox(height: 12),
              Text('الوصول محدود في وضع الزائر',
                  textAlign: TextAlign.center,
                  style: AppType.base(size: 15, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('للاطلاع على بياناتك الشخصية أو إدارة المبنى، يرجى تسجيل الدخول.',
                  textAlign: TextAlign.center,
                  style: AppType.base(
                      size: 13, weight: FontWeight.w500, color: AppColors.ink600, height: 1.6)),
              const SizedBox(height: 14),
              AppButton(
                label: 'تسجيل الدخول / إنشاء حساب',
                full: true,
                iconRight: 'arrowL',
                onTap: () => ctx.go('login'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _guestStat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          NumText(value, style: AppType.num(size: 22, weight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: AppType.base(size: 12, weight: FontWeight.w500, color: AppColors.navy300)),
        ],
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String method = 'phone';
  AppRole role = AppRole.admin;
  late BType btype = widget.ctx.btype;
  String val = '';
  String code = '';
  String name = '';
  // Phone sign-in requires the OTP to have been sent before "دخول" is enabled.
  bool otpSent = false;

  Future<void> _submit() async {
    final ctx = widget.ctx;
    final err = method == 'phone'
        ? await ctx.signIn(
            phone: val, code: code, name: name.trim().isEmpty ? null : name.trim(), role: role, btype: btype)
        : await ctx.signIn(email: val, password: code, role: role, btype: btype);
    if (err != null) ctx.toast(err, tone: 'late');
  }

  Future<void> _sendOtp() async {
    final ctx = widget.ctx;
    if (val.isEmpty) {
      ctx.toast('أدخل رقم الجوال أولاً', tone: 'late');
      return;
    }
    try {
      final dev = await ctx.requestOtp(val);
      setState(() => otpSent = true);
      ctx.toast(dev != null ? 'رمز التحقق التجريبي: $dev' : 'تم إرسال رمز التحقق إلى جوالك');
    } catch (_) {
      ctx.toast('تعذّر إرسال الرمز', tone: 'late');
    }
  }

  bool get _canSubmit => method == 'phone'
      ? (val.isNotEmpty && otpSent && code.length >= 4)
      : (val.isNotEmpty && code.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final phone = method == 'phone';
    return ScreenScaffold(
      header: AppHeader(
        title: 'تسجيل الدخول',
        subtitle: 'أهلاً بعودتك إلى عمارتي',
        onBack: () => ctx.go('splash'),
      ),
      children: [
        Segmented(
          value: method,
          onChanged: (v) => setState(() {
            method = v as String;
            otpSent = false;
            code = '';
          }),
          options: const [
            SegOption('phone', 'رقم الجوال', icon: 'phone'),
            SegOption('email', 'البريد', icon: 'mail'),
          ],
        ),
        const SizedBox(height: 16),
        // Full (four-part) name — only needed for first-time phone/OTP sign-up,
        // not for email login.
        if (phone)
          Field(
            label: 'الاسم الرباعي',
            icon: 'user',
            placeholder: 'الاسم الأول والأب والجد والعائلة',
            onChanged: (v) => setState(() => name = v),
          ),
        if (phone)
          Field(
            label: 'رقم الجوال',
            icon: 'phone',
            placeholder: '5X XXX XXXX',
            keyboardType: TextInputType.phone,
            ltr: true,
            onChanged: (v) => setState(() {
              val = v;
              otpSent = false; // re-send required if the number changes
            }),
          )
        else ...[
          Field(
            label: 'البريد الإلكتروني',
            icon: 'mail',
            placeholder: 'name@email.com',
            keyboardType: TextInputType.emailAddress,
            ltr: true,
            onChanged: (v) => setState(() => val = v),
          ),
          Field(
            label: 'كلمة المرور',
            icon: 'lock',
            placeholder: 'كلمة المرور',
            obscure: true,
            ltr: true,
            onChanged: (v) => setState(() => code = v),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Text('نوع الحساب',
              style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
        ),
        Row(
          children: [
            Expanded(child: _roleCard(AppRole.admin, 'مسؤول لجنة المبنى', 'shield')),
            const SizedBox(width: 10),
            Expanded(child: _roleCard(AppRole.resident, 'ساكن', 'user')),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('نوع المبنى',
              style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
        ),
        Segmented(
          value: btype,
          onChanged: (v) => setState(() => btype = v as BType),
          options: const [
            SegOption(BType.residential, 'سكنية (شقق)', icon: 'building'),
            SegOption(BType.commercial, 'تجارية (محلات)', icon: 'store'),
          ],
        ),
        const SizedBox(height: 22),
        // For phone sign-in the OTP field sits right next to the "send code"
        // button (per client feedback), and "دخول" stays disabled until a valid
        // code is entered.
        if (phone) ...[
          AppButton(
            label: otpSent ? 'إعادة إرسال الرمز' : 'إرسال رمز التحقق',
            variant: BtnVariant.outline,
            size: BtnSize.lg,
            full: true,
            icon: 'send',
            onTap: _sendOtp,
          ),
          const SizedBox(height: 12),
          Field(
            label: 'رمز التحقق (OTP)',
            icon: 'lock',
            placeholder: 'أدخل الرمز',
            keyboardType: TextInputType.number,
            ltr: true,
            hint: otpSent ? 'أدخل الرمز المُرسَل إلى جوالك' : 'اضغط «إرسال رمز التحقق» أولاً',
            onChanged: (v) => setState(() => code = v),
          ),
        ],
        AppButton(
          label: 'دخول',
          size: BtnSize.lg,
          full: true,
          iconRight: 'arrowL',
          disabled: !_canSubmit,
          onTap: _submit,
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: () => ctx.go('register'),
            child: RichText(
              text: TextSpan(
                style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink500),
                children: [
                  const TextSpan(text: 'ليس لديك حساب؟ '),
                  TextSpan(
                      text: 'إنشاء حساب جديد',
                      style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.navy600)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: () => ctx.enterGuest(btype),
            child: Text('المتابعة كزائر بدلاً من ذلك',
                style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.navy600)),
          ),
        ),
      ],
    );
  }

  Widget _roleCard(AppRole r, String label, String icon) {
    final on = role == r;
    return GestureDetector(
      onTap: () => setState(() => role = r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.navy50 : AppColors.surface,
          border: Border.all(color: on ? AppColors.navy600 : AppColors.line2, width: 1.5),
          borderRadius: BorderRadius.circular(15),
          boxShadow: on
              ? [const BoxShadow(color: AppColors.navy100, spreadRadius: 3, blurRadius: 0)]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: on ? AppColors.navy700 : AppColors.navy50,
                  borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 21, color: on ? Colors.white : AppColors.navy600),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: AppType.base(
                    size: 13,
                    weight: FontWeight.w700,
                    color: on ? AppColors.navy700 : AppColors.ink700)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Create account (sign-up) ─────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final f = {'name': '', 'email': '', 'password': '', 'confirm': ''};
  bool _saving = false;

  bool get _valid =>
      f['name']!.trim().isNotEmpty &&
      f['email']!.trim().contains('@') &&
      f['password']!.length >= 6 &&
      f['password'] == f['confirm'];

  Future<void> _submit() async {
    final ctx = widget.ctx;
    if (f['password'] != f['confirm']) {
      ctx.toast('كلمتا المرور غير متطابقتين', tone: 'late');
      return;
    }
    setState(() => _saving = true);
    final err = await ctx.register(f['name']!.trim(), f['email']!.trim(), f['password']!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ctx.toast(err, tone: 'late');
    } else {
      ctx.toast('تم إنشاء حسابك بنجاح');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'إنشاء حساب جديد',
        subtitle: 'انضم إلى عمارتي',
        onBack: () => ctx.go('login'),
      ),
      children: [
        AppCard(
          color: AppColors.navy50,
          borderColor: AppColors.navy100,
          child: Row(children: [
            const IconChip(icon: 'user', tone: 'navy', size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text('الحسابات الجديدة تُنشأ كساكن. للانضمام إلى عمارة، أرسل طلب '
                  'انضمام بعد الدخول ووافق عليه مسؤول العمارة.',
                  style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
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
                  label: 'البريد الإلكتروني',
                  icon: 'mail',
                  placeholder: 'name@email.com',
                  ltr: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => f['email'] = v)),
              Field(
                  label: 'كلمة المرور',
                  icon: 'lock',
                  placeholder: '6 أحرف على الأقل',
                  ltr: true,
                  obscure: true,
                  onChanged: (v) => setState(() => f['password'] = v)),
              Field(
                  label: 'تأكيد كلمة المرور',
                  icon: 'lock',
                  placeholder: 'أعد إدخال كلمة المرور',
                  ltr: true,
                  obscure: true,
                  marginBottom: 0,
                  onChanged: (v) => setState(() => f['confirm'] = v)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: _saving ? 'جارٍ الإنشاء…' : 'إنشاء الحساب',
          size: BtnSize.lg,
          full: true,
          iconRight: 'arrowL',
          disabled: !_valid || _saving,
          onTap: _submit,
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: () => ctx.go('login'),
            child: RichText(
              text: TextSpan(
                style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink500),
                children: [
                  const TextSpan(text: 'لديك حساب؟ '),
                  TextSpan(
                      text: 'تسجيل الدخول',
                      style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.navy600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

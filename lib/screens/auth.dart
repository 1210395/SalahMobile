// عمارتي — auth screens: Splash, Guest, Login.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/auth_store.dart';
import '../api/repository.dart' show apiErrorText;
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
                        // Required slogan (notes.docx) — shown directly under the logo.
                        Text('لإدارة العمارات والمجمعات السكنية',
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
              // A guest belongs to no building, so the server sends an empty shell
              // rather than some other customer's building. Show the app's own
              // name instead of a dangling "ملخص عام — ".
              Text('ملخص عام — ${ctx.building.name.trim().isEmpty ? Brand.appName : ctx.building.name}',
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
  // Two ways in: managers/owners via email-or-phone + password; residents via a
  // QR / login code their manager issues (no public resident sign-in).
  String method = 'password';
  late BType btype = widget.ctx.btype;
  String val = '';
  String pass = '';
  // Resident QR / login code (typed or scanned).
  String loginCode = '';
  // Bumped after a scan so the code Field rebuilds with the new value.
  int _codeKey = 0;

  Future<void> _submit() async {
    final ctx = widget.ctx;
    final err = method == 'code' ? await _redeemCode() : await _signInIdentifier();
    if (err != null) ctx.toast(err, tone: 'late');
  }

  // Email-or-mobile + password. signIn() routes an '@' address through
  // loginEmail and anything else through loginIdentifier; the server returns the
  // user's real role + building, so no role/type picker is needed here.
  Future<String?> _signInIdentifier() {
    final ctx = widget.ctx;
    // A phone may be stored with spaces ("059 123 4567"); the server matches the
    // identifier exactly, so strip spaces client-side to avoid a false "wrong
    // credentials" when the resident types the number without them. Emails are
    // left untouched.
    return val.contains('@')
        ? ctx.signIn(email: val.trim(), password: pass, role: AppRole.admin, btype: btype)
        : ctx.signIn(phone: val.trim().replaceAll(' ', ''), password: pass, role: AppRole.admin, btype: btype);
  }

  // Redeem a resident QR/login code, then land the resident on their home via
  // the same post-login path signIn uses (codeLogin: true).
  Future<String?> _redeemCode() =>
      widget.ctx.signIn(code: loginCode.trim(), codeLogin: true, role: AppRole.resident, btype: btype);

  /// Password recovery for a manager: mail a code, then set a new password and
  /// sign straight in with it. Residents don't need this — their manager can
  /// reissue their password and QR from the resident's file.
  void _openForgotPassword() {
    final f = {'email': val.contains('@') ? val.trim() : '', 'code': '', 'pass': ''};
    String? devCode;
    bool sent = false;

    showAppSheet(
      context,
      StatefulBuilder(builder: (sheetCtx, setS) {
        final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(f['email']!.trim());
        final blockers = <String>[
          if (!emailOk) 'بريد إلكتروني صحيح',
          if (sent && f['code']!.trim().length < 4) 'رمز التأكيد المُرسَل إلى بريدك',
          if (sent && f['pass']!.length < 6) 'كلمة مرور جديدة من 6 أحرف على الأقل',
        ];

        return SheetShell(
          title: 'استعادة كلمة المرور',
          footer: Column(mainAxisSize: MainAxisSize.min, children: [
            if (blockers.isNotEmpty) ...[
              FormBlockedHint(reasons: blockers, title: 'لمتابعة الاستعادة:'),
              const SizedBox(height: 10),
            ],
            AppButton(
              label: sent ? 'تعيين كلمة المرور والدخول' : 'إرسال رمز الاستعادة',
              full: true,
              size: BtnSize.lg,
              icon: sent ? 'check' : 'mail',
              disabled: blockers.isNotEmpty,
              onTap: () async {
                final ctx = widget.ctx;
                if (!sent) {
                  try {
                    final dev = await AuthStore.I.forgotPassword(f['email']!.trim());
                    setS(() {
                      sent = true;
                      devCode = dev;
                    });
                    ctx.toast(dev == null
                        ? 'إن كان البريد مسجلاً لدينا فستصلك رسالة بالرمز'
                        : 'تم إنشاء الرمز');
                  } catch (e) {
                    ctx.toast(apiErrorText(e), tone: 'late');
                  }
                  return;
                }
                Navigator.of(sheetCtx).pop();
                try {
                  await AuthStore.I.resetPassword(
                      f['email']!.trim(), f['code']!.trim(), f['pass']!);
                  // Reuse the normal sign-in path so the session, the building
                  // bundle and the landing screen are set up exactly as usual.
                  final err = await ctx.signIn(
                      email: f['email']!.trim(),
                      password: f['pass']!,
                      role: AppRole.admin,
                      btype: btype);
                  ctx.toast(err ?? 'تم تعيين كلمة المرور الجديدة');
                } catch (e) {
                  ctx.toast(apiErrorText(e), tone: 'late');
                }
              },
            ),
          ]),
          children: [
            Text('أدخل بريدك الإلكتروني المسجَّل، ونرسل لك رمزاً لتعيين كلمة مرور جديدة.',
                style: AppType.base(
                    size: 12.5, weight: FontWeight.w600, color: AppColors.ink600, height: 1.6)),
            const SizedBox(height: 12),
            Field(
              label: 'البريد الإلكتروني',
              icon: 'mail',
              value: f['email']!,
              ltr: true,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => setS(() => f['email'] = v),
            ),
            if (sent) ...[
              if (devCode != null) ...[
                // Only ever present on a deployment with no mail provider.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.gold100, borderRadius: BorderRadius.circular(12)),
                  child: Text('رمز الاستعادة (وضع التجربة): $devCode',
                      style: AppType.base(
                          size: 13, weight: FontWeight.w800, color: AppColors.ink900)),
                ),
                const SizedBox(height: 12),
              ],
              Field(
                label: 'رمز الاستعادة',
                icon: 'lock',
                value: f['code']!,
                ltr: true,
                keyboardType: TextInputType.number,
                onChanged: (v) => setS(() => f['code'] = v),
              ),
              Field(
                label: 'كلمة المرور الجديدة',
                icon: 'lock',
                obscure: true,
                ltr: true,
                value: f['pass']!,
                onChanged: (v) => setS(() => f['pass'] = v),
              ),
            ],
          ],
        );
      }),
    );
  }

  Future<void> _scanCode() async {
    final ctx = widget.ctx;
    final raw = await scanQr(context);
    if (!mounted || raw == null || raw.isEmpty) return;
    setState(() {
      loginCode = raw.trim();
      _codeKey++; // force the code Field to rebuild with the scanned value
    });
    ctx.toast('تم مسح الرمز');
  }

  /// What is still stopping sign-in. This is the app's front door — a greyed
  /// button here with no reason is the worst possible first impression.
  List<String> get _missing => method == 'code'
      ? [
          if (loginCode.trim().isEmpty) 'أدخل كود الدخول أو امسح رمز QR',
        ]
      : [
          if (val.trim().isEmpty) 'أدخل بريدك الإلكتروني أو رقم جوالك',
          if (pass.isEmpty) 'أدخل كلمة المرور',
        ];

  bool get _canSubmit => _missing.isEmpty;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final codeMode = method == 'code';
    return ScreenScaffold(
      header: AppHeader(
        title: 'تسجيل الدخول',
        subtitle: 'أهلاً بعودتك إلى عمارتي',
        onBack: ctx.back,
      ),
      children: [
        Segmented(
          value: method,
          onChanged: (v) => setState(() => method = v as String),
          options: const [
            SegOption('password', 'بريد / جوال', icon: 'mail'),
            SegOption('code', 'كود الدخول / QR', icon: 'qr'),
          ],
        ),
        const SizedBox(height: 16),
        // Resident login via short code or QR scan.
        if (codeMode) ...[
          Field(
            key: ValueKey('login-code-$_codeKey'),
            label: 'كود الدخول',
            icon: 'qr',
            placeholder: 'أدخل الكود أو امسح رمز QR',
            value: loginCode,
            ltr: true,
            onChanged: (v) => setState(() => loginCode = v),
          ),
          AppButton(
            label: 'مسح رمز QR',
            variant: BtnVariant.outline,
            size: BtnSize.lg,
            full: true,
            icon: 'qr',
            onTap: _scanCode,
          ),
          const SizedBox(height: 14),
          // #2 — say the other half out loud: a resident may already have an
          // account because the manager entered them by hand.
          Text('كود الدخول خاص بالسكان — يزوّده مسؤول العمارة عبر رمز QR أو رسالة واتساب، '
              'أو يتم إدخالهم يدوياً من قِبل الإدارة. لا يوجد تسجيل عام للسكان.',
              style: AppType.base(
                  size: 12.5, weight: FontWeight.w600, color: AppColors.ink500, height: 1.6)),
        ] else ...[
          Field(
            label: 'البريد الإلكتروني أو رقم الجوال',
            icon: 'mail',
            placeholder: 'name@email.com أو 5X XXX XXXX',
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
            marginBottom: 0,
            onChanged: (v) => setState(() => pass = v),
          ),
          // A manager who forgot their password had no way back into their own
          // building — no reset existed anywhere in the app.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _openForgotPassword,
              child: Text('نسيت كلمة المرور؟',
                  style: AppType.base(
                      size: 12.5, weight: FontWeight.w700, color: AppColors.navy700)),
            ),
          ),
          const SizedBox(height: 6),
          // No phone-OTP login exists in the app — say so, instead of letting
          // someone abroad discover it only after a code never arrives.
          Text(
            !Brand.smsAvailable && Brand.smsCoverage.isNotEmpty
                ? 'الدخول هنا بكلمة المرور، أو برمز QR / كود الدخول من مسؤول العمارة. '
                    'رموز التحقق عبر SMS غير متاحة حالياً إلا للأرقام '
                    '${Brand.smsCoverage.join(' / ')}.'
                : 'الدخول هنا بكلمة المرور، أو برمز QR / كود الدخول من مسؤول العمارة.',
            style: AppType.base(
                size: 12.5, weight: FontWeight.w600, color: AppColors.ink500, height: 1.6),
          ),
        ],
        const SizedBox(height: 22),
        if (_missing.isNotEmpty) ...[
          FormBlockedHint(reasons: _missing, title: 'لتسجيل الدخول، أكمل ما يلي:'),
          const SizedBox(height: 10),
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
}

// ───────────────────────────── Create account (sign-up) ─────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final f = {
    'name': '',
    'phone': '',
    'whatsapp': '',
    'email': '',
    'password': '',
    'confirm': '',
    'code': '',
    'pref': 'email', // preferred sign-in method (email | phone)
  };
  // The email must be confirmed (mirrors the OTP flow) before "إنشاء الحساب".
  bool _codeSent = false;
  bool _saving = false;
  String? _devCode; // shown in a prominent card when the API returns it

  // A phone/WhatsApp number is valid once it carries at least 7 digits
  // (ignoring '+', spaces, and other formatting).
  static bool _phoneValid(String s) =>
      s.replaceAll(RegExp(r'[^0-9]'), '').length >= 7;

  // Sending a confirmation code needs ONE thing: somewhere to send it. It used to
  // be gated on the whole form, so a half-filled registration left the button dead
  // with nothing on screen saying why.
  bool get _emailValid {
    final e = f['email']!.trim();
    final at = e.indexOf('@');
    return at > 0 && e.indexOf('.', at) > at + 1 && !e.endsWith('.');
  }

  // The base fields must all be valid to CREATE the account. WhatsApp is optional
  // (it defaults to the phone on submit), but if the user typed one it must itself
  // be a valid phone number.
  bool get _fieldsValid => _missing.isEmpty;

  /// What is still stopping "إنشاء الحساب" — shown to the user rather than left
  /// for them to guess at a greyed-out button.
  List<String> get _missing => [
        if (f['name']!.trim().isEmpty) 'الاسم الكامل',
        if (!_phoneValid(f['phone']!)) 'رقم جوال صحيح',
        if (f['whatsapp']!.trim().isNotEmpty && !_phoneValid(f['whatsapp']!))
          'رقم واتساب صحيح',
        if (!_emailValid) 'بريد إلكتروني صحيح',
        // This account owns a building's finances — the server requires 8.
        if (f['password']!.length < 8) 'كلمة سر من 8 أحرف على الأقل',
        if (f['password']!.length >= 8 && f['password'] != f['confirm'])
          'تطابق كلمة السر مع تأكيدها',
        // The server will not create an account with an unconfirmed address, so
        // the form asks for the code instead of letting the user submit into a
        // server error.
        if (f['code']!.trim().length < 4) 'رمز التأكيد المُرسَل إلى بريدك',
      ];

  // Email verification is OPTIONAL — a manager can create the account with just
  // the base fields. If they DID enter a code, it must be a plausible length so a
  // half-typed code isn't submitted. (Email delivery isn't wired yet; once it is,
  // the code simply becomes a real verification step with no other change.)
  bool get _valid => _fieldsValid;

  Future<void> _sendCode() async {
    final ctx = widget.ctx;
    if (!_emailValid) {
      ctx.toast('أدخل بريداً إلكترونياً صحيحاً أولاً', tone: 'late');
      return;
    }
    try {
      final dev = await AuthStore.I.requestEmailCode(f['email']!.trim());
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devCode = dev; // shown in the golden card below (dev/demo)
      });
      if (dev == null) ctx.toast('تم إرسال رمز التأكيد إلى بريدك');
    } catch (_) {
      ctx.toast('تعذّر إرسال رمز التأكيد', tone: 'late');
    }
  }

  Future<void> _submit() async {
    final ctx = widget.ctx;
    if (f['password'] != f['confirm']) {
      ctx.toast('كلمتا السر غير متطابقتين', tone: 'late');
      return;
    }
    setState(() => _saving = true);
    // Register verifies the email code atomically (server-side), so a duplicate
    // email/phone fails WITHOUT consuming the code — the user can fix it and
    // retry with the same code instead of getting a misleading "code wrong".
    final err = await ctx.register(
      f['name']!.trim(),
      f['email']!.trim(),
      f['password']!,
      phone: f['phone']!.trim(),
      // Empty WhatsApp defaults to the phone number (common case); a non-empty
      // value may differ from the phone and is sent as-is.
      whatsapp: f['whatsapp']!.trim().isEmpty ? f['phone']!.trim() : f['whatsapp']!.trim(),
      emailCode: f['code']!.trim().isEmpty ? null : f['code']!.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ctx.toast(err, tone: 'late');
    } else {
      // On success _register routes to the bank subscription screen.
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
        onBack: ctx.back,
      ),
      children: [
        AppCard(
          color: AppColors.navy50,
          borderColor: AppColors.navy100,
          child: Row(children: [
            const IconChip(icon: 'user', tone: 'navy', size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text('أنشئ حساب مدير العمارة. بعد الدخول تُكمل تفعيل الاشتراك ثم '
                  'إعداد بيانات المبنى. السكان يدخلون عبر كود/رمز QR من المدير فقط.',
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
                  label: 'الاسم',
                  icon: 'user',
                  placeholder: 'الاسم الكامل',
                  onChanged: (v) => setState(() => f['name'] = v)),
              Field(
                  label: 'رقم الهاتف',
                  icon: 'phone',
                  placeholder: '5X XXX XXXX',
                  ltr: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  onChanged: (v) => setState(() => f['phone'] = v)),
              Field(
                  label: 'رقم الواتساب',
                  icon: 'phone',
                  placeholder: '5X XXX XXXX',
                  ltr: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  onChanged: (v) => setState(() => f['whatsapp'] = v)),
              Field(
                  label: 'البريد الإلكتروني',
                  icon: 'mail',
                  placeholder: 'name@email.com',
                  ltr: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => f['email'] = v)),
              Field(
                  label: 'كلمة السر',
                  icon: 'lock',
                  placeholder: '6 أحرف على الأقل',
                  ltr: true,
                  obscure: true,
                  onChanged: (v) => setState(() => f['password'] = v)),
              Field(
                  label: 'تأكيد كلمة السر',
                  icon: 'lock',
                  placeholder: 'أعد إدخال كلمة السر',
                  ltr: true,
                  obscure: true,
                  marginBottom: 0,
                  onChanged: (v) => setState(() => f['confirm'] = v)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Preferred sign-in method (Note: "option to what is the main login way").
        // Both identifiers are stored; this only sets which one is recommended.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('طريقة الدخول الأساسية',
                    style: AppType.base(size: 14, weight: FontWeight.w800)),
              ),
              Segmented(
                value: f['pref']!,
                onChanged: (v) => setState(() => f['pref'] = v as String),
                options: const [
                  SegOption('email', 'البريد الإلكتروني', icon: 'mail'),
                  SegOption('phone', 'رقم الجوال', icon: 'phone'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Email confirmation step (mirrors the OTP flow): request a code, then
        // enter it to confirm ownership of the address before the account is made.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('تأكيد البريد الإلكتروني (اختياري)',
                    style: AppType.base(size: 14, weight: FontWeight.w800)),
              ),
              AppButton(
                label: _codeSent ? 'إعادة إرسال رمز التأكيد' : 'إرسال رمز التأكيد',
                variant: BtnVariant.outline,
                size: BtnSize.lg,
                full: true,
                icon: 'send',
                // Only the email gates this — it is all the code needs.
                disabled: !_emailValid,
                onTap: _sendCode,
              ),
              if (!_emailValid)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: FormBlockedHint(reasons: ['أدخل بريدك الإلكتروني أولاً']),
                ),
              // Prominent code card (dev/demo): shows the code clearly and stays
              // visible while the user types it in, with a copy button.
              if (_devCode != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.gold400.withValues(alpha: 0.14),
                    border: Border.all(color: AppColors.gold500, width: 1.4),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('رمز التأكيد (تجريبي)',
                                style: AppType.base(size: 12, weight: FontWeight.w700, color: AppColors.ink600)),
                            const SizedBox(height: 4),
                            NumText(_devCode!,
                                style: AppType.num(size: 26, weight: FontWeight.w800, color: AppColors.navy800)),
                          ],
                        ),
                      ),
                      AppButton(
                        label: 'نسخ',
                        variant: BtnVariant.outline,
                        size: BtnSize.sm,
                        icon: 'check',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _devCode!));
                          widget.ctx.toast('تم نسخ الرمز');
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Field(
                label: 'رمز تأكيد البريد (اختياري)',
                icon: 'lock',
                placeholder: 'أدخل الرمز',
                keyboardType: TextInputType.number,
                ltr: true,
                marginBottom: 0,
                hint: _codeSent
                    ? 'أدخل الرمز المُرسَل إلى بريدك الإلكتروني'
                    : 'يمكنك إنشاء الحساب مباشرةً — تأكيد البريد اختياري',
                onChanged: (v) => setState(() => f['code'] = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Never a dead button: if the form can't be submitted yet, say exactly why.
        if (_missing.isNotEmpty) ...[
          FormBlockedHint(reasons: _missing, title: 'لإنشاء الحساب، أكمل ما يلي:'),
          const SizedBox(height: 10),
        ] else if (f['code']!.trim().isNotEmpty && f['code']!.trim().length < 4) ...[
          const FormBlockedHint(reasons: ['رمز التأكيد غير مكتمل — أو احذفه لتخطّي التأكيد']),
          const SizedBox(height: 10),
        ],
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

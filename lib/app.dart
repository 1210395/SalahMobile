// عمارتي — root app: router, roles, navigation, toast, role switcher.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'api/auth_store.dart';
import 'api/repository.dart';
import 'screens/auth.dart';
import 'screens/admin_dashboard.dart';
import 'screens/admin_units.dart';
import 'screens/admin_finance.dart';
import 'screens/admin_services.dart';
import 'screens/admin_reports.dart';
import 'screens/resident.dart';
import 'screens/onboarding.dart';
import 'screens/super_admin.dart';

const Map<String, String> _adminTabOf = {
  'home': 'home', 'units': 'units', 'payments': 'payments', 'reports': 'reports',
  'more': 'more', 'building': 'more', 'expenses': 'more', 'workers': 'more',
  'parking': 'more', 'guard': 'more', 'elevator': 'more', 'craftsmen': 'more',
  'alerts': 'more', 'years': 'more', 'approvals': 'more',
  'subscribe': 'more', 'buildingSetup': 'more', 'register': 'more',
};
const Map<String, String> _resTabOf = {
  'resHome': 'resHome', 'resReport': 'resReport', 'resElevator': 'resElevator',
  'craftsmen': 'craftsmen', 'alerts': 'alerts',
};
// Super-admin: every building-management sub-screen maps to the "المباني" tab.
const Map<String, String> _superTabOf = {
  'superReport': 'superReport', 'admins': 'admins', 'more': 'more',
  'home': 'home', 'units': 'home', 'payments': 'home', 'reports': 'home',
  'building': 'home', 'expenses': 'home', 'workers': 'home', 'parking': 'home',
  'guard': 'home', 'elevator': 'home', 'craftsmen': 'home', 'alerts': 'home',
  'years': 'home', 'approvals': 'home', 'subscribe': 'home', 'buildingSetup': 'home',
};

class AmaratiApp extends StatefulWidget {
  const AmaratiApp({
    super.key,
    this.initialScreen = 'splash',
    this.initialRole = AppRole.guest,
    this.initialBtype = BType.residential,
    this.demoEmail,
  });

  final String initialScreen;
  final AppRole initialRole;
  final BType initialBtype;

  /// Web-only review hook: when set (via `?demo=admin|resident`), the app
  /// performs a real API login with the seeded demo account on launch.
  final String? demoEmail;

  @override
  State<AmaratiApp> createState() => _AmaratiAppState();
}

class _AmaratiAppState extends State<AmaratiApp> {
  // Demo deep-links start at splash and navigate to the target screen only
  // after the API login completes, so screens that fetch in initState do so
  // while authenticated.
  late String screen = widget.demoEmail != null ? 'splash' : widget.initialScreen;
  late AppRole role = widget.initialRole;
  late BType btype = widget.initialBtype;

  ({String msg, String tone})? _toast;
  int _toastSeq = 0;
  Timer? _toastTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  /// Restore a saved session on launch and load its building bundle.
  Future<void> _bootstrap() async {
    // Load editable brand (#10) — best-effort, rebuild when ready.
    Api.I.loadSettings().then((_) {
      if (mounted) setState(() {});
    });
    // Web review hook: a real API login with a seeded demo account, optionally
    // landing on a specific screen (?demo=admin&screen=units).
    if (widget.demoEmail != null) {
      final err = await _signIn(
        email: widget.demoEmail!,
        password: 'password',
        role: AppRole.admin,
        btype: BType.residential,
      );
      if (err != null && mounted) {
        _toastMsg(err, tone: 'late');
      } else if (mounted && widget.initialScreen != 'splash') {
        _go(widget.initialScreen);
      }
      return;
    }
    // Deep-linked screens (web review links) skip the auth restore.
    if (widget.initialScreen != 'splash') return;
    final ok = await AuthStore.I.restore();
    if (!ok || !mounted) return;
    final u = AuthStore.I.user!;
    final r = _roleFromString(u.role);
    final b = btypeFromKey(u.buildingKey);
    setState(() {
      _busy = true;
      role = r;
      btype = b;
    });
    try {
      await Api.I.loadBundle(b);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      screen = _homeFor(r);
    });
  }

  AppRole _roleFromString(String s) => switch (s) {
        'superadmin' => AppRole.superadmin,
        'admin' => AppRole.admin,
        'guest' => AppRole.guest,
        _ => AppRole.resident,
      };

  /// Landing screen for a role after sign-in.
  String _homeFor(AppRole r) => switch (r) {
        AppRole.superadmin => 'superReport',
        AppRole.admin => 'home',
        AppRole.resident => 'resHome',
        AppRole.guest => 'guestHome',
      };

  String _errText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return 'تعذّر الاتصال بالخادم';
      }
    }
    return 'حدث خطأ، حاول مرة أخرى';
  }

  void _go(String s) => setState(() => screen = s);

  // Android hardware/gesture back: navigate WITHIN the app instead of exiting.
  // sub-screen -> its parent tab -> role home -> (second press within 2s) exit.
  DateTime? _lastBackAt;
  void _handleBack() {
    final maps = switch (role) {
      AppRole.superadmin => _superTabOf,
      AppRole.admin => _adminTabOf,
      AppRole.resident => _resTabOf,
      AppRole.guest => const <String, String>{},
    };
    final home = _homeFor(role);
    final tab = maps[screen];
    if (tab != null && tab != screen) {
      _go(tab); // sub-screen -> its parent tab
      return;
    }
    if (screen != home) {
      _go(home); // a non-home tab -> role home
      return;
    }
    final now = DateTime.now(); // already on home -> confirm exit
    if (_lastBackAt != null && now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    _toastMsg('اضغط رجوع مرة أخرى للخروج', tone: 'info');
  }

  Future<void> _enterGuest(BType b) async {
    setState(() {
      _busy = true;
      role = AppRole.guest;
      btype = b;
    });
    try {
      await Api.I.loadGuest(b);
    } catch (_) {
      // Fall back to seed data so guest mode still works offline.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      screen = 'guestHome';
    });
  }

  Future<String?> _requestOtp(String phone) => AuthStore.I.requestOtp(phone);

  Future<String?> _signIn({
    String? email,
    String? password,
    String? phone,
    String? code,
    String? name,
    bool codeLogin = false,
    required AppRole role,
    required BType btype,
  }) async {
    setState(() => _busy = true);
    try {
      if (codeLogin) {
        // Resident QR / login-code redemption.
        await AuthStore.I.redeemCode(code ?? '');
      } else if (phone != null && code != null) {
        await AuthStore.I.verifyOtp(phone, code,
            role: role.name, buildingKey: btypeKey(btype), name: name);
      } else if (phone != null && password != null) {
        // Mobile-number identifier + password.
        await AuthStore.I.loginIdentifier(phone, password);
      } else {
        await AuthStore.I.loginEmail(email ?? '', password ?? '');
      }
      final u = AuthStore.I.user!;
      final r = _roleFromString(u.role);
      final b = btypeFromKey(u.buildingKey);
      await Api.I.loadBundle(b);
      if (!mounted) return null;
      // First-time manager (building not set up yet) → run the setup wizard
      // before anything else; configured admins land on their dashboard.
      final needsSetup = r == AppRole.admin && (DataStore.I.building?.name.trim().isEmpty ?? true);
      setState(() {
        _busy = false;
        this.role = r;
        this.btype = b;
        screen = needsSetup ? 'buildingSetup' : _homeFor(r);
      });
      return null;
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return _errText(e);
    }
  }

  /// Create a new account (always a resident), then route to the bank
  /// subscription screen (Note 4: pay the subscription right after signup).
  Future<String?> _register(String name, String email, String password,
      {String? phone, String? whatsapp}) async {
    setState(() => _busy = true);
    try {
      await AuthStore.I.register(name, email, password, phone: phone, whatsapp: whatsapp);
      final u = AuthStore.I.user!;
      final b = btypeFromKey(u.buildingKey);
      await Api.I.loadBundle(b);
      if (!mounted) return null;
      setState(() {
        _busy = false;
        role = _roleFromString(u.role);
        btype = b;
        screen = 'subscribe';
      });
      return null;
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return _errText(e);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await AuthStore.I.logout();
    DataStore.I.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      role = AppRole.guest;
      screen = 'splash';
    });
  }

  /// Re-fetch the active bundle (after a write) and rebuild the current screen.
  Future<void> _reload() async {
    if (!AuthStore.I.isAuthed) return;
    setState(() => _busy = true);
    try {
      await Api.I.loadBundle(btype);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  /// After building setup the server promoted this user to admin of [b];
  /// refresh the user, load the bundle, and land on the admin home.
  Future<void> _becomeAdmin(BType b) async {
    setState(() => _busy = true);
    try {
      await AuthStore.I.refresh();
      await Api.I.loadBundle(b);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      role = AppRole.admin;
      btype = b;
      screen = 'home';
    });
  }

  /// Switch building type and reload the active dataset.
  Future<void> _setBtype(BType b) async {
    setState(() {
      btype = b;
      _busy = true;
    });
    try {
      if (AuthStore.I.isAuthed) {
        await Api.I.loadBundle(b);
      } else if (role == AppRole.guest) {
        await Api.I.loadGuest(b);
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  void _toastMsg(String msg, {String tone = 'ok'}) {
    setState(() {
      _toast = (msg: msg, tone: tone);
      _toastSeq++;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Ctx _buildCtx() {
    Widget superNav() => BottomNav(
          active: _superTabOf[screen] ?? 'superReport',
          onChange: _go,
          tabs: const [
            NavTab(id: 'superReport', label: 'التقرير الشامل', icon: 'pie', fillOnActive: true),
            NavTab(id: 'admins', label: 'المسؤولون', icon: 'users'),
            NavTab(id: 'home', label: 'المباني', icon: 'building'),
            NavTab(id: 'more', label: 'المزيد', icon: 'grid'),
          ],
        );
    // Super-admins reuse the admin screens but with their own nav.
    Widget adminNav() => role == AppRole.superadmin
        ? superNav()
        : BottomNav(
            active: _adminTabOf[screen],
            onChange: _go,
            tabs: [
              const NavTab(id: 'home', label: 'الرئيسية', icon: 'home', fillOnActive: true),
              NavTab(
                  id: 'units',
                  label: btype == BType.residential ? 'الشقق' : 'محلات',
                  icon: btype == BType.residential ? 'building' : 'store'),
              const NavTab(id: 'payments', label: 'الإيرادات', icon: 'wallet'),
              const NavTab(id: 'reports', label: 'التقارير', icon: 'pie'),
              const NavTab(id: 'more', label: 'المزيد', icon: 'grid'),
            ],
          );
    Widget resNav() => BottomNav(
          active: _resTabOf[screen],
          onChange: _go,
          tabs: const [
            NavTab(id: 'resHome', label: 'الرئيسية', icon: 'home', fillOnActive: true),
            NavTab(id: 'resReport', label: 'تقريري', icon: 'pie'),
            NavTab(id: 'resElevator', label: 'المصعد', icon: 'elevator'),
            NavTab(id: 'craftsmen', label: 'الصنايعية', icon: 'wrench'),
            NavTab(id: 'alerts', label: 'التنبيهات', icon: 'bell', badge: true),
          ],
        );
    Widget guestNav() => BottomNav(
          active: screen == 'login' ? 'login' : 'guestHome',
          onChange: (id) => _go(id == 'login' ? 'login' : 'guestHome'),
          tabs: const [
            NavTab(id: 'guestHome', label: 'الرئيسية', icon: 'home', fillOnActive: true),
            NavTab(id: 'login', label: 'تسجيل الدخول', icon: 'logout'),
          ],
        );

    return Ctx(
      go: _go,
      role: role,
      setRole: (r) => setState(() => role = r),
      btype: btype,
      setBtype: _setBtype,
      building: buildingFor(btype),
      toast: _toastMsg,
      openRole: _openRoleSheet,
      adminNav: adminNav(),
      resNav: resNav(),
      guestNav: guestNav(),
      busy: _busy,
      enterGuest: _enterGuest,
      requestOtp: _requestOtp,
      register: _register,
      signIn: _signIn,
      signOut: _signOut,
      reload: _reload,
      becomeAdmin: _becomeAdmin,
    );
  }

  Widget _screenFor(Ctx ctx) {
    switch (screen) {
      case 'splash':
        return SplashScreen(ctx: ctx);
      case 'guestHome':
        return GuestHome(ctx: ctx);
      case 'login':
        return LoginScreen(ctx: ctx);
      case 'home':
        return Dashboard(ctx: ctx);
      case 'building':
        return BuildingScreen(ctx: ctx);
      case 'units':
        return UnitsScreen(ctx: ctx);
      case 'payments':
        return PaymentsScreen(ctx: ctx);
      case 'expenses':
        return ExpensesScreen(ctx: ctx);
      case 'workers':
        return WorkersScreen(ctx: ctx);
      case 'parking':
        return ParkingScreen(ctx: ctx);
      case 'guard':
        return GuardScreen(ctx: ctx);
      case 'elevator':
        return ElevatorScreen(ctx: ctx);
      case 'craftsmen':
        return CraftsmenScreen(ctx: ctx);
      case 'reports':
        return ReportsScreen(ctx: ctx);
      case 'alerts':
        return AlertsScreen(ctx: ctx);
      case 'years':
        return YearsScreen(ctx: ctx);
      case 'more':
        return MoreHub(ctx: ctx);
      case 'subscribe':
        return SubscribeScreen(ctx: ctx);
      case 'buildingSetup':
        return BuildingSetupScreen(ctx: ctx);
      case 'joinUnit':
        return JoinUnitScreen(ctx: ctx);
      case 'approvals':
        return ApprovalsScreen(ctx: ctx);
      case 'register':
        return RegisterScreen(ctx: ctx);
      case 'superReport':
        return SuperReportScreen(ctx: ctx);
      case 'admins':
        return AdminsScreen(ctx: ctx);
      case 'resHome':
        return ResidentHome(ctx: ctx);
      case 'resReport':
        return ResidentReport(ctx: ctx);
      case 'resElevator':
        return ResidentElevator(ctx: ctx);
      default:
        return SplashScreen(ctx: ctx);
    }
  }

  void _openRoleSheet() {
    final roles = [
      (AppRole.admin, 'مسؤول لجنة المبنى', 'صلاحية كاملة لكل الأدوات', 'shield', 'home'),
      (AppRole.resident, 'ساكن', 'لوحة شخصية وعرض محدود', 'user', 'resHome'),
      (AppRole.guest, 'زائر', 'تقارير عامة فقط', 'eye', 'guestHome'),
    ];
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetContext, setSheet) => SheetShell(
          title: 'تبديل الدور / العرض',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('اعرض التطبيق من منظور دور مختلف',
                  style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink500)),
            ),
            ...roles.map((r) {
              final on = role == r.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      role = r.$1;
                      screen = r.$5;
                    });
                    Navigator.of(sheetContext).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: on ? AppColors.navy50 : AppColors.surface,
                      border: Border.all(color: on ? AppColors.navy600 : AppColors.line2, width: 1.5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        IconChip(icon: r.$4, tone: 'navy', size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.$2, style: AppType.base(size: 14.5, weight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(r.$3,
                                  style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        on
                            ? const AppIcon('checkCircle', size: 22, color: AppColors.navy700)
                            : const AppIcon('chevronL', size: 18, color: AppColors.ink300),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نوع المبنى',
                      style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
                  const SizedBox(height: 9),
                  Segmented(
                    value: btype,
                    onChanged: (v) {
                      _setBtype(v as BType);
                      setSheet(() {});
                    },
                    options: const [
                      SegOption(BType.residential, 'سكنية (شقق)', icon: 'building'),
                      SegOption(BType.commercial, 'تجارية (محلات)', icon: 'store'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _buildCtx();
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.page,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            // Key by btype so screens fully rebuild when the building type swaps
            // (mirrors the prototype's `key={screen + btype}`).
            child: KeyedSubtree(key: ValueKey('$screen$btype'), child: _screenFor(ctx)),
          ),
          if (_toast != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 96 + bottomInset,
              child: _ToastView(key: ValueKey(_toastSeq), data: _toast!),
            ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33141630),
                child: Center(
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(AppColors.navy700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.data});
  final ({String msg, String tone}) data;

  @override
  Widget build(BuildContext context) {
    final (bg, icon) = switch (data.tone) {
      'info' => (AppColors.navy700, 'bell'),
      'late' => (AppColors.late, 'alert'),
      _ => (AppColors.ok, 'checkCircle'),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: kEaseOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(15), boxShadow: AppShadows.lg),
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(data.msg, style: AppType.base(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// سكن برو — root app: router, roles, navigation, toast, role switcher.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'api/api_client.dart';
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
  'more': 'more', 'building': 'more', 'expenses': 'expenses', 'workers': 'more',
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
    // When any request 401s (expired Sanctum token or a rotated single-use
    // login-code), end the session locally and return to login so a stale
    // identity can't persist across launches — the root of the wrong-user bug.
    ApiClient.I.onUnauthorized = _onUnauthorized;
    _bootstrap();
  }

  void _onUnauthorized() {
    if (!mounted) return;
    AuthStore.I.logout();
    DataStore.I.clear();
    setState(() {
      role = AppRole.guest;
      screen = 'login';
    });
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

  // Real navigation history so back returns to the PREVIOUS screen (#47), not
  // always home. Forward moves (_go) push the current screen; _back pops.
  final List<String> _history = [];

  void _setScreen(String s) => setState(() => screen = s);

  void _go(String s) {
    if (s == screen) return;
    _history.add(screen);
    if (_history.length > 40) _history.removeAt(0); // guard unbounded growth
    _setScreen(s);
  }

  // In-app + Android hardware/gesture back: return to the previous screen in
  // history; with no history, collapse toward the role home, then (second press
  // within 2s) exit.
  DateTime? _lastBackAt;
  void _back() {
    if (_history.isNotEmpty) {
      _setScreen(_history.removeLast());
      return;
    }
    _collapseBack();
  }

  void _collapseBack() {
    final maps = switch (role) {
      AppRole.superadmin => _superTabOf,
      AppRole.admin => _adminTabOf,
      AppRole.resident => _resTabOf,
      AppRole.guest => const <String, String>{},
    };
    final home = _homeFor(role);
    final tab = maps[screen];
    if (tab != null && tab != screen) {
      _setScreen(tab); // sub-screen -> its parent tab
      return;
    }
    if (screen != home) {
      _setScreen(home); // a non-home tab -> role home
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
    // Set on the retry after the building picker: which of the person's
    // accounts to open (the same identifier can exist in several buildings).
    int? buildingId,
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
            role: role.name, buildingKey: btypeKey(btype), name: name, buildingId: buildingId);
      } else if (phone != null && password != null) {
        // Mobile-number identifier + password.
        await AuthStore.I.loginIdentifier(phone, password, buildingId: buildingId);
      } else {
        await AuthStore.I.loginEmail(email ?? '', password ?? '', buildingId: buildingId);
      }
      final u = AuthStore.I.user!;
      final r = _roleFromString(u.role);
      final b = btypeFromKey(u.buildingKey);
      await Api.I.loadBundle(b);
      if (!mounted) return null;
      // First-time manager (building not set up yet) → run the setup wizard
      // before anything else; configured admins land on their dashboard.
      final needsSetup = r == AppRole.admin && (DataStore.I.building?.name.trim().isEmpty ?? true);
      // A publicly-registered account is a MANAGER-in-onboarding (never a renter):
      // it has role 'resident' but no unit. Send it back into the subscription →
      // building-setup flow on every login until it's promoted to admin — instead
      // of dropping it into the renter home. (Real renters always have a unit_no,
      // assigned by their manager via QR/join, so they still land on resHome.)
      // A pending manager (registered, no building yet) goes to setup/subscribe.
      // A renter who simply has no unit assigned belongs to a building already —
      // they must land on their home's empty state, NOT the manager pay flow.
      final pendingManager = u.isPendingManager;
      setState(() {
        _busy = false;
        this.role = r;
        // Multi-building: follow the building the server actually returned.
        this.btype = DataStore.I.loadedBtype ?? b;
        screen = needsSetup
            ? 'buildingSetup'
            : pendingManager
                ? 'subscribe'
                : _homeFor(r);
      });
      return null;
    } on MultipleBuildingsException catch (e) {
      // These credentials open an account in more than one building — ask which,
      // then sign in again naming it.
      if (mounted) setState(() => _busy = false);
      final picked = await _pickBuilding(e.choices);
      if (picked == null) return null; // dismissed — not an error
      return _signIn(
        email: email, password: password, phone: phone, code: code, name: name,
        codeLogin: codeLogin, buildingId: picked, role: role, btype: btype,
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return _errText(e);
    }
  }

  /// Create a new account (always a resident), then route to the bank
  /// subscription screen (Note 4: pay the subscription right after signup).
  Future<String?> _register(String name, String email, String password,
      {String? phone, String? whatsapp, String? emailCode}) async {
    setState(() => _busy = true);
    try {
      // Start from a clean slate — a stale auto-restored session (e.g. a device
      // still holding another resident's token) must not bleed into the new
      // account. Fixes "after registering it's still the old user".
      await AuthStore.I.logout();
      DataStore.I.clear();
      await AuthStore.I.register(name, email, password,
          phone: phone, whatsapp: whatsapp, emailCode: emailCode);
      final u = AuthStore.I.user!;
      // A fresh registrant is a pending manager with NO building yet — do NOT
      // load a building bundle here (there's nothing to load, and it made
      // registration hang). They create their building on the setup screen.
      if (!mounted) return null;
      setState(() {
        _busy = false;
        role = _roleFromString(u.role);
        btype = btypeFromKey(u.buildingKey);
        screen = 'subscribe';
      });
      return null;
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      return _errText(e);
    }
  }

  /// Ask which building to sign in to when one identifier opens several. Returns
  /// the chosen building id, or null if the sheet was dismissed.
  Future<int?> _pickBuilding(List<BuildingChoice> choices) async {
    int? picked;
    await showAppSheet(
      context,
      SheetShell(
        title: 'اختر البناية',
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('لهذا الحساب أكثر من بناية — اختر البناية التي تريد الدخول إليها:',
                style: AppType.base(
                    size: 12.5, weight: FontWeight.w600, color: AppColors.ink600, height: 1.6)),
          ),
          ...choices.map((c) => ListRow(
                title: c.name.trim().isEmpty ? 'بناية ${c.id}' : c.name,
                sub: c.role == 'admin'
                    ? 'مسؤول'
                    : (c.unitNo == null ? 'ساكن' : 'ساكن · وحدة ${c.unitNo}'),
                chevron: true,
                onTap: () {
                  picked = c.id;
                  Navigator.of(context).pop();
                },
              )),
        ],
      ),
    );
    return picked;
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
    if (mounted) {
      setState(() {
        _busy = false;
        btype = DataStore.I.loadedBtype ?? btype; // stay on the real building
      });
    }
    return;
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
      // Multi-building: follow the building the server actually returned.
      btype = DataStore.I.loadedBtype ?? b;
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
              // #12: الرئيسية moved off the bottom nav to the topbar home button.
              NavTab(
                  id: 'units',
                  label: btype == BType.residential ? 'الشقق' : 'وحدات',
                  icon: btype == BType.residential ? 'building' : 'store'),
              const NavTab(id: 'payments', label: 'الإيرادات', icon: 'wallet'),
              const NavTab(id: 'expenses', label: 'المصروفات', icon: 'expense'), // #11
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
      back: _back,
      role: role,
      btype: btype,
      setBtype: _setBtype,
      building: buildingFor(btype),
      toast: _toastMsg,
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

  @override
  Widget build(BuildContext context) {
    final ctx = _buildCtx();
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
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
            Positioned.fill(
              child: ColoredBox(
                color: Color(0x33141630),
                child: Center(
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(AppColors.brand700),
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
      'info' => (AppColors.brand700, 'bell'),
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

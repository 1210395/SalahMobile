// عمارتي — navigation/role context passed to every screen (mirrors the
// prototype's `ctx` object).

import 'package:flutter/widgets.dart';
import 'data/sample_data.dart';

enum AppRole { superadmin, admin, resident, guest }

class Ctx {
  const Ctx({
    required this.go,
    required this.back,
    required this.role,
    required this.btype,
    required this.setBtype,
    required this.building,
    required this.toast,
    required this.adminNav,
    required this.resNav,
    required this.guestNav,
    required this.busy,
    required this.enterGuest,
    required this.requestOtp,
    required this.register,
    required this.signIn,
    required this.signOut,
    required this.reload,
    required this.becomeAdmin,
  });

  /// Navigate to a screen id.
  final void Function(String screen) go;

  /// Go back to the previous screen (history-aware); use for header back buttons.
  final VoidCallback back;
  final AppRole role;
  final BType btype;
  final void Function(BType) setBtype;
  final Building building;

  /// Show a transient toast. tone: 'ok' | 'info' | 'late'.
  final void Function(String msg, {String tone}) toast;

  /// Pre-built bottom navigation bars for each role.
  final Widget adminNav;
  final Widget resNav;
  final Widget guestNav;

  /// True while an auth / data-loading request is in flight.
  final bool busy;

  /// Enter guest mode for [btype] (loads the public building summary).
  final Future<void> Function(BType btype) enterGuest;

  /// Request a phone OTP. Returns the dev code in local environments.
  final Future<String?> Function(String phone) requestOtp;

  /// Create a new account (name/email/password, with optional phone/whatsapp).
  /// Returns an error or null; on success routes to the bank subscription screen.
  final Future<String?> Function(String name, String email, String password,
      {String? phone, String? whatsapp, String? emailCode}) register;

  /// Sign in, then load the building bundle. Supported modes:
  /// - email+password (email may be an address)
  /// - phone+password (mobile-number identifier)
  /// - phone+code (OTP)
  /// - code + codeLogin:true (redeem a resident QR/login code)
  /// Returns an error message on failure, or null on success.
  final Future<String?> Function({
    String? email,
    String? password,
    String? phone,
    String? code,
    String? name,
    bool codeLogin,
    required AppRole role,
    required BType btype,
  }) signIn;

  /// Sign out, clear the session, and return to the splash screen.
  final Future<void> Function() signOut;

  /// Re-fetch the active building bundle and rebuild (after a write).
  final Future<void> Function() reload;

  /// Refresh the user (now an admin of [b]) after building setup, load the
  /// bundle, and land on the admin home.
  final Future<void> Function(BType b) becomeAdmin;

  bool get res => btype == BType.residential;
}

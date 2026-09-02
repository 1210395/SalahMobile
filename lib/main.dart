// سكن برو — entry point. RTL, Cairo type, purple + gold theme.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'app_ctx.dart';
import 'data/sample_data.dart';
import 'theme/tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The device's dark/light choice, before the first frame — otherwise the app
  // paints in dark and then flips, which reads as a bug.
  await AppTheme.restore();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const AmaratiRoot());
}

/// Web-only deep-link hook so any screen can be opened directly for review,
/// e.g. `/?screen=home&role=admin&btype=commercial`, or a real demo login with
/// `/?demo=admin|resident`. No effect on mobile.
({String screen, AppRole role, BType btype, String? demoEmail}) _initialFromUrl() {
  var screen = 'splash';
  var role = AppRole.guest;
  var btype = BType.residential;
  String? demoEmail;
  if (kIsWeb) {
    final q = Uri.base.queryParameters;
    if (q['screen'] != null) screen = q['screen']!;
    switch (q['role']) {
      case 'admin':
        role = AppRole.admin;
      case 'resident':
        role = AppRole.resident;
      case 'guest':
        role = AppRole.guest;
    }
    if (q['btype'] == 'commercial') btype = BType.commercial;
    // Review hook, alongside ?screen= and ?demo=: open the app in a chosen skin
    // without touching the device's saved preference. Web only.
    switch (q['skin']) {
      case 'light':
        AppTheme.skin.value = AppSkin.light;
      case 'dark':
        AppTheme.skin.value = AppSkin.dark;
    }
    switch (q['demo']) {
      case 'admin':
        demoEmail = 'admin@amarati.app';
      case 'resident':
        demoEmail = 'resident@amarati.app';
      case 'super':
        demoEmail = 'superadmin@amarati.app';
    }
  }
  return (screen: screen, role: role, btype: btype, demoEmail: demoEmail);
}

class AmaratiRoot extends StatelessWidget {
  const AmaratiRoot({super.key});

  @override
  Widget build(BuildContext context) {
    // Every colour in the app is resolved from the active skin at build time,
    // so rebuilding from the root is all a switch needs.
    return ValueListenableBuilder<AppSkin>(
      valueListenable: AppTheme.skin,
      builder: (context, skin, _) => _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    final base = ThemeData(
      brightness: AppTheme.isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.page,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand700,
        primary: AppColors.brand700,
        surface: AppColors.surface,
        brightness: AppTheme.isDark ? Brightness.dark : Brightness.light,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    return MaterialApp(
      title: 'سكن برو',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(textTheme: GoogleFonts.cairoTextTheme(base.textTheme)),
      locale: const Locale('ar'),
      // Force RTL across the whole app.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: () {
        final init = _initialFromUrl();
        return AmaratiApp(
          initialScreen: init.screen,
          initialRole: init.role,
          initialBtype: init.btype,
          demoEmail: init.demoEmail,
        );
      }(),
    );
  }
}

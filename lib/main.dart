// عمارتي — entry point. RTL, Cairo type, navy + gold theme.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'app_ctx.dart';
import 'data/sample_data.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    switch (q['demo']) {
      case 'admin':
        demoEmail = 'admin@amarati.app';
      case 'resident':
        demoEmail = 'resident@amarati.app';
    }
  }
  return (screen: screen, role: role, btype: btype, demoEmail: demoEmail);
}

class AmaratiRoot extends StatelessWidget {
  const AmaratiRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.page,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy700,
        primary: AppColors.navy700,
        surface: AppColors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    return MaterialApp(
      title: 'عمارتي',
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

// عمارتي — design tokens. Navy + Gold brand, Cairo type, RTL.
// Direct translation of the prototype's tokens.css.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand + semantic color tokens.
class AppColors {
  AppColors._();

  // Brand — navy
  static const navy900 = Color(0xFF14163A);
  static const navy800 = Color(0xFF1B1E48);
  static const navy700 = Color(0xFF232858); // primary
  static const navy600 = Color(0xFF303676);
  static const navy500 = Color(0xFF474E96);
  static const navy300 = Color(0xFF9AA0C8);
  static const navy100 = Color(0xFFE7E9F4);
  static const navy50 = Color(0xFFF1F2FA);

  // Brand — gold
  static const gold700 = Color(0xFF8E7327);
  static const gold600 = Color(0xFFA9892F);
  static const gold500 = Color(0xFFC2A24E); // primary gold
  static const gold400 = Color(0xFFD6BC74);
  static const gold200 = Color(0xFFECDDAE);
  static const gold100 = Color(0xFFF5ECCF);
  static const gold50 = Color(0xFFFBF6E8);

  // Neutrals
  static const ink900 = Color(0xFF1A1C2E);
  static const ink700 = Color(0xFF353953);
  static const ink600 = Color(0xFF5C6080);
  static const ink500 = Color(0xFF767B97);
  static const ink400 = Color(0xFF9CA1BC);
  static const ink300 = Color(0xFFC2C6D8);
  static const line = Color(0xFFE9EBF3);
  static const line2 = Color(0xFFDEE1EE);

  static const page = Color(0xFFF4F5FA);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFAFBFD);

  // Status — paid / late / credit / warn
  static const ok = Color(0xFF1E9D6B);
  static const okBg = Color(0xFFE6F5EE);
  static const ok700 = Color(0xFF157A52);
  static const late = Color(0xFFD8453B);
  static const lateBg = Color(0xFFFBEAE8);
  static const late700 = Color(0xFFAF2E26);
  static const credit = Color(0xFF2E73D6);
  static const creditBg = Color(0xFFE7EFFB);
  static const credit700 = Color(0xFF1F569F);
  static const warn = Color(0xFFD98A1F);
  static const warnBg = Color(0xFFFBF0DE);

  // App backdrop behind the screen content.
  static const backdrop = Color(0xFF20223F);
}

/// Corner radii.
class AppRadii {
  AppRadii._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double pill = 999;
}

/// Soft, cool navy-tinted shadows.
class AppShadows {
  AppShadows._();

  static const xs = [
    BoxShadow(color: Color(0x0F14163A), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const sm = [
    BoxShadow(color: Color(0x1214163A), offset: Offset(0, 2), blurRadius: 8),
    BoxShadow(color: Color(0x0D14163A), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const md = [
    BoxShadow(color: Color(0x1A14163A), offset: Offset(0, 6), blurRadius: 20),
    BoxShadow(color: Color(0x0F14163A), offset: Offset(0, 2), blurRadius: 6),
  ];
  static const lg = [
    BoxShadow(color: Color(0x2914163A), offset: Offset(0, 16), blurRadius: 40),
  ];
  static const gold = [
    BoxShadow(color: Color(0x47A9892F), offset: Offset(0, 8), blurRadius: 22),
  ];
  static const navy = [
    BoxShadow(color: Color(0x4D232858), offset: Offset(0, 10), blurRadius: 26),
  ];
}

/// Standard easing curve (cubic-bezier(0.22, 1, 0.36, 1)).
const Cubic kEaseOut = Cubic(0.22, 1, 0.36, 1);

/// Cairo type helper. Numbers stay LTR & tabular via [num] style.
class AppType {
  AppType._();

  static TextStyle base({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink900,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Tabular numerals, forced LTR rendering for figures/dates/phones.
  static TextStyle num({
    double size = 14,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.ink900,
    double? letterSpacing,
  }) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

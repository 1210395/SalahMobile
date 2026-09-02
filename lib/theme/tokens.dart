// سكن برو — design tokens. Purple + gold brand, Cairo type, RTL.
//
// The colours are no longer compile-time constants: every token reads through
// to the active skin (see skin.dart), so the whole app follows the dark/light
// switch without any widget knowing a theme exists. `brand*` is the purple of
// the logo's towers, `accent*` the gold of its frame.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'skin.dart';

export 'skin.dart' show AppSkin, AppTheme, Palette, kDarkPalette, kLightPalette;

/// Brand + semantic color tokens, resolved against the active skin.
class AppColors {
  AppColors._();

  static Palette get _p => AppTheme.palette;

  // Brand — purple
  static Color get brand900 => _p.brand900;
  static Color get brand800 => _p.brand800;
  static Color get brand700 => _p.brand700; // primary
  static Color get brand600 => _p.brand600;
  static Color get brand500 => _p.brand500;
  static Color get brand300 => _p.brand300;
  static Color get brand100 => _p.brand100;
  static Color get brand50 => _p.brand50;

  // Accent — gold (the logo's frame colour)
  static Color get accent700 => _p.accent700;
  static Color get accent600 => _p.accent600;
  static Color get accent500 => _p.accent500;
  static Color get accent400 => _p.accent400;
  static Color get accent200 => _p.accent200;
  static Color get accent100 => _p.accent100;
  static Color get accent50 => _p.accent50;

  // Brand — red (the plinth the logo's towers stand on). Distinct from the
  // semantic `late` red.
  static Color get brandRed => _p.brandRed;
  static Color get brandRed700 => _p.brandRed700;
  static Color get brandRedBg => _p.brandRedBg;

  // Neutrals — these INVERT between skins.
  static Color get ink900 => _p.ink900;
  static Color get ink700 => _p.ink700;
  static Color get ink600 => _p.ink600;
  static Color get ink500 => _p.ink500;
  static Color get ink400 => _p.ink400;
  static Color get ink300 => _p.ink300;
  static Color get line => _p.line;
  static Color get line2 => _p.line2;

  static Color get page => _p.page;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;

  // Status — paid / late / credit / warn
  static Color get ok => _p.ok;
  static Color get okBg => _p.okBg;
  static Color get ok700 => _p.ok700;
  static Color get late => _p.late;
  static Color get lateBg => _p.lateBg;
  static Color get late700 => _p.late700;
  static Color get credit => _p.credit;
  static Color get creditBg => _p.creditBg;
  static Color get credit700 => _p.credit700;
  static Color get warn => _p.warn;
  static Color get warnBg => _p.warnBg;

  /// App backdrop behind the screen content.
  static Color get backdrop => _p.backdrop;
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

/// Soft shadows, tinted by the skin: a cool tint reads as depth on a light
/// ground and as a glow on a dark one, so the dark skin shadows in black.
class AppShadows {
  AppShadows._();

  static Color _ink(double opacity) => AppTheme.palette.shadowInk.withValues(alpha: opacity);

  static List<BoxShadow> get xs => [
        BoxShadow(color: _ink(0.06), offset: const Offset(0, 1), blurRadius: 2),
      ];
  static List<BoxShadow> get sm => [
        BoxShadow(color: _ink(0.07), offset: const Offset(0, 2), blurRadius: 8),
        BoxShadow(color: _ink(0.05), offset: const Offset(0, 1), blurRadius: 2),
      ];
  static List<BoxShadow> get md => [
        BoxShadow(color: _ink(0.10), offset: const Offset(0, 6), blurRadius: 20),
        BoxShadow(color: _ink(0.06), offset: const Offset(0, 2), blurRadius: 6),
      ];
  static List<BoxShadow> get lg => [
        BoxShadow(color: _ink(0.16), offset: const Offset(0, 16), blurRadius: 40),
      ];
  static List<BoxShadow> get accent => [
        BoxShadow(color: AppColors.accent600.withValues(alpha: 0.28),
            offset: const Offset(0, 8), blurRadius: 22),
      ];
  static List<BoxShadow> get brand => [
        BoxShadow(color: AppColors.brand700.withValues(alpha: 0.30),
            offset: const Offset(0, 10), blurRadius: 26),
      ];
}

/// Standard easing curve (cubic-bezier(0.22, 1, 0.36, 1)).
const Cubic kEaseOut = Cubic(0.22, 1, 0.36, 1);

/// Cairo type helper. Numbers stay LTR & tabular via [num] style.
class AppType {
  AppType._();

  // `color` is nullable rather than defaulted: a default value must be a
  // compile-time constant, and the ink colour now depends on the active skin.
  static TextStyle base({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink900,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Tabular numerals, forced LTR rendering for figures/dates/phones.
  static TextStyle num({
    double size = 14,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.cairo(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink900,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

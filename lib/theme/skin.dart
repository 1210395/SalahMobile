// سكن برو — the two skins, and the switch between them.
//
// The app's colours used to be compile-time constants, so there was exactly one
// look. A skin is now a bag of colours chosen at runtime, and `AppColors` reads
// through to whichever bag is active — so every screen follows the switch
// without a single widget knowing a theme exists.
//
// Dark is the default: the identity is dark (purple line-art on near-black), and
// a manager checking dues on a stairwell at night is the common case. Light is
// one tap away and is remembered per device.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSkin { dark, light }

/// Every colour the app can ask for, in one skin's worth.
///
/// The token NAMES are historical (`navy*` for the brand, `gold*` for the
/// accent) and are kept so this change stays a palette swap rather than a
/// rename across 573 call sites. They now mean: navy* = brand purple,
/// gold* = accent gold, and the neutrals invert between skins.
@immutable
class Palette {
  const Palette({
    required this.navy900, required this.navy800, required this.navy700,
    required this.navy600, required this.navy500, required this.navy300,
    required this.navy100, required this.navy50,
    required this.gold700, required this.gold600, required this.gold500,
    required this.gold400, required this.gold200, required this.gold100,
    required this.gold50,
    required this.brandRed, required this.brandRed700, required this.brandRedBg,
    required this.ink900, required this.ink700, required this.ink600,
    required this.ink500, required this.ink400, required this.ink300,
    required this.line, required this.line2,
    required this.page, required this.surface, required this.surface2,
    required this.ok, required this.okBg, required this.ok700,
    required this.late, required this.lateBg, required this.late700,
    required this.credit, required this.creditBg, required this.credit700,
    required this.warn, required this.warnBg,
    required this.backdrop,
    required this.shadowInk,
  });

  final Color navy900, navy800, navy700, navy600, navy500, navy300, navy100, navy50;
  final Color gold700, gold600, gold500, gold400, gold200, gold100, gold50;
  final Color brandRed, brandRed700, brandRedBg;
  final Color ink900, ink700, ink600, ink500, ink400, ink300;
  final Color line, line2;
  final Color page, surface, surface2;
  final Color ok, okBg, ok700;
  final Color late, lateBg, late700;
  final Color credit, creditBg, credit700;
  final Color warn, warnBg;
  final Color backdrop;

  /// What a drop shadow is tinted with. On a light ground a cool tint reads as
  /// depth; on a dark one the same tint reads as a glow, so dark goes black.
  final Color shadowInk;
}

// ── dark (default) ──────────────────────────────────────────────────────────
const kDarkPalette = Palette(
  navy900: Color(0xFF1A0E22), navy800: Color(0xFF241130), navy700: Color(0xFF7E42B4),
  navy600: Color(0xFF9A63CE), navy500: Color(0xFFB183DF), navy300: Color(0xFFC3A8DA),
  navy100: Color(0xFF2E1F3D), navy50: Color(0xFF241A31),

  // Lifted so gold still reads as gold on near-black — the first dark pass came
  // out muddy on the "add" button and the tenant badge.
  gold700: Color(0xFFE0C07A), gold600: Color(0xFFC08F44), gold500: Color(0xFFD2A85C),
  gold400: Color(0xFFE2C688), gold200: Color(0xFF3F3117), gold100: Color(0xFF33280F),
  gold50: Color(0xFF241B0C),

  brandRed: Color(0xFFC4453F), brandRed700: Color(0xFFD8615B), brandRedBg: Color(0xFF3A1A18),

  // The neutrals invert: ink becomes light, the ground becomes near-black.
  ink900: Color(0xFFEFEAF4), ink700: Color(0xFFD6CFE0), ink600: Color(0xFFA79BB6),
  ink500: Color(0xFF8E84A0), ink400: Color(0xFF6E6480), ink300: Color(0xFF4A4159),
  line: Color(0xFF241A31), line2: Color(0xFF2E2340),

  page: Color(0xFF08050C), surface: Color(0xFF140D1C), surface2: Color(0xFF1A1124),

  // Status tints flip from pale washes to dark ones, and their inks brighten —
  // #AF2E26 on near-black is unreadable.
  ok: Color(0xFF3FBF8C), okBg: Color(0xFF10281F), ok700: Color(0xFF5FD3A6),
  late: Color(0xFFE4635C), lateBg: Color(0xFF2E1513), late700: Color(0xFFF08B85),
  credit: Color(0xFF5B95E8), creditBg: Color(0xFF121C2C), credit700: Color(0xFF86B4F2),
  warn: Color(0xFFE0A64A), warnBg: Color(0xFF2C2213),

  backdrop: Color(0xFF06040A),
  shadowInk: Color(0xFF000000),
);

// ── light ───────────────────────────────────────────────────────────────────
const kLightPalette = Palette(
  navy900: Color(0xFF2A1436), navy800: Color(0xFF3C1B4A), navy700: Color(0xFF6B2F9E),
  navy600: Color(0xFF7E42B4), navy500: Color(0xFF9A63CE), navy300: Color(0xFFC3A8DA),
  navy100: Color(0xFFEDE4F5), navy50: Color(0xFFF6F3FA),

  // Darker than the logo's gold: #937135 on white is ~4.4:1, fine for a hairline
  // but not for a label, so the text-carrying steps go darker still.
  gold700: Color(0xFF6B4F24), gold600: Color(0xFF7A5C2B), gold500: Color(0xFF937135),
  gold400: Color(0xFFB08C46), gold200: Color(0xFFEEDDA8), gold100: Color(0xFFF6EDCE),
  gold50: Color(0xFFFBF6E8),

  brandRed: Color(0xFFB02324), brandRed700: Color(0xFF8C1B1C), brandRedBg: Color(0xFFF8E7E5),

  ink900: Color(0xFF1A1220), ink700: Color(0xFF353953), ink600: Color(0xFF5C6080),
  ink500: Color(0xFF767B97), ink400: Color(0xFF9CA1BC), ink300: Color(0xFFC2C6D8),
  line: Color(0xFFE9EBF3), line2: Color(0xFFDEE1EE),

  page: Color(0xFFF6F3FA), surface: Color(0xFFFFFFFF), surface2: Color(0xFFFAFBFD),

  ok: Color(0xFF1E9D6B), okBg: Color(0xFFE6F5EE), ok700: Color(0xFF157A52),
  late: Color(0xFFD8453B), lateBg: Color(0xFFFBEAE8), late700: Color(0xFFAF2E26),
  credit: Color(0xFF2E73D6), creditBg: Color(0xFFE7EFFB), credit700: Color(0xFF1F569F),
  warn: Color(0xFFD98A1F), warnBg: Color(0xFFFBF0DE),

  backdrop: Color(0xFF2A1436),
  shadowInk: Color(0xFF2A1436),
);

/// The active skin. Widgets never read this directly — they read [AppColors],
/// which reads through to here — but the root listens so a change repaints
/// everything at once.
class AppTheme {
  AppTheme._();

  static const _prefsKey = 'sakanpro_skin';

  /// Dark by default, per the brand.
  static final ValueNotifier<AppSkin> skin = ValueNotifier<AppSkin>(AppSkin.dark);

  static Palette get palette => skin.value == AppSkin.dark ? kDarkPalette : kLightPalette;

  static bool get isDark => skin.value == AppSkin.dark;

  /// Restore the device's choice. Called once before the first frame; a device
  /// that has never chosen stays dark.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Honour whichever value was stored — reading only 'light' meant this
      // upgraded rather than restored, and a device that had chosen dark could
      // be left on light by whatever the process happened to hold.
      switch (prefs.getString(_prefsKey)) {
        case 'light':
          skin.value = AppSkin.light;
        case 'dark':
          skin.value = AppSkin.dark;
        default:
          break; // nothing stored: leave the default (dark) alone
      }
    } catch (_) {
      // A device that cannot read preferences still gets a working app.
    }
  }

  static Future<void> toggle() async {
    skin.value = isDark ? AppSkin.light : AppSkin.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, isDark ? 'dark' : 'light');
    } catch (_) {
      // The switch still applies for this session even if it can't be saved.
    }
  }
}

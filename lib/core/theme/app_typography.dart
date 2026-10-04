import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Katisha typography system.
/// Uses Google Fonts (Inter) as primary, matching the web app's font stack.
///
/// Every style is a cached [TextStyle] constant rather than a getter. Building
/// a style goes through `GoogleFonts.inter`, which hashes the font family and
/// consults the font loader (and can trigger an asset/network load) on every
/// call. These getters used to be rebuilt on each access, so a single frame
/// that rendered a few dozen `AppTypography.bodyMedium` styles paid that cost
/// dozens of times. Caching them keeps the cost to once per app run.
///
/// Callers still copy before mutating (`AppTypography.bodyMedium.copyWith(...)`),
/// so callers can't accidentally mutate the shared instance.
abstract final class AppTypography {
  static TextStyle _base({double? fontSize, FontWeight? fontWeight, Color? color}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.text,
    );
  }

  // ── Display ──────────────────────────────────
  static final displayLarge = _base(fontSize: 32, fontWeight: FontWeight.w700);
  static final displayMedium = _base(fontSize: 28, fontWeight: FontWeight.w700);
  static final displaySmall = _base(fontSize: 24, fontWeight: FontWeight.w600);

  // ── Headlines ────────────────────────────────
  static final headlineLarge = _base(fontSize: 22, fontWeight: FontWeight.w700);
  static final headlineMedium = _base(fontSize: 20, fontWeight: FontWeight.w600);
  static final headlineSmall = _base(fontSize: 18, fontWeight: FontWeight.w600);

  // ── Titles ───────────────────────────────────
  static final titleLarge = _base(fontSize: 18, fontWeight: FontWeight.w600);
  static final titleMedium = _base(fontSize: 16, fontWeight: FontWeight.w600);
  static final titleSmall = _base(fontSize: 14, fontWeight: FontWeight.w600);

  // ── Body ─────────────────────────────────────
  static final bodyLarge = _base(fontSize: 16, fontWeight: FontWeight.w400);
  static final bodyMedium = _base(fontSize: 14, fontWeight: FontWeight.w400);
  static final bodySmall = _base(fontSize: 12, fontWeight: FontWeight.w400);

  // ── Labels ───────────────────────────────────
  static final labelLarge = _base(fontSize: 14, fontWeight: FontWeight.w500);
  static final labelMedium = _base(fontSize: 12, fontWeight: FontWeight.w500);
  static final labelSmall = _base(fontSize: 10, fontWeight: FontWeight.w500);

  // ── Button ───────────────────────────────────
  static final buttonLarge =
      _base(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.white);
  static final buttonMedium =
      _base(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.white);
  static final buttonSmall =
      _base(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.white);
}
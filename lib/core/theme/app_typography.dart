import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Katisha typography system.
/// Uses Google Fonts (Inter) as primary, matching the web app's font stack.
abstract final class AppTypography {
  static TextStyle _base({double? fontSize, FontWeight? fontWeight, Color? color}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.text,
    );
  }

  // ── Display ──────────────────────────────────
  static TextStyle get displayLarge => _base(fontSize: 32, fontWeight: FontWeight.w700);
  static TextStyle get displayMedium => _base(fontSize: 28, fontWeight: FontWeight.w700);
  static TextStyle get displaySmall => _base(fontSize: 24, fontWeight: FontWeight.w600);

  // ── Headlines ────────────────────────────────
  static TextStyle get headlineLarge => _base(fontSize: 22, fontWeight: FontWeight.w700);
  static TextStyle get headlineMedium => _base(fontSize: 20, fontWeight: FontWeight.w600);
  static TextStyle get headlineSmall => _base(fontSize: 18, fontWeight: FontWeight.w600);

  // ── Titles ───────────────────────────────────
  static TextStyle get titleLarge => _base(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle get titleMedium => _base(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle get titleSmall => _base(fontSize: 14, fontWeight: FontWeight.w600);

  // ── Body ─────────────────────────────────────
  static TextStyle get bodyLarge => _base(fontSize: 16, fontWeight: FontWeight.w400);
  static TextStyle get bodyMedium => _base(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get bodySmall => _base(fontSize: 12, fontWeight: FontWeight.w400);

  // ── Labels ───────────────────────────────────
  static TextStyle get labelLarge => _base(fontSize: 14, fontWeight: FontWeight.w500);
  static TextStyle get labelMedium => _base(fontSize: 12, fontWeight: FontWeight.w500);
  static TextStyle get labelSmall => _base(fontSize: 10, fontWeight: FontWeight.w500);

  // ── Button ───────────────────────────────────
  static TextStyle get buttonLarge => _base(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.white);
  static TextStyle get buttonMedium => _base(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.white);
  static TextStyle get buttonSmall => _base(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.white);
}

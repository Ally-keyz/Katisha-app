import 'package:flutter/material.dart';

/// Katisha brand color palette extracted from web CSS custom properties.
/// All hex values match the web frontend exactly.
abstract final class AppColors {
  // ── Primary ──────────────────────────────────
  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primaryLight = Color(0xFFDBEAFE);

  // ── Info / Secondary ─────────────────────────
  static const Color info = Color(0xFF0075A8);

  // ── Text ─────────────────────────────────────
  static const Color text = Color(0xFF0F172A);
  static const Color textSub = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  // ── Backgrounds ──────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceVariant = Color(0xFFF1F5F9);

  // ── Borders ──────────────────────────────────
  static const Color border = Color(0xFFE2E8F0);

  // ── Semantic ─────────────────────────────────
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color errorBorder = Color(0xFFFECACA);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color success = Color(0xFF1D4ED8);
  static const Color successBg = Color(0xFFDBEAFE);

  // ── Booking Status ───────────────────────────
  static const Color statusPendingAgent = Color(0xFF7C3AED);
  static const Color statusAwaiting = Color(0xFFD97706);
  static const Color statusExpired = Color(0xFFDC2626);
  static const Color statusPaid = Color(0xFF0891B2);
  static const Color statusUploaded = Color(0xFF7C3AED);
  static const Color statusDeparted = Color(0xFF1D4ED8);
  static const Color statusCompleted = Color(0xFF1E40AF);
  static const Color statusCancelled = Color(0xFF6B7280);

  // ── Seat Map ─────────────────────────────────
  static const Color seatAvailable = Color(0xFF1D4ED8);
  static const Color seatSelected = Color(0xFF10B981);
  static const Color seatTaken = Color(0xFF6B7280);

  /// Returns the color for a given booking status string.
  static Color forStatus(String status) {
    return switch (status) {
      'pending' => statusAwaiting,
      'confirmed' => success,
      'rejected' => error,
      'cancelled' => statusCancelled,
      'completed' => statusCompleted,
      'paid' => statusPaid,
      _ => textMuted,
    };
  }
}

import 'dart:math';
import 'package:flutter/material.dart';

/// Which fabric treatment a button surface gets.
///
/// * [canvas] — a soft, matte paper/canvas grain: thousands of low-contrast
///   specks in slightly lighter and darker shades of the base colour.
/// * [felt] — the same grain plus a few faint, wispy organic fibre strokes
///   (softly curved arcs) that read as pressed felt.
enum ClothTextureStyle { canvas, felt }

/// Paints a cloth/fabric texture over a solid button colour.
///
/// The painter is deterministic (seeded), so it never shimmers or re-rolls
/// between frames, and it derives its lighter/darker specks from [base] so the
/// texture always belongs to the colour beneath it. The texture is drawn as a
/// mostly-transparent overlay: the button's own [base] fill still supplies the
/// solid background, and the specks/strokes add the matte fabric depth on top.
class ClothTexturePainter extends CustomPainter {
  const ClothTexturePainter({
    required this.base,
    this.style = ClothTextureStyle.felt,
    this.seed = 7,
  });

  final Color base;
  final ClothTextureStyle style;

  /// Fixed seed keeps the grain stable across repaints and button instances.
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final light = _shift(base, 0.14);
    final dark = _shift(base, -0.16);
    final rng = Random(seed);

    // ── Fine digital grain ─────────────────────────────────────────
    // A dense field of tiny translucent specks. Roughly 1 speck per 14px² so
    // the surface reads as cloth, not noise.
    final grainPaint = Paint();
    final count = (size.width * size.height / 14).round().clamp(120, 3200);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.5 + rng.nextDouble() * 1.1;
      final lighten = rng.nextBool();
      grainPaint.color =
          (lighten ? light : dark).withValues(alpha: 0.05 + rng.nextDouble() * 0.07);
      canvas.drawCircle(Offset(x, y), r, grainPaint);
    }

    // ── Wispy fibre strokes (felt only) ────────────────────────────
    if (style == ClothTextureStyle.felt) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6 + rng.nextDouble() * 0.8
        ..strokeCap = StrokeCap.round;

      final strokes = 14 + rng.nextInt(10);
      for (var i = 0; i < strokes; i++) {
        final startX = rng.nextDouble() * size.width;
        final startY = rng.nextDouble() * size.height;
        // A long, shallow sweep so the fibres feel like woven strands rather
        // than stray hairs.
        final length = size.width * (0.25 + rng.nextDouble() * 0.45);
        final angle = -0.35 + rng.nextDouble() * 0.7; // mostly horizontal
        final endX = startX + cos(angle) * length;
        final endY = startY + sin(angle) * length;
        final ctrlX = (startX + endX) / 2 + (rng.nextDouble() - 0.5) * 26;
        final ctrlY = (startY + endY) / 2 + (rng.nextDouble() - 0.5) * 14;

        final path = Path()
          ..moveTo(startX, startY)
          ..quadraticBezierTo(ctrlX, ctrlY, endX, endY);

        final lighten = rng.nextBool();
        strokePaint.color =
            (lighten ? light : dark).withValues(alpha: 0.04 + rng.nextDouble() * 0.06);
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(ClothTexturePainter oldDelegate) {
    return oldDelegate.base != base || oldDelegate.style != style;
  }

  Color _shift(Color color, double deltaLightness) {
    final hsl = HSLColor.fromColor(color);
    final next = (hsl.lightness + deltaLightness).clamp(0.0, 1.0);
    return hsl.withLightness(next).toColor();
  }
}

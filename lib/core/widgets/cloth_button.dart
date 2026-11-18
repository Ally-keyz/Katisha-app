import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/cloth_texture.dart';

/// A full-width button whose background carries a subtle cloth/fabric texture
/// (see [ClothTexturePainter]) instead of a flat solid fill.
///
/// Drop-in replacement for the plain `ElevatedButton` used across the booking
/// flow. It keeps the same look and feel — rounded corners, ink ripple, a
/// disabled state — and layers the grain/fibre texture over the base colour.
class ClothButton extends StatelessWidget {
  const ClothButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.color = AppColors.primary,
    this.disabledColor,
    this.textureStyle = ClothTextureStyle.felt,
    this.height = 52,
    this.borderRadius,
    this.side,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color color;
  final Color? disabledColor;
  final ClothTextureStyle textureStyle;
  final double height;
  final BorderRadius? borderRadius;
  final BorderSide? side;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius =
        borderRadius ?? BorderRadius.circular(AppSpacing.radiusMd);
    final surfaceColor =
        enabled ? color : (disabledColor ?? color.withValues(alpha: 0.5));

    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: side ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (enabled)
                CustomPaint(
                  painter: ClothTexturePainter(
                    base: color,
                    style: textureStyle,
                  ),
                ),
              Center(
                child: Padding(
                  padding:
                      padding ?? const EdgeInsets.symmetric(horizontal: 16),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

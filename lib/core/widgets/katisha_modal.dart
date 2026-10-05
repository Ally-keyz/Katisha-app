import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Fraction of the screen height every Katisha selector sheet occupies.
///
/// The booking flow (destination, agency, date, hour and payment) all use this
/// one number so the five dialogs feel like the same component: a panel
/// anchored to the bottom edge, taking the full width, with the remaining ~11%
/// left as the dimmed backdrop above it.
const double kKatishaModalHeightFactor = 0.89;

/// Shows a Katisha modal: a bottom sheet with a fixed height of
/// [kKatishaModalHeightFactor] of the screen.
///
/// The panel is flush with the left, right and bottom edges — only the top two
/// corners are rounded — so it reads as a sheet rising from the bottom rather
/// than a card floating in the middle. This matches how the web build presents
/// the same selectors on a phone viewport.
Future<T?> showKatishaModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  Duration transitionDuration = const Duration(milliseconds: 340),
  bool dark = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.45),
    transitionDuration: transitionDuration,
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      // Curve the raw value rather than allocating a `CurvedAnimation`: a
      // CurvedAnimation registers a status listener on its parent and is never
      // disposed when the dialog route is popped, leaking a listener for every
      // bottom sheet ever opened.
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(animation.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              // Slide the sheet up from a meaningful distance: the previous
              // offset of `0.18 * (1 - t)` pixels was invisible, so the sheet
              // only faded in. 64px reads as a deliberate sheet motion.
              offset: Offset(0, 64 * (1 - t)),
              child: child,
            ),
          );
        },
      );
    },
    pageBuilder: (ctx, animation, secondaryAnimation) {
      // Read size and insets inside the dialog route: the keyboard or a
      // rotation can change them between the tap and the route being built.
      // The sheet is lifted by the keyboard inset and sized against the
      // remaining space, so a pinned footer (e.g. the Pay button) is never
      // buried behind the on-screen keyboard.
      final media = MediaQuery.of(ctx);
      final bottomInset = media.viewInsets.bottom;
      final availableHeight = media.size.height - bottomInset;
      final panelHeight = availableHeight * kKatishaModalHeightFactor;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child:           Material(
            color: dark ? const Color(0xFF141414) : AppColors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl),
            ),
            clipBehavior: Clip.antiAlias,
            // A soft edge instead of a large blurred shadow: full-width sheets
            // are expensive to shade, and the dimmed barrier already separates
            // the panel from the page.
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            child: SizedBox(
              height: panelHeight,
              width: double.infinity,
              child: SafeArea(
                top: false,
                child: builder(ctx),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Standard chrome shared by every Katisha modal: a drag-handle-free header
/// with the title, an optional subtitle and a close button, a scrollable body
/// and an optional pinned footer.
class KatishaModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  final String closeLabel;

  /// Lets the body own its scrolling. Set false when [child] already scrolls.
  final bool bodyScrollable;

  /// Renders the sheet in the dark promoter theme.
  final bool dark;

  const KatishaModal({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onClose,
    this.closeLabel = 'Close',
    this.bodyScrollable = true,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : null,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.bodySmall.copyWith(
                      color: dark ? const Color(0xFF9CA3AF) : AppColors.textSub,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            tooltip: closeLabel,
            icon: const Icon(Icons.close, size: 20),
            color: dark ? const Color(0xFF9CA3AF) : AppColors.textSub,
            style: IconButton.styleFrom(
              backgroundColor: dark ? const Color(0xFF27272A) : AppColors.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );

    final body = bodyScrollable
        ? Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: child,
            ),
          )
        : Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: child,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        header,
        Divider(height: 1, color: dark ? const Color(0xFF27272A) : AppColors.border),
        body,
        if (footer != null) ...[
          Divider(height: 1, color: dark ? const Color(0xFF27272A) : AppColors.border),
          Container(color: dark ? const Color(0xFF141414) : AppColors.white, child: footer),
        ],
      ],
    );
  }
}

/// Full-width primary action button used in Katisha modal footers.
class KatishaModalAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool isSecondary;

  const KatishaModalAction({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary ? AppColors.surface : AppColors.primary,
          foregroundColor: isSecondary ? AppColors.text : AppColors.white,
          disabledBackgroundColor: isSecondary
              ? AppColors.surfaceVariant
              : AppColors.primaryLight,
          disabledForegroundColor: isSecondary
              ? AppColors.textMuted
              : AppColors.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: isSecondary
                ? const BorderSide(color: AppColors.border)
                : BorderSide.none,
          ),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isSecondary ? AppColors.primary : AppColors.white,
                ),
              )
            : Text(
                label,
                // AppTypography.buttonMedium hardcodes a white color, which
                // would make the secondary (light) button's label invisible.
                style: AppTypography.buttonMedium.copyWith(
                  color: isSecondary ? AppColors.text : AppColors.white,
                ),
              ),
      ),
    );
  }
}

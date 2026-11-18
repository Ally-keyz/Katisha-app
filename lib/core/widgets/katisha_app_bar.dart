import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Standard app bar for all shell-tab screens.
///
/// Layout: [title] on the left · Bus Lottie in the center · notification
/// bell on the right. Flat white surface: no elevation, no scroll tint and no
/// divider, so it blends into the borderless screens below it.
class KatishaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Color? titleColor;
  final bool showBackButton;
  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;
  final int unreadCount;
  final bool showLottie;
  final bool showBell;

  const KatishaAppBar({
    super.key,
    required this.title,
    this.titleColor,
    this.showBackButton = false,
    this.bottom,
    this.extraActions,
    this.unreadCount = 0,
    this.showLottie = true,
    this.showBell = true,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.text,
      // Material 3 tints the bar (and adds a shadow) once content scrolls
      // underneath it. Turn both off to keep the bar perfectly flat.
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      // White toolbar, so pin dark status/navigation bar icons regardless of
      // which route (e.g. the dark welcome page) was on screen before.
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: AppColors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      automaticallyImplyLeading: showBackButton,
      title: Text(
        title,
        style: AppTypography.titleLarge.copyWith(
          color: titleColor ?? AppColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      actions: [
        if (extraActions != null) ...extraActions!,
        if (showLottie)
          // Center Lottie bus animation. Capped at 24 fps and isolated behind
          // a RepaintBoundary so the decorative loop does not repaint the
          // toolbar (and everything around it) on every frame.
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: RepaintBoundary(
                child: Lottie.asset(
                  'assets/lottie/bus.json',
                  height: 36,
                  width: 36,
                  repeat: true,
                  frameRate: const FrameRate(24),
                ),
              ),
            ),
          ),
        if (showBell)
          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.text,
                ),
                onPressed: () => context.push('/notifications'),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(width: 8),
      ],
      bottom: bottom,
    );
  }
}
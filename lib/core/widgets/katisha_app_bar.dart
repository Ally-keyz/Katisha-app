import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Standard app bar for all shell-tab screens.
///
/// Layout: [title] on the left · Bus Lottie in the center · notification
/// bell on the right. White background, no elevation.
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
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: showBackButton,
      title: Text(
        title,
        style: AppTypography.titleLarge.copyWith(color: titleColor ?? AppColors.text),
      ),
      actions: [
        if (extraActions != null) ...extraActions!,
        if (showLottie)
          // Center Lottie bus animation
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Lottie.asset(
                'assets/lottie/bus.json',
                height: 36,
                width: 36,
                repeat: true,
              ),
            ),
          ),
        if (showBell)
          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.text),
                onPressed: () => context.push('/notifications'),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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
        const SizedBox(width: 4),
      ],
      bottom: bottom,
    );
  }
}

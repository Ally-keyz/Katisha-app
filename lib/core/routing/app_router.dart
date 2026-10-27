import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../platform/badge_counts.dart';

import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/my_bookings/presentation/screens/my_bookings_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/booking/presentation/screens/booking_wizard_screen.dart';
import '../../features/booking/presentation/screens/route_search_results_screen.dart';
import '../../features/booking/presentation/screens/payment_waiting_screen.dart';
import '../../features/ticket/presentation/screens/ticket_view_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter provider.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── User role routes (bottom nav shell) ──────────────────────────────
      ShellRoute(
        builder: (context, state, child) => UserHomeShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BookingWizardScreen(embedded: true),
            ),
          ),
          GoRoute(
            path: '/my-bookings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MyBookingsScreen(),
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: NotificationsScreen(),
            ),
          ),
        ],
      ),

      // ── Booking flow (full-screen, no bottom nav) ────────────────────────
      GoRoute(
        path: '/book',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return BookingWizardScreen(extra: extra);
        },
      ),
      GoRoute(
        path: '/search-results',
        builder: (context, state) => const RouteSearchResultsScreen(),
      ),
      GoRoute(
        path: '/payment-waiting',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PaymentWaitingScreen(
            bookingId: extra['bookingId'] as String? ?? '',
            referenceCode: extra['referenceCode'] as String? ?? '',
            paymentMethod: extra['paymentMethod'] as String? ?? '',
            phone: extra['phone'] as String? ?? '',
            totalAmount: extra['totalAmount'] as int? ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/ticket/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId']!;
          return TicketViewScreen(bookingId: bookingId);
        },
      ),
    ],
  );
});

/// Shell widget for the User role with bottom navigation.
class UserHomeShell extends ConsumerWidget {
  final Widget child;
  const UserHomeShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paths = _userPaths;
    final currentIndex = _getCurrentIndex(context, paths);

    return Scaffold(
      body: child,
      bottomNavigationBar: _buildBottomNav(
        context: context,
        currentIndex: currentIndex < 0 ? 0 : currentIndex,
        paths: paths,
        ref: ref,
      ),
    );
  }

  static int _getCurrentIndex(BuildContext context, List<String> paths) {
    final location = GoRouterState.of(context).matchedLocation;
    return paths.indexOf(location);
  }
}

/// Builds the platform-adaptive bottom navigation bar.
Widget _buildBottomNav({
  required BuildContext context,
  required int currentIndex,
  required List<String> paths,
  required WidgetRef ref,
}) {
  // Live badge counts (tickets + notifications) that update automatically.
  final badgeCounts = ref.watch(badgeCountsProvider);
  // Resolved once: this runs on every shell rebuild, and each destination used
  // to do its own Localizations lookup.
  final l10n = AppLocalizations.of(context);

  return NavigationBar(
    selectedIndex: currentIndex,
    onDestinationSelected: (index) => context.go(paths[index]),
    backgroundColor: Colors.white,
    elevation: 0,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    indicatorColor: const Color(0xFFDBEAFE),
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    ),
    surfaceTintColor: Colors.transparent,
    destinations: [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: l10n.translate('nav_home'),
      ),
      NavigationDestination(
        icon: _BadgeIcon(
          icon: Icons.confirmation_num_outlined,
          selectedIcon: Icons.confirmation_num,
          selected: false,
          count: badgeCounts.ticketCount,
          color: const Color(0xFF0854AE),
        ),
        selectedIcon: _BadgeIcon(
          icon: Icons.confirmation_num_outlined,
          selectedIcon: Icons.confirmation_num,
          selected: true,
          count: badgeCounts.ticketCount,
          color: const Color(0xFF0854AE),
        ),
        label: l10n.translate('nav_my_tickets'),
      ),
      NavigationDestination(
        icon: _BadgeIcon(
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications,
          selected: false,
          count: badgeCounts.notificationCount,
          color: Colors.red,
        ),
        selectedIcon: _BadgeIcon(
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications,
          selected: true,
          count: badgeCounts.notificationCount,
          color: Colors.red,
        ),
        label: l10n.translate('nav_alerts'),
      ),
    ],
  );
}

/// Icon widget for a bottom-nav destination that shows a badge with a count.
/// Counts above 9 are shown as "9+".
class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final int count;
  final Color color;

  const _BadgeIcon({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final displayed = count > 9 ? '9+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? selectedIcon : icon),
        if (count > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 16,
              ),
              alignment: Alignment.center,
              child: Text(
                displayed,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

const _userPaths = ['/home', '/my-bookings', '/notifications'];

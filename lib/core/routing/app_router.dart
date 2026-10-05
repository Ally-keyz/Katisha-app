import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../platform/badge_counts.dart';

import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/welcome/presentation/screens/welcome_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/my_bookings/presentation/screens/my_bookings_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/booking/presentation/screens/booking_wizard_screen.dart';
import '../../features/booking/presentation/screens/route_search_results_screen.dart';
import '../../features/booking/presentation/screens/payment_waiting_screen.dart';
import '../../features/ticket/presentation/screens/ticket_view_screen.dart';
import '../../features/promoter/presentation/screens/promoter_dashboard_screen.dart';
import '../../features/promoter/presentation/screens/promoter_earnings_screen.dart';
import '../../features/promoter/presentation/screens/promoter_referrals_screen.dart';
import '../../features/promoter/presentation/screens/promoter_setup_screen.dart';
import '../../features/promoter/presentation/screens/promoter_payouts_screen.dart';
import '../../features/promoter/presentation/widgets/promoter_gate.dart';

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
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── User role routes (bottom nav shell) ──────
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
          // ── Promoter (tab; the gate handles non-promoter accounts) ──
          GoRoute(
            path: '/promoter',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PromoterGate(child: PromoterDashboardScreen()),
            ),
          ),
        ],
      ),

      // ── Promoter onboarding ──
      // Kept outside the shell so a signed-out visitor can apply directly.
      GoRoute(
        path: '/promoter/setup',
        builder: (context, state) => const PromoterSetupScreen(),
      ),

      // ── Promoter ledgers (full-screen drill-downs) ─
      GoRoute(
        path: '/promoter/earnings',
        builder: (context, state) => const PromoterGate(
          child: PromoterEarningsScreen(),
        ),
      ),
      GoRoute(
        path: '/promoter/referrals',
        builder: (context, state) => const PromoterGate(
          child: PromoterReferralsScreen(),
        ),
      ),
      GoRoute(
        path: '/promoter/payouts',
        builder: (context, state) => const PromoterGate(
          child: PromoterPayoutsScreen(),
        ),
      ),

      // ── Booking flow (full-screen, no bottom nav) ─
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
class UserHomeShell extends ConsumerStatefulWidget {
  final Widget child;
  const UserHomeShell({super.key, required this.child});

  @override
  ConsumerState<UserHomeShell> createState() => _UserHomeShellState();
}

class _UserHomeShellState extends ConsumerState<UserHomeShell> {
  /// See the guard in [build]: keeps the invalid-location redirect to one
  /// post-frame callback instead of one per rebuild.
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    // Resolve any stored session so `isPromoterProvider` can decide whether the
    // promoter tab belongs in the bar. Without this the tab could never appear:
    // nothing else resolves the session until /promoter is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final paths = _visiblePaths(ref);
    final currentIndex = _getCurrentIndex(context, paths);
    // A deep link (or a stale tab state) can land on /promoter with an account
    // that has no promoter role. Send them somewhere valid instead of showing a
    // blank tab.
    if (currentIndex < 0) {
      // Guarded so this fires once per invalid location instead of queueing a
      // fresh post-frame callback (and another `go`) on every rebuild.
      if (!_redirected) {
        _redirected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/home');
        });
      }
    } else {
      _redirected = false;
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: _buildBottomNav(
        context: context,
        currentIndex: currentIndex < 0 ? 0 : currentIndex,
        paths: paths,
        ref: ref,
      ),
    );
  }

  /// `/promoter` is always in the tab bar.
  ///
  /// Hiding it behind the promoter role meant a plain account had no way to
  /// discover or start the setup flow, so the feature looked missing entirely.
  /// [PromoterGate] decides what the tab renders: the dashboard for a promoter,
  /// the setup form for a signed-in non-promoter, sign-in options otherwise.
  static List<String> _visiblePaths(WidgetRef ref) {
    return const [..._userPaths, _promoterPath];
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
  // The promoter screen is dark, so only on that tab does the nav go dark.
  final dark = GoRouterState.of(context).matchedLocation == _promoterPath;

  return Container(
    decoration: BoxDecoration(
      color: dark ? Colors.black : Colors.white,
      border: Border(
        top: BorderSide(
          color: dark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
          width: 0.5,
        ),
      ),
    ),
    child: dark
        ? Theme(
            data: Theme.of(context).copyWith(
              navigationBarTheme: NavigationBarThemeData(
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
            child: _buildNavBar(context, currentIndex, paths, l10n, dark, badgeCounts),
          )
        : _buildNavBar(context, currentIndex, paths, l10n, dark, badgeCounts),
  );
}

Widget _buildNavBar(
  BuildContext context,
  int currentIndex,
  List<String> paths,
  dynamic l10n,
  bool dark,
  dynamic badgeCounts,
) {
  return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => context.go(paths[index]),
      backgroundColor: dark ? Colors.black : Colors.white,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorColor: dark ? const Color(0x332563EB) : const Color(0xFFDBEAFE),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: dark
          ? WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            )
          : null,
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
            color: const Color(0xFF1D4ED8),
          ),
          selectedIcon: _BadgeIcon(
            icon: Icons.confirmation_num_outlined,
            selectedIcon: Icons.confirmation_num,
            selected: true,
            count: badgeCounts.ticketCount,
            color: const Color(0xFF1D4ED8),
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
        // Only present when _visiblePaths included it.
        if (paths.contains(_promoterPath))
          NavigationDestination(
            icon: const Icon(Icons.campaign_outlined),
            selectedIcon: const Icon(Icons.campaign),
            label: l10n.translate('nav_promoter'),
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
const _promoterPath = '/promoter';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/welcome/presentation/screens/welcome_screen.dart';
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
        ],
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
class UserHomeShell extends StatelessWidget {
  final Widget child;
  const UserHomeShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: _buildBottomNav(
        context: context,
        currentIndex: currentIndex,
      ),
    );
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return switch (location) {
      '/home' => 0,
      '/my-bookings' => 1,
      '/notifications' => 2,
      _ => 0,
    };
  }
}

/// Builds the platform-adaptive bottom navigation bar.
Widget _buildBottomNav({
  required BuildContext context,
  required int currentIndex,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1D4ED8).withOpacity(0.08),
          blurRadius: 12,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => context.go(_userPaths[index]),
      backgroundColor: Colors.white,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorColor: const Color(0xFFDBEAFE),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      surfaceTintColor: Colors.transparent,
      destinations: _userNavItems
          .map((item) => NavigationDestination(
                icon: Icon(item['icon'] as IconData),
                selectedIcon: Icon(item['selectedIcon'] as IconData),
                label: item['label'] as String,
              ))
          .toList(),
    ),
  );
}

const _userNavItems = [
  {'icon': Icons.home_outlined, 'selectedIcon': Icons.home, 'label': 'Home'},
  {'icon': Icons.confirmation_num_outlined, 'selectedIcon': Icons.confirmation_num, 'label': 'My Tickets'},
  {'icon': Icons.notifications_outlined, 'selectedIcon': Icons.notifications, 'label': 'Alerts'},
];

const _userPaths = ['/home', '/my-bookings', '/notifications'];

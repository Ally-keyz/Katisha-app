import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/ticket_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/application/auth_controller.dart';

/// Simple splash: a static logo on the brand gradient. No artificial delay —
/// it navigates the moment persisted session tokens are loaded.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Loads persisted tokens and navigates immediately when done. A signed-in
  /// promoter goes straight to their dashboard; everyone else lands on the
  /// welcome screen as before.
  Future<void> _bootstrap() async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.init();
    if (!mounted) return;

    if (apiClient.isAuthenticated) {
      // Fetch and save the user's tickets locally in the background, so they
      // are available offline (ticket JSON + private ticket images).
      startBackgroundTicketSync(ref);

      final user = await ref.read(authControllerProvider.notifier).restore();
      if (!mounted) return;
      if (user != null && user.isPromoter) {
        context.go('/promoter');
        return;
      }
    }
    context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Center(
          child: Image.asset(
            'assets/images/splash_logo.png',
            width: 200,
            fit: BoxFit.contain,
            color: Colors.white,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
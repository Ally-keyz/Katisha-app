import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/ticket_sync_service.dart';
import '../../../../core/theme/app_colors.dart';

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

  /// Loads persisted tokens and navigates immediately when done. Every launch
  /// passes through the welcome screen first, even when the user is already
  /// logged in.
  Future<void> _bootstrap() async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.init();
    if (!mounted) return;

    if (apiClient.isAuthenticated) {
      // Fetch and save the user's tickets locally in the background, so they
      // are available offline (ticket JSON + private ticket images).
      startBackgroundTicketSync(ref);
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
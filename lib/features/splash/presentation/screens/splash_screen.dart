import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final apiClient = ref.read(apiClientProvider);
    await apiClient.init();

    if (!mounted) return;
    if (apiClient.isAuthenticated) {
      // Start at the language selection screen on every app launch, so a
      // refresh never drops the user straight into the booking wizard.
      context.go('/onboarding');
    } else {
      context.go('/welcome');
    }
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
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(
              <double>[
                0, 0, 0, 0, 255, // R
                0, 0, 0, 0, 255, // G
                0, 0, 0, 0, 255, // B
                0, 0, 0, 1, 0,   // A
              ],
            ),
            child: Image.asset(
              'assets/images/logo.png',
              width: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_bus,
                size: 64,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

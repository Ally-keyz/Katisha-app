import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  /// Sends the user to whichever promoter screen fits their account.
  ///
  /// The welcome page is the app entry point, so no screen has resolved the
  /// stored session yet. Resolve it here (once) so an existing promoter lands
  /// straight on the dashboard instead of being shown the setup form.
  Future<void> _openPromoter(BuildContext context, WidgetRef ref) async {
    ref.read(soundServiceProvider).playClick();

    final auth = ref.read(authControllerProvider);
    final user = auth is AuthSignedIn
        ? auth.user
        : await ref.read(authControllerProvider.notifier).restore();
    if (!context.mounted) return;

    context.go(user != null && user.isPromoter ? '/promoter' : '/promoter/setup');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // `SystemUiOverlayStyle.light` alone leaves `statusBarColor` unset, so
        // the global white bar from `main()` keeps showing behind these dark
        // icons. Force both bars transparent so the photo and its dark wash
        // reach all the way to the top/bottom of the screen.
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
            'assets/images/welcome.jpg',
            fit: BoxFit.cover,
            // Decode at screen resolution instead of full file resolution so
            // this full-bleed image never consumes many MB of decoded memory.
            cacheWidth:
                (MediaQuery.of(context).size.width *
                        MediaQuery.of(context).devicePixelRatio)
                    .round(),
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.primaryDark,
              child: const Center(
                child: Icon(
                  Icons.directions_bus,
                  size: 96,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          // Flat dark wash so the white headline and both buttons stay legible
          // over any part of the photo, not just the bottom third.
          const ColoredBox(
            color: Color(0x8C000000),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    l10n.translate('welcome_to_katisha'),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        ref.read(soundServiceProvider).playClick();
                        context.go('/onboarding');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(54),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        textStyle: AppTypography.buttonLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      child: Text(l10n.translate('book_a_ticket')),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openPromoter(context, ref),
                      icon: const Icon(Icons.campaign_outlined, size: 20),
                      label: Text(l10n.translate('make_money_katisha')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,
                        // Transparent fill with a white edge reads as a
                        // secondary action over the photo without hiding it.
                        backgroundColor: const Color(0x33FFFFFF),
                        side: const BorderSide(color: AppColors.white, width: 1.5),
                        minimumSize: const Size.fromHeight(54),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        textStyle: AppTypography.buttonLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

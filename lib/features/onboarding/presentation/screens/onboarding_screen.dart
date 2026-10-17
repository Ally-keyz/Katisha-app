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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.white,
      // This page is white, so the status-bar clock/signal/battery must be dark.
      // Stated explicitly because the splash page leaves light icons behind and
      // would otherwise bleed into this route.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: AppColors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.directions_bus,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.language,
                        size: 28,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.translate('choose_language'),
                      style: AppTypography.displaySmall.copyWith(color: AppColors.text),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.translate('select_preferred_language'),
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _buildLanguageOption(
                      context,
                      code: 'en',
                      label: 'English',
                      flag: '\u{1F1EC}\u{1F1E7}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildLanguageOption(
                      context,
                      code: 'rw',
                      label: 'Kinyarwanda',
                      flag: '\u{1F1F7}\u{1F1FC}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildLanguageOption(
                      context,
                      code: 'sw',
                      label: 'Kiswahili',
                      flag: '\u{1F1F9}\u{1F1FF}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildLanguageOption(
                      context,
                      code: 'fr',
                      label: 'Fran\u00e7ais',
                      flag: '\u{1F1EB}\u{1F1F7}',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openPromoter,
                    icon: const Icon(Icons.campaign_outlined, size: 20),
                    label: Text(l10n.translate('make_money_katisha')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      textStyle: AppTypography.buttonMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context, {
    required String code,
    required String label,
    required String flag,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(AppSpacing.md),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () => _selectLanguage(code),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectLanguage(String code) async {
    ref.read(soundServiceProvider).vibrate();
    final locale = Locale(code);
    await LanguagePreference.setLocale(locale);

    // Update the app locale provider to trigger rebuild
    ref.read(appLocaleProvider.notifier).state = locale;

    if (!mounted) return;
    context.go('/home');
  }

  /// Sends the user to whichever promoter screen fits their account.
  ///
  /// The language page is now the app entry point, so no screen has resolved
  /// the stored session yet. Resolve it here (once) so an existing promoter
  /// lands straight on the dashboard instead of being shown the setup form.
  Future<void> _openPromoter() async {
    ref.read(soundServiceProvider).playClick();

    final auth = ref.read(authControllerProvider);
    final user = auth is AuthSignedIn
        ? auth.user
        : await ref.read(authControllerProvider.notifier).restore();
    if (!mounted) return;

    context.go(user != null && user.isPromoter ? '/promoter' : '/promoter/setup');
  }
}

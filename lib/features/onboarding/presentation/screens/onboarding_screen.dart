import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

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
      body: SafeArea(
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.translate('select_preferred_language'),
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
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
          ],
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
}

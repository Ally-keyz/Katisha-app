import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Language picker bottom sheet widget.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('language'), style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _buildLanguageOption(
              context,
              ref: ref,
              code: 'en',
              label: 'English',
              flag: '🇬🇧',
              currentCode: l10n.languageCode,
            ),
            _buildLanguageOption(
              context,
              ref: ref,
              code: 'rw',
              label: 'Kinyarwanda',
              flag: '🇷🇼',
              currentCode: l10n.languageCode,
            ),
            _buildLanguageOption(
              context,
              ref: ref,
              code: 'sw',
              label: 'Kiswahili',
              flag: '🇹🇿',
              currentCode: l10n.languageCode,
            ),
            _buildLanguageOption(
              context,
              ref: ref,
              code: 'fr',
              label: 'Français',
              flag: '🇫🇷',
              currentCode: l10n.languageCode,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context, {
    required WidgetRef ref,
    required String code,
    required String label,
    required String flag,
    required String currentCode,
  }) {
    final isSelected = code == currentCode;
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(label, style: AppTypography.bodyLarge),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      onTap: isSelected
          ? null
          : () async {
              await LanguagePreference.setLocale(Locale(code));
              ref.read(appLocaleProvider.notifier).state = Locale(code);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
    );
  }
}

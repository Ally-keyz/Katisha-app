import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/models/promoter_models.dart';

/// Shared presentation helpers for the promoter area.
///
/// The React promoter pages define the reference look; these widgets keep the
/// Flutter screens visually consistent with each other and avoid repeating the
/// same status-colour switch five times.

/// Formats a RWF amount with thousands separators: `1234567` → `1,234,567`.
String formatRwf(num amount) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer(rounded < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats a commission/payout amount with its currency: `12,500 RWF`.
String formatMoney(num amount, [String currency = 'RWF']) {
  return '${formatRwf(amount)} $currency';
}

/// `250720000007` / `0720000007` → `250 72 000 0007` style grouping is overkill
/// for the list views, so keep the stored number as-is apart from trimming.
String formatPhone(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '-';
  if (trimmed.length <= 12) return trimmed;
  return trimmed;
}

/// Abbreviated month translation keys, 1-indexed to match `DateTime.month`.
///
/// The full `month_*` names are too wide for the compact trend axis, so the
/// promoter area uses the `*_abbr` variants.
const _monthKeys = [
  'month_jan_abbr',
  'month_feb_abbr',
  'month_mar_abbr',
  'month_apr_abbr',
  'month_may_abbr',
  'month_jun_abbr',
  'month_jul_abbr',
  'month_aug_abbr',
  'month_sep_abbr',
  'month_oct_abbr',
  'month_nov_abbr',
  'month_dec_abbr',
];

String monthLabel(AppLocalizations l10n, int month) {
  final m = month - 1;
  if (m < 0 || m > 11) return '';
  return l10n.translate(_monthKeys[m]);
}

/// Short date for list rows: `12 Mar 2026`.
String formatPromoterDate(DateTime? date, AppLocalizations l10n) {
  if (date == null) return '-';
  return '${date.day} ${monthLabel(l10n, date.month)} ${date.year}';
}

/// Colours + copy for a commission status.
({Color fg, Color bg, String label}) commissionStatusStyle(
  String status,
  AppLocalizations l10n,
) {
  return switch (status) {
    'paid' => (
      fg: AppColors.statusPaid,
      bg: const Color(0xFFE0F2FE),
      label: l10n.translate('status_paid'),
    ),
    'earned' => (
      fg: AppColors.primary,
      bg: AppColors.primaryLight,
      label: l10n.translate('status_earned'),
    ),
    'pending' => (
      fg: AppColors.statusAwaiting,
      bg: AppColors.warningBg,
      label: l10n.translate('status_pending'),
    ),
    'reversed' => (
      fg: AppColors.statusCancelled,
      bg: AppColors.surfaceVariant,
      label: l10n.translate('status_reversed'),
    ),
    _ => (fg: AppColors.textSub, bg: AppColors.surfaceVariant, label: status),
  };
}

/// Colours + copy for a payout status.
({Color fg, Color bg, String label}) payoutStatusStyle(
  String status,
  AppLocalizations l10n,
) {
  return switch (status) {
    'paid' => (
      fg: AppColors.statusPaid,
      bg: const Color(0xFFE0F2FE),
      label: l10n.translate('status_paid'),
    ),
    'processing' => (
      fg: AppColors.statusAwaiting,
      bg: AppColors.warningBg,
      label: l10n.translate('status_processing'),
    ),
    'failed' => (
      fg: AppColors.error,
      bg: AppColors.errorBg,
      label: l10n.translate('status_failed'),
    ),
    _ => (
      fg: AppColors.textSub,
      bg: AppColors.surfaceVariant,
      label: l10n.translate('status_pending'),
    ),
  };
}

/// Colours + copy for a referral status.
({Color fg, Color bg, String label}) referralStatusStyle(
  String status,
  AppLocalizations l10n,
) {
  return switch (status) {
    'converted' => (
      fg: AppColors.statusPaid,
      bg: const Color(0xFFE0F2FE),
      label: l10n.translate('status_converted'),
    ),
    'pending' => (
      fg: AppColors.statusAwaiting,
      bg: AppColors.warningBg,
      label: l10n.translate('status_pending'),
    ),
    _ => (fg: AppColors.textSub, bg: AppColors.surfaceVariant, label: status),
  };
}

/// Colours + copy for the promoter account status.
({Color fg, Color bg, String label}) promoterStatusStyle(
  PromoterStatus status,
  AppLocalizations l10n,
) {
  return switch (status) {
    PromoterStatus.active => (
      fg: AppColors.statusPaid,
      bg: const Color(0xFFE0F2FE),
      label: l10n.translate('status_active'),
    ),
    PromoterStatus.pending => (
      fg: AppColors.statusAwaiting,
      bg: AppColors.warningBg,
      label: l10n.translate('status_pending_review'),
    ),
    PromoterStatus.suspended => (
      fg: AppColors.error,
      bg: AppColors.errorBg,
      label: l10n.translate('status_suspended'),
    ),
    PromoterStatus.unknown => (
      fg: AppColors.textSub,
      bg: AppColors.surfaceVariant,
      label: l10n.translate('status_unknown'),
    ),
  };
}

/// Small pill used for every status in the promoter area.
class PromoterStatusChip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const PromoterStatusChip({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
  });

  factory PromoterStatusChip.commission(String status, AppLocalizations l10n) {
    final s = commissionStatusStyle(status, l10n);
    return PromoterStatusChip(label: s.label, fg: s.fg, bg: s.bg);
  }

  factory PromoterStatusChip.payout(String status, AppLocalizations l10n) {
    final s = payoutStatusStyle(status, l10n);
    return PromoterStatusChip(label: s.label, fg: s.fg, bg: s.bg);
  }

  factory PromoterStatusChip.referral(String status, AppLocalizations l10n) {
    final s = referralStatusStyle(status, l10n);
    return PromoterStatusChip(label: s.label, fg: s.fg, bg: s.bg);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Dashboard tile: a big number with a caption.
class PromoterStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const PromoterStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.hint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSub,
                    ),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (hint != null && hint!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card wrapper used for every promoter list section.
class PromoterCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const PromoterCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      ),
    );
  }
}

/// Empty-state block for the list screens.
class PromoterEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const PromoterEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textSub,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error block with a retry affordance.
class PromoterErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const PromoterErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSub,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(AppLocalizations.of(context).translate('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal sparkline of the monthly earnings trend.
class PromoterTrendBar extends StatelessWidget {
  final List<PromoterTrendPoint> points;

  const PromoterTrendBar({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    // Only the last 6 points are ever drawn, so the scale is derived from those
    // alone. Wrapping the whole server list in `map().fold()` walked every
    // point on every build just to discard all but six.
    final visible = points.length <= 6
        ? points
        : points.sublist(points.length - 6);

    var max = 0.0;
    for (final point in visible) {
      if (point.total > max) max = point.total;
    }
    // A flat all-zero history has no scale, so fall back to 1 to avoid a
    // divide-by-zero producing NaN heights.
    final scale = max <= 0 ? 1.0 : max;

    // Resolved once instead of per bar in the loop below.
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in visible)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      formatRwf(point.total),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 8,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 6 + 56 * (point.total / scale),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthLabel(l10n, point.month),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 8,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

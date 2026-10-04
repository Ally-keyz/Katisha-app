import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/promoter_providers.dart';
import '../../data/models/promoter_models.dart';
import '../widgets/promoter_ui.dart';
import 'promoter_settings_modal.dart';

class PromoterDashboardScreen extends ConsumerStatefulWidget {
  const PromoterDashboardScreen({super.key});

  @override
  ConsumerState<PromoterDashboardScreen> createState() =>
      _PromoterDashboardScreenState();
}

class _PromoterDashboardScreenState
    extends ConsumerState<PromoterDashboardScreen> {
  PromoterStats? _stats;
  PromoterProfile? _profile;
  String _error = '';
  bool _loading = true;
  bool _requestingPayout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final repo = ref.read(promoterRepositoryProvider);
    // Profile and stats are independent; one failing should not blank the
    // other, so they are fetched separately and merged.
    final statsResult = await repo.getStats();
    final profileResult = await repo.getProfile();

    if (!mounted) return;

    statsResult.fold(
      (failure) {
        setState(() {
          _error = failure.message;
          _loading = false;
        });
      },
      (stats) {
        setState(() {
          _stats = stats;
          _error = '';
          _loading = false;
        });
      },
    );

    profileResult.fold((_) {}, (profile) {
      if (mounted) setState(() => _profile = profile);
    });
  }

  Future<void> _requestPayout() async {
    if (_requestingPayout) return;

    final l10n = AppLocalizations.of(context);
    final payoutPhone = _profile?.payoutPhone ?? _profile?.phone;

    final confirmed = await showKatishaModal<bool>(
      context: context,
      builder: (ctx) => KatishaModal(
        title: l10n.translate('promoter_withdraw_now'),
        subtitle: l10n.translate('promoter_payouts_subtitle'),
        bodyScrollable: false,
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: KatishaModalAction(
                  label: l10n.translate('cancel'),
                  isSecondary: true,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: KatishaModalAction(
                  label: l10n.translate('promoter_withdraw'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMoney(_stats?.earnings.availableBalance ?? 0),
              style: AppTypography.displaySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${l10n.translate('promoter_payout_phone')}: '
              '${payoutPhone ?? l10n.translate('promoter_using_account_phone')}',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _requestingPayout = true);
    final result = await ref.read(promoterRepositoryProvider).requestPayout();
    if (!mounted) return;

    setState(() => _requestingPayout = false);

    result.fold((failure) => _toast(failure.message, isError: true), (payout) {
      final paid = payout.isPaid;
      _toast(
        paid
            ? '${formatMoney(payout.amount)} · '
                  '${payout.phone ?? payoutPhone ?? ''}'
            : payout.failureReason ?? payout.status,
        isError: !paid,
      );
      // The balance and history both changed either way.
      ref.read(promoterDataVersionProvider.notifier).state++;
      _load();
    });
  }

  Future<void> _openSettings() async {
    await showKatishaModal<void>(
      context: context,
      builder: (_) => const PromoterSettingsModal(),
    );
    ref.read(promoterDataVersionProvider.notifier).state++;
    _load();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading && _stats == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: KatishaAppBar(
          title: l10n.translate('nav_promoter'),
          showBell: false,
        ),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 3)),
      );
    }

    if (_error.isNotEmpty && _stats == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: KatishaAppBar(
          title: l10n.translate('nav_promoter'),
          showBell: false,
        ),
        body: PromoterErrorView(message: _error, onRetry: _load),
      );
    }

    final stats = _stats!;
    final earnings = stats.earnings;
    final status = PromoterStatus.parse(_profile?.status);
    // Resolved once: the chip used to call this three times for the same
    // status, rebuilding the record and re-running the lookup each time.
    final statusStyle = promoterStatusStyle(status, l10n);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KatishaAppBar(
        title: l10n.translate('nav_promoter'),
        showBell: false,
        extraActions: [
          IconButton(
            onPressed: _openSettings,
            tooltip: l10n.translate('settings'),
            icon: const Icon(Icons.settings_outlined, size: 22),
            color: AppColors.textSub,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_error.isNotEmpty) ...[
              _banner(_error, isError: true),
              const SizedBox(height: AppSpacing.md),
            ],

            // Referral code + account status.
            PromoterCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profile?.name ?? 'Promoter',
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.translate('promoter_your_code'),
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PromoterStatusChip(
                        label: statusStyle.label,
                        fg: statusStyle.fg,
                        bg: statusStyle.bg,
                      ),
                    ],
                  ),
                  if (_profile?.promoterCode != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _codeBox(_profile!.promoterCode!),
                  ],
                  if (status == PromoterStatus.pending) ...[
                    const SizedBox(height: AppSpacing.md),
                    _banner(
                      l10n.translate('promoter_pending_notice'),
                      isError: false,
                      isWarning: true,
                    ),
                  ],
                  if (status == PromoterStatus.suspended) ...[
                    const SizedBox(height: AppSpacing.md),
                    _banner(
                      l10n.translate('promoter_suspended_notice'),
                      isError: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Available balance + withdraw.
            PromoterCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('promoter_available_balance'),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSub,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(earnings.availableBalance, earnings.currency),
                      style: AppTypography.displaySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n
                        .translate('promoter_paid_out_total')
                        .replaceAll(
                          '%s',
                          formatMoney(earnings.paidTotal, earnings.currency),
                        ),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: (!stats.canRequestPayout || _requestingPayout)
                          ? null
                          : _requestPayout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: AppColors.surfaceVariant,
                        disabledForegroundColor: AppColors.textMuted,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      icon: _requestingPayout
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                            ),
                      label: Text(
                        stats.canRequestPayout
                            ? l10n.translate('promoter_withdraw_now')
                            : l10n.translate('promoter_nothing_to_withdraw'),
                        style: AppTypography.titleSmall.copyWith(
                          color: stats.canRequestPayout
                              ? AppColors.white
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Counters.
            Row(
              children: [
                Expanded(
                  child: PromoterStatTile(
                    label: l10n.translate('promoter_this_month'),
                    value: formatRwf(stats.thisMonth.total),
                    hint: l10n
                        .translate('promoter_commissions_n')
                        .replaceAll('%d', '${stats.thisMonth.count}'),
                    icon: Icons.calendar_month_outlined,
                    accent: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PromoterStatTile(
                    label: l10n.translate('nav_promoter_referrals'),
                    value: '${stats.referrals.total}',
                    hint: '${stats.referrals.converted} converted',
                    icon: Icons.people_outline,
                    accent: AppColors.info,
                    onTap: () => context.push('/promoter/referrals'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: PromoterStatTile(
                    label: l10n.translate('promoter_conversion'),
                    value: '${stats.referrals.conversionRate}%',
                    hint: l10n
                        .translate('promoter_referrals_total_n')
                        .replaceAll('%d', '${stats.referrals.total}'),
                    icon: Icons.trending_up,
                    accent: AppColors.statusPaid,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PromoterStatTile(
                    label: l10n.translate('promoter_lifetime'),
                    value: formatRwf(earnings.lifetimeEarned),
                    hint: l10n
                        .translate('promoter_commissions_n')
                        .replaceAll('%d', '${earnings.commissionCount}'),
                    icon: Icons.history,
                    accent: AppColors.statusAwaiting,
                    onTap: () => context.push('/promoter/earnings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Trend.
            if (stats.trend.isNotEmpty) ...[
              PromoterCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('promoter_monthly_earnings'),
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PromoterTrendBar(points: stats.trend),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Navigation to the three ledger screens.
            _navTile(
              icon: Icons.receipt_long_outlined,
              title: l10n.translate('nav_promoter_earnings'),
              subtitle: l10n.translate('promoter_earnings_subtitle'),
              onTap: () => context.push('/promoter/earnings'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _navTile(
              icon: Icons.people_outline,
              title: l10n.translate('nav_promoter_referrals'),
              subtitle: l10n.translate('promoter_referrals_subtitle'),
              onTap: () => context.push('/promoter/referrals'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _navTile(
              icon: Icons.account_balance_outlined,
              title: l10n.translate('nav_promoter_payouts'),
              subtitle: l10n.translate('promoter_payouts_subtitle'),
              onTap: () => context.push('/promoter/payouts'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return PromoterCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_right,
            size: 20,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _codeBox(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              code,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(
                      context,
                    ).translate('promoter_code_copied'),
                  ),
                  backgroundColor: AppColors.text,
                ),
              );
            },
            tooltip: AppLocalizations.of(context).translate('copy'),
            icon: const Icon(Icons.copy, size: 18, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _banner(
    String message, {
    required bool isError,
    bool isWarning = false,
  }) {
    final color = isError ? AppColors.error : AppColors.warning;
    final bg = isError ? AppColors.errorBg : AppColors.warningBg;
    final border = isError ? AppColors.errorBorder : const Color(0xFFFDE68A);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

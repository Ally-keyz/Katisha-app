import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/promoter_providers.dart';
import '../../data/models/promoter_models.dart';
import '../widgets/promoter_ui.dart';

/// Paginated commission ledger: `GET /promoter/earnings`.
///
/// Shows the aggregate summary above the rows so the numbers on this screen
/// always match the dashboard's available balance.
class PromoterEarningsScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const PromoterEarningsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PromoterEarningsScreen> createState() =>
      _PromoterEarningsScreenState();
}

class _PromoterEarningsScreenState
    extends ConsumerState<PromoterEarningsScreen> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final List<PromoterCommission> _commissions = [];
  PromoterEarningsSummary? _summary;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  /// Optional status filter passed to the server.
  String? _status;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 320) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore) return;
    if (!reset && !_hasMore) return;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final nextPage = reset ? 1 : _page + 1;
    final result = await ref
        .read(promoterRepositoryProvider)
        .getEarnings(page: nextPage, limit: _pageSize, status: _status);

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
        _loadingMore = false;
      }),
      (data) => setState(() {
        if (reset) _commissions.clear();
        _commissions.addAll(data.commissions);
        _summary = data.earnings;
        _page = data.pagination.page;
        _hasMore = data.pagination.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KatishaAppBar(
        title: l10n.translate('nav_promoter_earnings'),
        showBackButton: !widget.embedded,
        showBell: false,
      ),
      body: Column(
        children: [
          if (_summary != null) _summaryBar(l10n),
          _statusFilter(l10n),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _buildBody(l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(AppLocalizations l10n) {
    final s = _summary!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('promoter_available_balance'),
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(s.availableBalance, s.currency),
              style: AppTypography.displaySmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _summaryCell(
                l10n.translate('promoter_lifetime'),
                formatRwf(s.lifetimeEarned),
              ),
              _summaryCell(
                l10n.translate('promoter_paid_out_total').replaceAll('%s', ''),
                formatRwf(s.paidTotal),
              ),
              _summaryCell(
                l10n.translate('promoter_reversed'),
                formatRwf(s.reversedTotal),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCell(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusFilter(AppLocalizations l10n) {
    final options = <String?, String>{
      null: l10n.translate('all'),
      'pending': l10n.translate('status_pending'),
      'earned': l10n.translate('status_earned'),
      'paid': l10n.translate('status_paid'),
      'reversed': l10n.translate('status_reversed'),
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          for (final entry in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _status == entry.key,
                onSelected: (_) {
                  setState(() => _status = entry.key);
                  _load(reset: true);
                },
                labelStyle: AppTypography.labelMedium.copyWith(
                  color: _status == entry.key
                      ? AppColors.white
                      : AppColors.textSub,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    if (_error != null && _commissions.isEmpty) {
      return PromoterErrorView(
        message: _error!,
        onRetry: () => _load(reset: true),
      );
    }
    if (_commissions.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          PromoterEmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.translate('promoter_no_commissions'),
            subtitle: l10n.translate('promoter_no_commissions_sub'),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _commissions.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= _commissions.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _row(l10n, _commissions[index]);
      },
    );
  }

  /// [l10n] is threaded in from [_buildBody]: resolving it here instead would
  /// run an InheritedWidget lookup for every row on every scroll frame.
  Widget _row(AppLocalizations l10n, PromoterCommission commission) {
    return PromoterCard(
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
                      commission.booking?.referenceCode ??
                          l10n.translate('promoter_commission'),
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPromoterDate(commission.earnedAt, l10n),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(commission.amount, commission.currency),
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PromoterStatusChip.commission(commission.status, l10n),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                '${commission.rate}% of ${formatMoney(commission.baseAmount, commission.currency)}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              if (commission.booking?.travelDate != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '· ${l10n.translate("travel_date")} ${formatPromoterDate(commission.booking!.travelDate, l10n)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

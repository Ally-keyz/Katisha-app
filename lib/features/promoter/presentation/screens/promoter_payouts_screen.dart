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

/// Payout history: `GET /promoter/payouts`.
class PromoterPayoutsScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const PromoterPayoutsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PromoterPayoutsScreen> createState() =>
      _PromoterPayoutsScreenState();
}

class _PromoterPayoutsScreenState extends ConsumerState<PromoterPayoutsScreen> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final List<PromoterPayout> _payouts = [];
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

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
        .getPayouts(page: nextPage, limit: _pageSize);

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
        _loadingMore = false;
      }),
      (data) => setState(() {
        if (reset) _payouts.clear();
        _payouts.addAll(data.payouts);
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
        title: l10n.translate('nav_promoter_payouts'),
        showBackButton: !widget.embedded,
        showBell: false,
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _buildBody(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    if (_error != null && _payouts.isEmpty) {
      return PromoterErrorView(
        message: _error!,
        onRetry: () => _load(reset: true),
      );
    }
    if (_payouts.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          PromoterEmptyState(
            icon: Icons.account_balance_outlined,
            title: l10n.translate('promoter_no_payouts'),
            subtitle: l10n.translate('promoter_no_payouts_sub'),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _payouts.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= _payouts.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _row(l10n, _payouts[index]);
      },
    );
  }

  /// [l10n] is threaded in from [_buildBody]: resolving it here instead would
  /// run an InheritedWidget lookup for every row on every scroll frame.
  Widget _row(AppLocalizations l10n, PromoterPayout payout) {
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
                      formatMoney(payout.amount, payout.currency),
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      payout.reference,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PromoterStatusChip.payout(payout.status, l10n),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                payout.phone ?? '-',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(Icons.schedule, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                formatPromoterDate(
                  payout.processedAt ?? payout.createdAt,
                  l10n,
                ),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
              const Spacer(),
              Text(
                l10n
                    .translate('promoter_commissions_n')
                    .replaceAll('%d', '${payout.commissionCount}'),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          // Sandbox/auth rejections are permanent: the server rolls the money
          // back, so the reason is worth showing rather than hiding.
          if (payout.isFailed && payout.failureReason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.errorBorder),
              ),
              child: Text(
                payout.failureReason!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

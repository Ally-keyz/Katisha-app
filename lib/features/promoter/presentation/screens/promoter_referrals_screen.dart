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

/// Referred customers: `GET /promoter/referrals`.
///
/// Phone numbers arrive already masked from the server, so nothing sensitive is
/// rendered here beyond what the promoter is allowed to see.
class PromoterReferralsScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const PromoterReferralsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PromoterReferralsScreen> createState() =>
      _PromoterReferralsScreenState();
}

class _PromoterReferralsScreenState
    extends ConsumerState<PromoterReferralsScreen> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final List<PromoterReferral> _referrals = [];
  PromoterPagination? _pagination;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
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
        .getReferrals(page: nextPage, limit: _pageSize, status: _status);

    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
        _loadingMore = false;
      }),
      (data) => setState(() {
        if (reset) _referrals.clear();
        _referrals.addAll(data.referrals);
        _pagination = data.pagination;
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
        title: l10n.translate('nav_promoter_referrals'),
        showBackButton: !widget.embedded,
        showBell: false,
      ),
      body: Column(
        children: [
          if (_pagination != null) _header(l10n, _pagination!),
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

  Widget _header(AppLocalizations l10n, PromoterPagination pagination) {
    final converted = _referrals.where((r) => r.isConverted).length;
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pagination.total}',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.translate('promoter_referrals_total'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$converted',
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.translate('promoter_converted'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pagination.total == 0
                      ? '0%'
                      : '${(converted * 100 / pagination.total).round()}%',
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.statusPaid,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.translate('promoter_conversion'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusFilter(AppLocalizations l10n) {
    final options = <String?, String>{
      null: l10n.translate('all'),
      'converted': l10n.translate('status_converted'),
      'pending': l10n.translate('status_pending'),
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
    if (_error != null && _referrals.isEmpty) {
      return PromoterErrorView(
        message: _error!,
        onRetry: () => _load(reset: true),
      );
    }
    if (_referrals.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          PromoterEmptyState(
            icon: Icons.people_outline,
            title: l10n.translate('promoter_no_referrals'),
            subtitle: l10n.translate('promoter_no_referrals_sub'),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _referrals.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= _referrals.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _row(l10n, _referrals[index]);
      },
    );
  }

  /// [l10n] is threaded in from [_buildBody]: resolving it here instead would
  /// run an InheritedWidget lookup for every row on every scroll frame.
  Widget _row(AppLocalizations l10n, PromoterReferral referral) {
    final name = referral.customerName ?? l10n.translate('promoter_customer');

    return PromoterCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  referral.customerPhone ?? '-',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPromoterDate(referral.createdAt, l10n),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PromoterStatusChip.referral(referral.status, l10n),
              const SizedBox(height: 4),
              Text(
                formatRwf(referral.lifetimeValue),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

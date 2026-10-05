import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/network/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/promoter_providers.dart';
import '../../data/models/promoter_models.dart';
import '../../data/promoter_repository.dart';
import '../widgets/promoter_ui.dart';
import 'promoter_settings_modal.dart';

const _accentBlue = Color(0xFF3B82F6);
const _primaryBlue = Color(0xFF2563EB);
const _mutedGrey = Color(0xFF9CA3AF);

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
  bool _copied = false;
  StreamSubscription<SocketEvent>? _clickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _clickSub = ref.read(socketServiceProvider).onEvent.listen((event) {
      if (event.name == 'promoter:link-click' && mounted) {
        setState(() {
          if (_stats != null) {
            _stats = PromoterStats(
              earnings: _stats!.earnings,
              referrals: _stats!.referrals,
              thisMonth: _stats!.thisMonth,
              trend: _stats!.trend,
              recentCommissions: _stats!.recentCommissions,
              minPayout: _stats!.minPayout,
              canRequestPayout: _stats!.canRequestPayout,
              linkClicks: _stats!.linkClicks + 1,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final repo = ref.read(promoterRepositoryProvider);
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

  String get _referralLink {
    final code = _profile?.promoterCode;
    return code == null || code.isEmpty
        ? ''
        : 'https://katisha.today/?ref=${Uri.encodeComponent(code)}';
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
      ref.read(promoterDataVersionProvider.notifier).state++;
      _load();
    });
  }

  Future<void> _openSettings() async {
    await showKatishaModal<void>(
      context: context,
      dark: true,
      builder: (_) => const PromoterSettingsModal(),
    );
    ref.read(promoterDataVersionProvider.notifier).state++;
    _load();
  }

  Future<void> _copyLink() async {
    final link = _referralLink;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _copied = true);
    _toast(l10n.translate('promoter_link_copied'));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _share() async {
    final link = _referralLink;
    if (link.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    try {
      await Share.share(
        l10n.translate('promoter_share_text').replaceAll('%s', link),
        subject: l10n.translate('promoter_title'),
      );
    } catch (_) {
      // Platform share unavailable — fall back to copying.
      await _copyLink();
    }
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReferralsSheet(
        repo: ref.read(promoterRepositoryProvider),
        onWithdraw: (_stats?.canRequestPayout ?? false) ? _requestPayout : null,
        withdrawing: _requestingPayout,
      ),
    );
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
    final stats = _stats;
    final status = PromoterStatus.parse(_profile?.status);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Color(0xFF1A1A1A)],
              ),
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_rounded, color: _accentBlue, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        l10n.translate('promoter_title'),
                        style: const TextStyle(
                          color: _accentBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _openSettings,
                        tooltip: l10n.translate('settings'),
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: _mutedGrey,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                if (status == PromoterStatus.pending)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _darkBanner(
                      l10n.translate('promoter_pending_notice'),
                      icon: Icons.info_outline,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                if (status == PromoterStatus.suspended)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _darkBanner(
                      l10n.translate('promoter_suspended_notice'),
                      icon: Icons.error_outline,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _darkBanner(
                      _error,
                      icon: Icons.error_outline,
                      color: const Color(0xFFEF4444),
                    ),
                  ),

                // Center focal numbers
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading && stats == null)
                          _skeletonBox(width: 180, height: 56)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatMoney(stats?.thisMonth.total ?? 0),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w500,
                                  color: _accentBlue,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (_loading && stats == null)
                          _skeletonBox(width: 110, height: 20)
                        else
                          Text(
                            l10n
                                .translate('promoter_link_opens')
                                .replaceAll('%d', '${stats?.linkClicks ?? 0}'),
                            style: const TextStyle(
                              fontSize: 18,
                              color: _mutedGrey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // History handle
                GestureDetector(
                  onTap: _openHistory,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: _mutedGrey,
                          size: 22,
                        ),
                        Text(
                          l10n.translate('promoter_history'),
                          style: const TextStyle(
                            color: _mutedGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _referralLink.isEmpty ? null : _copyLink,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accentBlue,
                              side: const BorderSide(
                                color: _primaryBlue,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              _copied
                                  ? l10n.translate('promoter_copied')
                                  : l10n.translate('promoter_copy_link'),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _referralLink.isEmpty ? null : _share,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              l10n.translate('promoter_share'),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeletonBox({required double width, required double height}) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF111827),
      highlightColor: const Color(0xFF1F2937),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _darkBanner(String message, {required IconData icon, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Referrals history sheet ─────────────────────────────

class _ReferralsSheet extends StatefulWidget {
  final PromoterRepository repo;
  final VoidCallback? onWithdraw;
  final bool withdrawing;

  const _ReferralsSheet({
    required this.repo,
    required this.onWithdraw,
    required this.withdrawing,
  });

  @override
  State<_ReferralsSheet> createState() => _ReferralsSheetState();
}

class _ReferralsSheetState extends State<_ReferralsSheet> {
  List<PromoterReferral>? _referrals;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.repo.getReferrals(page: 1, limit: 50);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (page) => setState(() {
        _referrals = page.referrals;
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3F3F46),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    l10n.translate('promoter_referrals'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onWithdraw != null)
                    TextButton(
                      onPressed: _withdraw,
                      child: Text(
                        l10n.translate('promoter_withdraw'),
                        style: const TextStyle(color: _accentBlue),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: _mutedGrey),
                          ),
                        )
                      : (_referrals == null || _referrals!.isEmpty)
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.people_outline,
                                    color: _mutedGrey,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.translate('promoter_no_referrals'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.translate('promoter_share_hint'),
                                    style: const TextStyle(
                                      color: _mutedGrey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              itemCount: _referrals!.length,
                              separatorBuilder: (_, _) => const Divider(
                                color: Color(0xFF27272A),
                                height: 1,
                              ),
                              itemBuilder: (_, i) {
                                final r = _referrals![i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.customerName ?? r.id,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              formatMoney(r.earned),
                                              style: const TextStyle(
                                                color: _mutedGrey,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              r.createdAt != null
                                                  ? r.createdAt!
                                                      .toLocal()
                                                      .toString()
                                                      .split(' ')
                                                      .first
                                                  : '—',
                                              style: const TextStyle(
                                                color: _mutedGrey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: r.paidOut
                                              ? const Color(0xFF059669)
                                                  .withValues(alpha: 0.2)
                                              : const Color(0xFFF59E0B)
                                                  .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          l10n.translate(
                                            r.paidOut
                                                ? 'status_paid'
                                                : 'status_pending',
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: r.paidOut
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFFFBBF24),
                                          ),
                                        ),
                                      ),
                                      if (!r.paidOut && widget.onWithdraw != null)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: TextButton(
                                            onPressed: _withdraw,
                                            child: Text(
                                              l10n.translate('promoter_withdraw'),
                                              style: const TextStyle(
                                                color: _accentBlue,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _withdraw() {
    Navigator.pop(context);
    widget.onWithdraw?.call();
  }
}

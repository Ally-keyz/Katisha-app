import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/route_model.dart';
import '../../data/booking_repository.dart';

final _bookingRepoProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.read(apiClientProvider));
});

class RouteSearchResultsScreen extends ConsumerStatefulWidget {
  const RouteSearchResultsScreen({super.key});

  @override
  ConsumerState<RouteSearchResultsScreen> createState() =>
      _RouteSearchResultsScreenState();
}

class _RouteSearchResultsScreenState
    extends ConsumerState<RouteSearchResultsScreen> {
  List<RouteModel> _routes = [];
  bool _loading = true;
  String? _error;
  String _origin = '';
  String _destination = '';
  DateTime _selectedDate = DateTime.now();

  BookingRepository get _repo => ref.read(_bookingRepoProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = GoRouterState.of(context).uri.queryParameters;
    final origin = params['origin'] ?? '';
    final destination = params['destination'] ?? '';
    final dateStr = params['date'];

    if (origin.isNotEmpty &&
        destination.isNotEmpty &&
        (origin != _origin || destination != _destination)) {
      _origin = origin;
      _destination = destination;
      if (dateStr != null) {
        _selectedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
      }
      _searchRoutes();
    }
  }

  Future<void> _searchRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.searchRoutes(_origin, _destination);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (routes) => setState(() {
        _routes = routes;
        _loading = false;
      }),
    );
  }

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  void _navigateToBook(RouteModel route) {
    context.push('/book', extra: {
      'route': route,
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.translate('search_routes'),
          style: AppTypography.titleLarge,
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: Column(
        children: [
          _SearchSummaryBar(
            origin: _origin,
            destination: _destination,
            date: _selectedDate,
            formattedDate: _formatDate(_selectedDate),
          ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.translate('loading'),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: _searchRoutes,
      );
    }

    if (_routes.isEmpty) {
      return _EmptyState(
        message: l10n.translate('no_routes_found'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _RouteCard(
        route: _routes[index],
        onBook: () => _navigateToBook(_routes[index]),
        bookLabel: l10n.translate('book_now'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Summary Bar
// ---------------------------------------------------------------------------

class _SearchSummaryBar extends StatelessWidget {
  final String origin;
  final String destination;
  final DateTime date;
  final String formattedDate;

  const _SearchSummaryBar({
    required this.origin,
    required this.destination,
    required this.date,
    required this.formattedDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              origin,
              style: AppTypography.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
          const Icon(Icons.circle, size: 8, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              destination,
              style: AppTypography.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              formattedDate,
              style: AppTypography.labelSmall.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route Card
// ---------------------------------------------------------------------------

class _RouteCard extends StatelessWidget {
  final RouteModel route;
  final VoidCallback onBook;
  final String bookLabel;

  const _RouteCard({
    required this.route,
    required this.onBook,
    required this.bookLabel,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrice = route.effectivePrice ?? route.price;
    final hasDiscount =
        route.effectivePrice != null && route.effectivePrice != route.price;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    route.agency.name,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (route.estimatedDuration != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        route.estimatedDuration!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSub),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    route.origin,
                    style: AppTypography.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
                const Icon(Icons.circle, size: 8, color: AppColors.success),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    route.destination,
                    style: AppTypography.titleMedium,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            if (route.stops.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      route.stops.map((s) => s.name).join(' · '),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              height: 1,
              color: AppColors.border,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '${NumberFormat('#,##0').format(effectivePrice)} RWF',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                if (hasDiscount) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${NumberFormat('#,##0').format(route.price)} RWF',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    textStyle: AppTypography.buttonMedium,
                  ),
                  child: Text(bookLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSub),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error State
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.errorBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSub),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                textStyle: AppTypography.buttonMedium,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/badge_counts.dart';
import '../../../../core/platform/local_ticket_store.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/platform/screen_security.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../my_bookings/data/my_bookings_repository.dart';

final _myBookingsRepoProvider = Provider<MyBookingsRepository>((ref) {
  return MyBookingsRepository(ref.read(apiClientProvider));
});

class TicketViewScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const TicketViewScreen({super.key, required this.bookingId});

  @override
  ConsumerState<TicketViewScreen> createState() => _TicketViewScreenState();
}

class _TicketViewScreenState extends ConsumerState<TicketViewScreen> {
  bool _loading = true;
  String? _error;
  String? _imageUrl;
  String? _localImagePath;
  Map<String, dynamic>? _ticketData;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  @override
  void dispose() {
    super.dispose();
    ScreenSecurity.disable();
  }

  Future<void> _loadTicket() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await ScreenSecurity.enable();

    // 1) Show locally cached ticket immediately (works offline).
    final localStore = ref.read(localTicketStoreProvider);
    final cached = await localStore.getBooking(widget.bookingId);
    final localImage = await localStore.getTicketImagePath(widget.bookingId);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _ticketData = cached;
        _localImagePath = localImage;
        _loading = false;
      });
    }

    // 2) Refresh from the network and update the local cache.
    final repo = ref.read(_myBookingsRepoProvider);
    final result = await repo.viewTicket(widget.bookingId);

    if (!mounted) return;

    result.fold(
      (failure) {
        if (_ticketData == null) {
          setState(() {
            _error = failure.message;
            _loading = false;
          });
        }
      },
      (data) async {
        final ticket = data['ticket'] as Map<String, dynamic>?;
        final booking = data['booking'] as Map<String, dynamic>?;
        final imageUrl = ticket?['imageUrl'] as String?;

        if (booking != null) {
          await localStore.cacheBooking(widget.bookingId, booking);
        }

        if (imageUrl != null && imageUrl.isNotEmpty) {
          // Auto-download the ticket image into app-private storage.
          _downloadPrivateImage(localStore, imageUrl);
        }

        if (!mounted) return;
        setState(() {
          _imageUrl = imageUrl;
          if (booking != null) _ticketData = booking;
          _loading = false;
          _error = null;
        });

        ref.read(badgeCountsProvider.notifier).refresh();
      },
    );
  }

  /// Downloads the ticket image into the app-private folder so it stays
  /// visible offline and never appears in the gallery or public file manager.
  Future<void> _downloadPrivateImage(
    LocalTicketStore localStore,
    String imageUrl,
  ) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.downloadBytes(imageUrl);
      final bytes = response.data;
      if (bytes is Uint8List || bytes is List<int>) {
        final path = await localStore.saveTicketImage(
          widget.bookingId,
          Uint8List.fromList(bytes as List<int>),
        );
        if (path != null && mounted) {
          setState(() => _localImagePath = path);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: Column(
        children: [
          _buildTopBar(l10n),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────

  Widget _buildTopBar(AppLocalizations l10n) {
    return SafeArea(
      bottom: false,
      child: Container(
        color: AppColors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 40,
                height: 40,
              ),
              icon: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: AppColors.textSub,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('my_ticket'),
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    l10n.translate('digital_travel_pass'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) return _buildLoadingState();

    if (_error != null) return _buildErrorState(l10n);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        children: [
          _buildTicketImage(),
          const SizedBox(height: AppSpacing.md),
          if (_ticketData != null) ...[
            _buildStatusBadges(),
            const SizedBox(height: AppSpacing.md),
            _buildTripSummaryCard(l10n),
            const SizedBox(height: AppSpacing.md),
            _buildReferenceSection(l10n),
          ],
        ],
      ),
    );
  }

  // ── Loading State ─────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context).translate('loading'),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error State ───────────────────────────────

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(color: AppColors.errorBorder),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSub,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _loadTicket,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ticket Image ──────────────────────────────

  Widget _buildTicketImage() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withAlpha(12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildTicketImageContent(),
    );
  }

  Widget _buildTicketImageContent() {
    // Prefer the locally stored (private) image so the ticket works offline
    // and the image never has to be re-fetched from the network.
    final localPath = _localImagePath;
    final remote = _imageUrl;

    // Decode the ticket at display resolution so a full-page PNG ticket never
    // occupies many MB of decoded memory.
    final decodeWidth =
        (MediaQuery.of(context).size.width *
                MediaQuery.of(context).devicePixelRatio)
            .round();

    if (localPath != null && localPath.isNotEmpty) {
      return Image.file(
        File(localPath),
        width: double.infinity,
        fit: BoxFit.fitWidth,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => _buildQrFallback(),
      );
    }

    if (remote != null && remote.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: remote,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        memCacheWidth: decodeWidth,
        placeholder: (_, __) => const SizedBox(
          height: 200,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _buildQrFallback(),
      );
    }

    return _buildQrFallback();
  }

  Widget _buildQrFallback() {
    final referenceCode =
        _ticketData?['referenceCode'] ?? widget.bookingId;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border),
            ),
            child: QrImageView(
              data: referenceCode,
              version: QrVersions.auto,
              size: 160,
              backgroundColor: AppColors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            referenceCode,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Badges ─────────────────────────────

  Widget _buildStatusBadges() {
    final status = (_ticketData?['status'] as String?) ?? '';
    final paymentStatus =
        (_ticketData?['paymentStatus'] as String?) ?? '';

    return Row(
      children: [
        if (status.isNotEmpty) _buildStatusBadge(status),
        if (status.isNotEmpty && paymentStatus.isNotEmpty)
          const SizedBox(width: AppSpacing.sm),
        if (paymentStatus.isNotEmpty)
          _buildPaymentBadge(paymentStatus),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isConfirmed = status.toLowerCase() == 'confirmed';
    final bgColor =
        isConfirmed ? AppColors.successBg : AppColors.primaryLight;
    final textColor =
        isConfirmed ? AppColors.statusCompleted : AppColors.primary;
    final borderColor = textColor.withAlpha(60);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBadge(String paymentStatus) {
    final isPaid = paymentStatus.toLowerCase() == 'paid';
    final bgColor =
        isPaid ? AppColors.successBg : AppColors.errorBg;
    final textColor =
        isPaid ? AppColors.statusPaid : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaid
                ? Icons.payments_rounded
                : Icons.payment_rounded,
            size: 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            paymentStatus.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ── Trip Summary Card ─────────────────────────

  Widget _buildTripSummaryCard(AppLocalizations l10n) {
    final data = _ticketData!;
    final origin = data['origin'] as String? ?? '\u2014';
    final destination = data['destination'] as String? ?? '\u2014';
    final agencyName =
        (data['agency'] as Map<String, dynamic>?)?['name'] as String? ??
            '\u2014';
    final travelDate = data['travelDate'] != null
        ? DateTime.tryParse(data['travelDate'])
        : null;
    final dateStr = travelDate != null
        ? DateFormat('dd MMM yyyy').format(travelDate)
        : '\u2014';
    final time = data['travelTime'] as String? ?? '\u2014';
    final seats = '${data['seats'] ?? '\u2014'}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          // Route header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  color: AppColors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$origin \u2192 $destination',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      agencyName,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSub,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),

          // Details grid
          Row(
            children: [
              Expanded(
                child: _buildDetailColumn(
                  l10n.translate('date'),
                  dateStr,
                ),
              ),
              Expanded(
                child: _buildDetailColumn(
                  l10n.translate('time'),
                  time,
                ),
              ),
              Expanded(
                child: _buildDetailColumn(
                  l10n.translate('seats'),
                  seats,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailColumn(String label, String value) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Reference Code ────────────────────────────

  Widget _buildReferenceSection(AppLocalizations l10n) {
    final referenceCode =
        _ticketData?['referenceCode'] ?? widget.bookingId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${l10n.translate('reference')}: ',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          Text(
            referenceCode,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.text,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

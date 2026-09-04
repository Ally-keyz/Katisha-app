import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/platform/sound_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/booking_repository.dart';
import '../../../../shared/models/booking_model.dart';

final _bookingRepoProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.read(apiClientProvider));
});

class PaymentWaitingScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String referenceCode;
  final String paymentMethod;
  final String phone;
  final int totalAmount;

  const PaymentWaitingScreen({
    super.key,
    required this.bookingId,
    required this.referenceCode,
    required this.paymentMethod,
    required this.phone,
    required this.totalAmount,
  });

  @override
  ConsumerState<PaymentWaitingScreen> createState() =>
      _PaymentWaitingScreenState();
}

class _PaymentWaitingScreenState extends ConsumerState<PaymentWaitingScreen> {
  // Matches the web frontend behaviour.
  static const _pollInterval = Duration(seconds: 5);
  static const _timeout = Duration(minutes: 5);

  Timer? _pollTimer;
  Timer? _timeoutTimer;
  StreamSubscription<Map<String, dynamic>>? _paymentSub;
  bool _navigated = false;
  bool _cancelling = false;
  String? _error;

  BookingRepository get _repo => ref.read(_bookingRepoProvider);
  SoundService get _soundService => ref.read(soundServiceProvider);

  @override
  void initState() {
    super.initState();
    _startPolling();
    _startTimeout();
    _listenForPayment();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _paymentSub?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _checkPaymentStatus();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkPaymentStatus());
  }

  void _startTimeout() {
    _timeoutTimer = Timer(_timeout, () async {
      if (_navigated) return;
      // Abandon the unpaid booking so its seats are released, exactly like
      // the web's 5-minute abandon timeout.
      await _repo.abandonBooking(widget.bookingId);
      if (!mounted || _navigated) return;
      _navigated = true;
      context.go('/home');
    });
  }

  /// Listen for the instant payment confirmation pushed over the socket,
  /// mirroring the web frontend's socket handling.
  void _listenForPayment() {
    try {
      _paymentSub = ref.read(socketServiceProvider).onPaymentConfirmed.listen(
        (data) {
          if (mounted) _onPaymentConfirmed();
        },
      );
    } catch (_) {
      // Socket not available — fall back to polling only.
    }
  }

  /// Handles a confirmed/already-paid booking: play the success sound,
  /// schedule departure alerts, record + surface notifications, and redirect
  /// to the ticket.
  void _onPaymentConfirmed([Booking? maybeBooking]) {
    if (_navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _paymentSub?.cancel();

    _soundService.vibrate();

    if (maybeBooking != null) {
      _scheduleDepartureAlerts(maybeBooking);
    } else {
      _scheduleDepartureAlertsForReference();
    }

    ref.read(localNotificationStoreProvider).add(
          title: 'Payment Confirmed!',
          message:
              'Your booking ${widget.referenceCode} has been confirmed.',
          type: 'payment',
          entityId: widget.bookingId,
        );
    ref.read(notificationServiceProvider).showImmediateAlert(
          title: 'Payment Confirmed!',
          body: 'Your booking ${widget.referenceCode} has been confirmed.',
          type: 'payment',
          entityId: widget.bookingId,
        );

    if (!mounted) return;
    context.go('/ticket/${widget.bookingId}');
  }

  Future<void> _checkPaymentStatus() async {
    if (_navigated) return;
    final result = await _repo.getBooking(widget.bookingId);
    if (!mounted || _navigated) return;

    result.fold(
      (failure) => setState(() => _error = failure.message),
      (booking) {
        if (booking.paymentStatus == 'paid') {
          _onPaymentConfirmed(booking);
        } else if (booking.paymentStatus == 'failed' ||
            booking.status == 'cancelled') {
          if (_navigated) return;
          _navigated = true;
          _pollTimer?.cancel();
          _timeoutTimer?.cancel();
          _paymentSub?.cancel();
          context.go('/home');
        }
      },
    );
  }

  void _scheduleDepartureAlertsForReference() {
    // Without the full booking object we cannot derive the departure time,
    // so fall back to a best-effort fetch.
    _repo.getBooking(widget.bookingId).then((result) {
      result.fold((_) {}, (booking) => _scheduleDepartureAlerts(booking));
    });
  }

  void _scheduleDepartureAlerts(Booking booking) {
    final routeName = '${booking.origin} → ${booking.destination}';

    DateTime? departure;
    final travelDate = booking.travelDate;
    if (travelDate != null && booking.travelTime != null) {
      final parts = booking.travelTime!.split(':');
      if (parts.length >= 2) {
        departure = DateTime(
          travelDate.year,
          travelDate.month,
          travelDate.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    if (booking.id.isEmpty || departure == null) return;
    if (departure.isBefore(DateTime.now())) return;

    ref.read(notificationServiceProvider).scheduleJourneyAlerts(
          bookingId: booking.id,
          routeName: routeName,
          departureTime: departure,
        );
  }

  Future<void> _cancelPayment() async {
    if (_cancelling) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await _repo.abandonBooking(widget.bookingId);
    } catch (_) {
      // Abandon already happened server-side is fine.
    }
    if (!mounted || _navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _paymentSub?.cancel();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_navigated) _cancelPayment();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Lottie payment animation (same asset as web) ──
                    Lottie.asset(
                      'assets/lottie/payment.json',
                      width: 190,
                      height: 190,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // ── Title ─────────────────────
                    Text(
                      l10n.translate('payment_prompt_sent'),
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),

                    // ── Description ───────────────
                    Text(
                      l10n.translate('payment_prompt_desc'),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSub,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Reference code ────────────
                    Text(
                      '${l10n.translate('ref_code')}: '
                      '${widget.referenceCode}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    // ── Amount ────────────────────
                    Text(
                      '${l10n.translate('amount')}: '
                      '${_formatAmount(widget.totalAmount)} '
                      '${l10n.translate('currency')}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Error message ─────────────
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          color: AppColors.errorBg,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          border: Border.all(color: AppColors.errorBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── Cancel button (green CTA, like web) ──
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _cancelling ? null : _cancelPayment,
                        icon: _cancelling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _greenInk,
                                ),
                              )
                            : const Icon(Icons.close, size: 16),
                        label: Text(
                          _cancelling
                              ? l10n.translate('payment_cancelling')
                              : l10n.translate('payment_cancel'),
                          style: AppTypography.buttonMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _greenCta,
                          foregroundColor: _greenInk,
                          disabledBackgroundColor: _greenCta,
                          disabledForegroundColor: _greenInk,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatAmount(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static const Color _greenCta = Color(0xFF74E24C);
  static const Color _greenInk = Color(0xFF0B3D0B);
}

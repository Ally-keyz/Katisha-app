import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/session.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/media_url.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../shared/models/booking_model.dart';
import '../../data/agent_repository.dart';

final _agentRepoProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(ref.read(apiClientProvider));
});

final _dateFormat = DateFormat('EEE, d MMM yyyy');
final _amountFormat = NumberFormat.decimalPattern();

/// Field-agent portal: assigned-route bookings, the "I have seen it" step, and
/// the mandatory photo of the physical ticket that makes a booking ready.
///
/// The screen deliberately mirrors the passenger side of the app: the same
/// [KatishaAppBar], typography, spacing and card vocabulary as the
/// notifications list. Cards stay collapsed to a single summary row and expand
/// in place when tapped, so the list reads calmly even with many bookings.
class AgentBookingsScreen extends ConsumerStatefulWidget {
  const AgentBookingsScreen({super.key});

  @override
  ConsumerState<AgentBookingsScreen> createState() =>
      _AgentBookingsScreenState();
}

class _AgentBookingsScreenState extends ConsumerState<AgentBookingsScreen> {
  final _picker = ImagePicker();
  final Set<String> _busy = <String>{};
  final Set<String> _expanded = <String>{};

  List<Booking> _bookings = <Booking>[];
  bool _loading = true;
  bool _todayOnly = false;
  bool _attentionOnly = false;
  String? _error;
  Timer? _reloadDebounce;
  StreamSubscription<SocketEvent>? _socketSub;

  AgentRepository get _repo => ref.read(_agentRepoProvider);

  /// The `/uploads` route requires a bearer token (or a dashboard referer), so
  /// the proof image must carry the agent's token when loaded in the app.
  Map<String, String>? get _imageHeaders {
    final token = ref.read(apiClientProvider).accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  bool _hasProof(Booking booking) =>
      booking.ticketProofImage != null && booking.ticketProofImage!.isNotEmpty;

  /// A booking needs the agent to act when it is paid but the physical ticket
  /// proof has not been captured yet. Unpaid bookings are waiting on the
  /// passenger and cancelled/rejected rows never reach this list.
  bool _needsAttention(Booking booking) =>
      booking.paymentStatus == 'paid' && !_hasProof(booking);

  int get _attentionCount => _bookings.where(_needsAttention).length;

  List<Booking> get _visibleBookings => _attentionOnly
      ? _bookings.where(_needsAttention).toList(growable: false)
      : _bookings;

  @override
  void initState() {
    super.initState();
    _load();
    _listenForUpdates();

    // Safety net for accounts that signed in before permission was granted:
    // without POST_NOTIFICATIONS (Android 13+) every alert is silently dropped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(notificationServiceProvider).requestPermission(),
      );
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }

  void _listenForUpdates() {
    final socket = ref.read(socketServiceProvider);
    _socketSub = socket.onEvent.listen((event) {
      const watched = {
        'new_booking',
        'booking_confirmed',
        'booking_seen',
        'booking_ready',
        'booking_issued',
        'booking_status',
        'booking_rejected',
        'booking_cancelled',
        'ticket_uploaded',
      };
      if (!watched.contains(event.name)) return;
      _scheduleReload();
    });
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await _repo.getAgentBookings(
      page: 1,
      limit: 100,
      today: _todayOnly,
    );
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (response) {
        final active = response.bookings.where(_isRelevant).toList()
          ..sort(_compareBookings);
        setState(() {
          _bookings = active;
          _loading = false;
          _error = null;
        });
      },
    );
  }

  bool _isRelevant(Booking booking) {
    if (booking.status == 'cancelled' || booking.status == 'rejected') {
      return false;
    }
    final date = booking.travelDate;
    if (date == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(today);
  }

  int _compareBookings(Booking a, Booking b) {
    // Anything waiting on the agent floats to the top of the list.
    final aAttention = _needsAttention(a) ? 0 : 1;
    final bAttention = _needsAttention(b) ? 0 : 1;
    if (aAttention != bAttention) return aAttention.compareTo(bAttention);

    final da = a.travelDate ?? DateTime(2100);
    final db = b.travelDate ?? DateTime(2100);
    final byDate = da.compareTo(db);
    if (byDate != 0) return byDate;
    return (a.travelTime ?? '').compareTo(b.travelTime ?? '');
  }

  Future<void> _markSeen(Booking booking) async {
    if (_busy.contains(booking.id)) return;
    setState(() => _busy.add(booking.id));
    final result = await _repo.markSeen(booking.id);
    if (!mounted) return;
    setState(() => _busy.remove(booking.id));
    result.fold(
      (failure) => _showSnack(failure.message, isError: true),
      (updated) {
        _replaceBooking(updated);
        _showSnack('Booking confirmed. Capture the ticket photo next.');
      },
    );
  }

  Future<void> _captureAndMarkReady(Booking booking) async {
    if (_busy.contains(booking.id)) return;

    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 70,
        maxWidth: 1600,
      );
    } catch (_) {
      if (mounted) {
        _showSnack(
          'Could not open the camera. Check the camera permission and try again.',
          isError: true,
        );
      }
      return;
    }
    if (shot == null) return;

    File photo = File(shot.path);
    while (mounted) {
      final choice = await _confirmPhoto(photo);
      if (!mounted) return;
      if (choice == 'retake') {
        await _deleteQuietly(photo);
        try {
          final retake = await _picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.rear,
            imageQuality: 70,
            maxWidth: 1600,
          );
          if (retake == null) return;
          photo = File(retake.path);
          continue;
        } catch (_) {
          _showSnack('Could not reopen the camera.', isError: true);
          return;
        }
      }
      if (choice != 'use') {
        await _deleteQuietly(photo);
        return;
      }
      break;
    }

    setState(() => _busy.add(booking.id));
    final result = await _repo.markReady(booking.id, photo);
    await _deleteQuietly(photo);
    if (!mounted) return;
    setState(() => _busy.remove(booking.id));
    result.fold(
      (failure) => _showSnack(failure.message, isError: true),
      (updated) {
        _replaceBooking(updated);
        _showSnack('Ticket marked ready. The passenger has been notified.');
      },
    );
  }

  Future<String?> _confirmPhoto(File photo) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final width = MediaQuery.of(ctx).size.width;
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: Text('Ticket photo', style: AppTypography.titleMedium),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Image.file(
                    photo,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: (width * 1.2).round(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Make sure the ticket number and passenger name are readable. '
                  'This photo is the proof sent to the passenger.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'retake'),
              child: Text(
                'Retake',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'use'),
              style: _primaryButtonStyle(),
              child: const Text('Use photo'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _replaceBooking(Booking updated) {
    final index = _bookings.indexWhere((b) => b.id == updated.id);
    if (index < 0) {
      _load(silent: true);
      return;
    }
    setState(() {
      _bookings[index] = updated;
      _bookings.sort(_compareBookings);
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : AppColors.text,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text('Log out?', style: AppTypography.titleMedium),
        content: Text(
          'You will need to sign in again to see your assigned bookings.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSub,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: AppTypography.buttonMedium,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: KatishaAppBar(
        title: 'Agent Portal',
        showBell: false,
        extraActions: [
          _buildAttentionAction(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(),
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.textSub,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSub),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Log out',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  // ── App bar attention flag ────────────────────────────────────────────────

  Widget _buildAttentionAction() {
    final count = _attentionCount;
    final active = _attentionOnly;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: count > 0
              ? '$count booking${count == 1 ? '' : 's'} need attention'
              : 'Nothing needs attention',
          onPressed: count == 0 && !active
              ? null
              : () {
                  setState(() => _attentionOnly = !_attentionOnly);
                },
          icon: Icon(
            active ? Icons.flag_rounded : Icons.flag_outlined,
            color: count > 0
                ? AppColors.error
                : active
                    ? AppColors.primary
                    : AppColors.textMuted,
          ),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading && _bookings.isEmpty) {
      return _buildSkeleton();
    }

    if (_error != null && _bookings.isEmpty) {
      return _buildErrorState();
    }

    final bookings = _visibleBookings;

    return Column(
      children: [
        _buildFilters(),
        if (_attentionOnly && _attentionCount > 0) _buildAttentionBanner(),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _load(silent: true),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: bookings.isEmpty ? 1 : bookings.length,
              itemBuilder: (context, index) {
                if (bookings.isEmpty) return _buildEmptyState();
                return _buildBookingCard(bookings[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          _filterChip('All bookings', !_todayOnly, () {
            if (_todayOnly) {
              setState(() => _todayOnly = false);
              _load();
            }
          }),
          const SizedBox(width: AppSpacing.sm),
          _filterChip("Today's trips", _todayOnly, () {
            if (!_todayOnly) {
              setState(() => _todayOnly = true);
              _load();
            }
          }),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: selected ? AppColors.white : AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildAttentionBanner() {
    final count = _attentionCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$count booking${count == 1 ? '' : 's'} need your attention',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _attentionOnly = false),
            child: Text(
              'Show all',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
      itemCount: 5,
      itemBuilder: (_, _) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: 150,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 11,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.border.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
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

  Widget _buildEmptyState() {
    final attentionMode = _attentionOnly;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: attentionMode ? AppColors.errorBg : AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              attentionMode
                  ? Icons.check_rounded
                  : Icons.confirmation_num_outlined,
              size: 40,
              color: attentionMode ? AppColors.error : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            attentionMode ? 'You are all caught up' : 'No bookings right now',
            style: AppTypography.titleMedium.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            attentionMode
                ? 'Every paid booking already has its physical ticket photo.'
                : 'New bookings for your assigned routes will appear here automatically.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
                Icons.cloud_off_rounded,
                size: 36,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Could not load your bookings',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _load(),
              style: _primaryButtonStyle(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Booking card ──────────────────────────────────────────────────────────

  Widget _buildBookingCard(Booking booking) {
    final expanded = _expanded.contains(booking.id);
    final needsAttention = _needsAttention(booking);
    final date = booking.travelDate;
    final dateLabel = date == null ? '—' : _dateFormat.format(date);
    final time = booking.travelTime;
    final passenger = booking.passengerDetails.isNotEmpty
        ? booking.passengerDetails.first
        : null;
    final passengerName = passenger?.name.isNotEmpty == true
        ? passenger!.name
        : 'Passenger';

    final subtitle = [
      passengerName,
      '$dateLabel${time != null && time.isNotEmpty ? ' · $time' : ''}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: needsAttention ? AppColors.errorBorder : AppColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.primary.withValues(alpha: 0.04),
          highlightColor: AppColors.primary.withValues(alpha: 0.02),
          onTap: () {
            setState(() {
              if (expanded) {
                _expanded.remove(booking.id);
              } else {
                _expanded.add(booking.id);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bookingAvatar(booking),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${booking.origin} → ${booking.destination}',
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSub,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _statusPill(booking),
                        const SizedBox(height: 4),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? _buildExpandedDetails(
                          booking,
                          passenger: passenger,
                          dateLabel: dateLabel,
                          time: time,
                          busy: _busy.contains(booking.id),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingAvatar(Booking booking) {
    final ready = _hasProof(booking);
    final unpaid = booking.paymentStatus != 'paid';
    final (Color bg, Color fg, IconData icon) = ready
        ? (const Color(0xFFDCFCE7), const Color(0xFF15803D),
            Icons.check_circle_outline_rounded)
        : unpaid
            ? (AppColors.surfaceVariant, AppColors.textMuted,
                Icons.hourglass_bottom_rounded)
            : booking.agentSeen
                ? (AppColors.warningBg, AppColors.warning,
                    Icons.photo_camera_outlined)
                : (AppColors.primaryLight, AppColors.primary,
                    Icons.confirmation_number_outlined);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: fg),
    );
  }

  Widget _statusPill(Booking booking) {
    final (String label, Color fg, Color bg) = _hasProof(booking)
        ? ('Ready', const Color(0xFF15803D), const Color(0xFFDCFCE7))
        : booking.paymentStatus != 'paid'
            ? ('Unpaid', AppColors.textSub, AppColors.surfaceVariant)
            : ('Needs action', AppColors.error, AppColors.errorBg);

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

  Widget _buildExpandedDetails(
    Booking booking, {
    required PassengerDetail? passenger,
    required String dateLabel,
    required String? time,
    required bool busy,
  }) {
    final phone = passenger?.phone ?? booking.phone ?? booking.contactPhone;
    final paid = booking.paymentStatus == 'paid';
    final ready = _hasProof(booking);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          _detailRow(
            Icons.confirmation_number_outlined,
            'Reference',
            booking.referenceCode,
            mono: true,
          ),
          if (passenger != null && passenger.name.isNotEmpty)
            _detailRow(Icons.person_outline_rounded, 'Passenger', passenger.name),
          if (phone != null && phone.isNotEmpty)
            _detailRow(Icons.call_outlined, 'Phone', phone),
          _detailRow(
            Icons.event_outlined,
            'Travel',
            '$dateLabel${time != null && time.isNotEmpty ? ' · $time' : ''}',
          ),
          _detailRow(
            Icons.event_seat_outlined,
            'Seats',
            '${booking.seats} seat${booking.seats == 1 ? '' : 's'}'
            '${booking.seatNumbers.isNotEmpty ? ' · ${booking.seatNumbers.join(', ')}' : ''}',
          ),
          if (booking.pickupPoint != null && booking.pickupPoint!.isNotEmpty)
            _detailRow(
              Icons.location_on_outlined,
              'Pickup',
              booking.pickupPoint!,
            ),
          if (booking.totalAmount > 0)
            _detailRow(
              Icons.payments_outlined,
              'Total',
              '${_amountFormat.format(booking.totalAmount)} RWF',
            ),
          _detailRow(
            Icons.verified_outlined,
            'Payment',
            paid ? 'Paid' : 'Awaiting payment',
            valueColor: paid ? const Color(0xFF15803D) : AppColors.warning,
          ),
          if (ready) ...[
            const SizedBox(height: 6),
            _buildProofRow(booking),
          ],
          const SizedBox(height: 12),
          _buildActions(
            booking,
            busy: busy,
            paid: paid,
            ready: ready,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall.copyWith(
                color: valueColor ?? AppColors.text,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
                letterSpacing: mono ? 0.3 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofRow(Booking booking) {
    final url = resolveMediaUrl(booking.ticketProofImage);
    return GestureDetector(
      onTap: () => _showProof(booking),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: url == null
                  ? Container(
                      width: 44,
                      height: 44,
                      color: AppColors.primaryLight,
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      httpHeaders: _imageHeaders,
                      placeholder: (_, _) => Container(
                        width: 44,
                        height: 44,
                        color: AppColors.surfaceVariant,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 44,
                        height: 44,
                        color: AppColors.primaryLight,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ticket photo attached',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Tap to inspect the proof',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    Booking booking, {
    required bool busy,
    required bool paid,
    required bool ready,
  }) {
    if (busy) {
      return const SizedBox(
        height: 46,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (!paid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for the passenger’s payment',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!booking.agentSeen) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _markSeen(booking),
          style: _primaryButtonStyle(),
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: const Text('Confirm I have seen this booking'),
        ),
      );
    }

    if (!ready) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _captureAndMarkReady(booking),
          style: _primaryButtonStyle(),
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: const Text('Mark ready & photograph ticket'),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showProof(booking),
            style: _outlineButtonStyle(color: AppColors.primary),
            icon: const Icon(Icons.photo_outlined, size: 17),
            label: const Text('View proof'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _captureAndMarkReady(booking),
            style: _outlineButtonStyle(color: AppColors.textSub),
            icon: const Icon(Icons.camera_alt_outlined, size: 17),
            label: const Text('Replace photo'),
          ),
        ),
      ],
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      minimumSize: const Size.fromHeight(46),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: AppTypography.buttonMedium,
    );
  }

  ButtonStyle _outlineButtonStyle({required Color color}) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: const BorderSide(color: AppColors.border),
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: AppTypography.buttonSmall.copyWith(color: color),
    );
  }

  void _showProof(Booking booking) {
    final url = resolveMediaUrl(booking.ticketProofImage);
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.white,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ticket proof · ${booking.referenceCode}',
                      style: AppTypography.titleSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppSpacing.radiusXl),
                ),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    memCacheWidth: 1600,
                    httpHeaders: _imageHeaders,
                    placeholder: (_, _) => const SizedBox(
                      height: 260,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => const SizedBox(
                      height: 260,
                      child: Center(
                        child: Text('Could not load the photo'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

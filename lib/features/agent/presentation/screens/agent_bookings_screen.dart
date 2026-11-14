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
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/booking_model.dart';
import '../../data/agent_repository.dart';

final _agentRepoProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(ref.read(apiClientProvider));
});

final _dateFormat = DateFormat('EEE, d MMM yyyy');

/// Field-agent portal: assigned-route bookings, the "I have seen it" step, and
/// the mandatory photo of the physical ticket that makes a booking ready.
class AgentBookingsScreen extends ConsumerStatefulWidget {
  const AgentBookingsScreen({super.key});

  @override
  ConsumerState<AgentBookingsScreen> createState() =>
      _AgentBookingsScreenState();
}

class _AgentBookingsScreenState extends ConsumerState<AgentBookingsScreen> {
  final _picker = ImagePicker();
  final Set<String> _busy = <String>{};

  List<Booking> _bookings = <Booking>[];
  bool _loading = true;
  bool _todayOnly = false;
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

  @override
  void initState() {
    super.initState();
    _load();
    _listenForUpdates();
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
      (updated) => _replaceBooking(updated),
    );
  }

  Future<void> _captureAndMarkReady(Booking booking) async {
    if (_busy.contains(booking.id)) return;

    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 72,
        maxWidth: 1800,
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
            imageQuality: 72,
            maxWidth: 1800,
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: const Text('Ticket photo'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
              child: const Text('Retake'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'use'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
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
    setState(() => _bookings[index] = updated);
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
        ),
      );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to see your assigned bookings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
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
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agent Portal', style: AppTypography.titleLarge),
            if (session != null)
              Text(
                session.name.isNotEmpty ? session.name : session.username,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSub),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSub),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                _filterChip('All bookings', !_todayOnly, () {
                  setState(() => _todayOnly = false);
                  _load();
                }),
                const SizedBox(width: AppSpacing.sm),
                _filterChip("Today's trips", _todayOnly, () {
                  setState(() => _todayOnly = true);
                  _load();
                }),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: selected ? Colors.white : AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _bookings.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary,
        ),
      );
    }

    if (_error != null && _bookings.isEmpty) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(silent: true),
      child: _bookings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [_buildEmptyState()],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              itemCount: _bookings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildSummary();
                final booking = _bookings[index - 1];
                return _buildBookingCard(booking);
              },
            ),
    );
  }

  Widget _buildSummary() {
    final today = DateTime.now();
    final todayCount = _bookings.where((b) {
      final d = b.travelDate;
      return d != null &&
          d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    }).length;
    final seenCount = _bookings.where((b) => b.agentSeen).length;
    final readyCount = _bookings.where((b) => b.ticketProofImage != null).length;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _summaryMetric('Today', '$todayCount'),
          _summaryDivider(),
          _summaryMetric('Seen', '$seenCount'),
          _summaryDivider(),
          _summaryMetric('Ready', '$readyCount'),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryDivider() {
    return Container(width: 1, height: 26, color: AppColors.border);
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 80),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: const Icon(
            Icons.event_available_rounded,
            size: 34,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('No bookings right now', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'New bookings for your assigned routes will appear here automatically.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSub,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => _load(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Booking booking) {
    final busy = _busy.contains(booking.id);
    final paid = booking.paymentStatus == 'paid';
    final ready = booking.ticketProofImage != null &&
        booking.ticketProofImage!.isNotEmpty;
    final date = booking.travelDate;
    final dateLabel = date == null ? '—' : _dateFormat.format(date);
    final isToday = date != null && _isSameDay(date, DateTime.now());
    final passenger = booking.passengerDetails.isNotEmpty
        ? booking.passengerDetails.first
        : null;
    final phone = passenger?.phone ?? booking.phone ?? booking.contactPhone;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${booking.origin} → ${booking.destination}',
                        style: AppTypography.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        booking.referenceCode,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                          fontFamily: 'monospace',
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _statusPill(booking),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _meta(
                  Icons.person_outline_rounded,
                  passenger?.name.isNotEmpty == true
                      ? passenger!.name
                      : 'Passenger',
                ),
                if (phone != null && phone.isNotEmpty)
                  _meta(Icons.call_outlined, phone),
                _meta(
                  Icons.event_seat_outlined,
                  '${booking.seats} seat${booking.seats == 1 ? '' : 's'}'
                  '${booking.seatNumbers.isNotEmpty ? ' · ${booking.seatNumbers.join(', ')}' : ''}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 6,
              children: [
                _meta(
                  isToday
                      ? Icons.today_rounded
                      : Icons.calendar_today_outlined,
                  '$dateLabel${booking.travelTime != null ? ' · ${booking.travelTime}' : ''}',
                  emphasize: isToday,
                ),
                if (booking.pickupPoint != null &&
                    booking.pickupPoint!.isNotEmpty)
                  _meta(
                    Icons.location_on_outlined,
                    booking.pickupPoint!,
                  ),
              ],
            ),
            if (booking.agentSeen) ...[
              const SizedBox(height: AppSpacing.sm),
              _inlineFlag(
                icon: Icons.visibility_rounded,
                label: 'Seen by agent',
                color: const Color(0xFF15803D),
                background: const Color(0xFFDCFCE7),
              ),
            ],
            if (ready) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildProofRow(booking),
            ],
            const SizedBox(height: AppSpacing.md),
            _buildActions(booking, busy: busy, paid: paid, ready: ready),
          ],
        ),
      ),
    );
  }

  Widget _buildProofRow(Booking booking) {
    final url = resolveMediaUrl(booking.ticketProofImage);
    return GestureDetector(
      onTap: () => _showProof(booking),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
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
                      width: 42,
                      height: 42,
                      color: AppColors.primaryLight,
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      httpHeaders: _imageHeaders,
                      placeholder: (_, __) => Container(
                        width: 42,
                        height: 42,
                        color: AppColors.surfaceVariant,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 42,
                        height: 42,
                        color: AppColors.primaryLight,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ticket photo attached',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Tap to inspect the proof',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSub,
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
        height: 40,
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
      return Row(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            'Waiting for the passenger’s payment',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      );
    }

    if (!booking.agentSeen) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _markSeen(booking),
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: const Text('Confirm I have seen this booking'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
      );
    }

    if (!ready) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _captureAndMarkReady(booking),
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: const Text('Mark ready & photograph ticket'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF15803D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showProof(booking),
            icon: const Icon(Icons.photo_outlined, size: 17),
            label: const Text('View proof'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              textStyle: AppTypography.buttonSmall.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _captureAndMarkReady(booking),
            icon: const Icon(Icons.camera_alt_outlined, size: 17),
            label: const Text('Replace photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSub,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              textStyle: AppTypography.buttonSmall.copyWith(
                color: AppColors.textSub,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showProof(Booking booking) {
    final url = resolveMediaUrl(booking.ticketProofImage);
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
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
                    placeholder: (_, __) => const SizedBox(
                      height: 260,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox(
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

  Widget _statusPill(Booking booking) {
    final ready = booking.ticketProofImage != null &&
        booking.ticketProofImage!.isNotEmpty;
    final (String label, Color fg, Color bg) = ready
        ? ('Ready', const Color(0xFF15803D), const Color(0xFFDCFCE7))
        : booking.agentSeen
            ? ('Seen', AppColors.primary, AppColors.primaryLight)
            : booking.paymentStatus == 'paid'
                ? ('New', const Color(0xFFB45309), const Color(0xFFFEF3C7))
                : ('Unpaid', AppColors.textSub, AppColors.surfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

  Widget _meta(IconData icon, String text, {bool emphasize = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: emphasize ? AppColors.primary : AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.bodySmall.copyWith(
            color: emphasize ? AppColors.primary : AppColors.textSub,
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _inlineFlag({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

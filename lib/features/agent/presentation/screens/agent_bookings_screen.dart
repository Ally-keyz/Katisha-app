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
import 'agent_settings_screen.dart';

final _agentRepoProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(ref.read(apiClientProvider));
});

final _dateFormat = DateFormat('EEE, d MMM yyyy');
final _numericDateFormat = DateFormat('dd/MM/yyyy');
final _shortDateFormat = DateFormat('d MMM');
final _amountFormat = NumberFormat.decimalPattern();
final _whitespace = RegExp(r'\s+');

// ── Local design tokens ─────────────────────────────────────────────────────
// Neutral, borderless surfaces. Structure comes from tone and spacing, not
// outlines. Status is carried by a tinted pill rather than a fully coloured
// card, so a long list stays calm and still scans quickly.
const Color _kGray = Color(0xFFF3F4F6);
const Color _kGrayStrong = Color(0xFFE5E7EB);

const Color _kRed = Color(0xFFC62828);
const Color _kRedCard = Color(0xFFFDECEC); // red version of the gray
const Color _kRedPill = Color(0xFFF9D2D2);
const Color _kOrange = Color(0xFFC2570C);
const Color _kOrangeCard = Color(0xFFFFF1E2); // orange version of the gray
const Color _kOrangePill = Color(0xFFFFDDB8);
const Color _kTeal = Color(0xFF19D3B5);
const Color _kGreen = Color(0xFF15803D);
const Color _kGreenBg = Color(0xFFE6F6EC);
const Color _kSlate = Color(0xFF475569);

const double _kCardRadius = 18;
const double _kChipRadius = 14; // "rounded-xl"

/// Card + pill colours per booking state.
///  * not yet confirmed by the agent  -> red-tinted card
///  * confirmed, ticket photo needed  -> orange-tinted card
///  * ready (photo attached)          -> plain gray card
///  * waiting on the passenger        -> plain gray card
({Color card, Color pill, Color fg, String label}) _statusFor({
  required bool ready,
  required bool paid,
  required bool seen,
}) {
  if (ready) {
    return (card: _kGray, pill: _kGreenBg, fg: _kGreen, label: 'Ready');
  }
  if (!paid) {
    return (
      card: _kGray,
      pill: AppColors.white,
      fg: _kSlate,
      label: 'Awaiting payment',
    );
  }
  if (!seen) {
    return (
      card: _kRedCard,
      pill: _kRedPill,
      fg: _kRed,
      label: 'Needs action',
    );
  }
  return (
    card: _kOrangeCard,
    pill: _kOrangePill,
    fg: _kOrange,
    label: 'Photo needed',
  );
}
const double _kControlRadius = 12;

/// The active booking view on the agent portal.
enum _AgentView { action, today, completed }

/// Field-agent portal: assigned-route bookings, the "I have seen it" step, and
/// the mandatory photo of the physical ticket that makes a booking ready.
///
/// Two tabs share one app bar: the booking feed and the agent's settings
/// (password + notification permission). Tapping a booking opens a detail
/// sheet with the actions for that booking.
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
  _AgentView _view = _AgentView.action;
  int _tab = 0;
  int _visibleLimit = 7;
  String? _error;
  Timer? _reloadDebounce;
  StreamSubscription<SocketEvent>? _socketSub;

  /// Booking opened from an alarm (`/agent?booking=<id>`). Held until the
  /// feed has loaded, then presented as the detail sheet.
  String? _pendingBookingId;
  String? _handledDeepLinkId;
  bool _openingPending = false;

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

  /// Whether a booking has been paid (only paid bookings are shown to the agent).
  bool _isPaid(Booking booking) => booking.paymentStatus == 'paid';

  /// Whether the travel date has not yet passed (today or in the future).
  /// Bookings without a date are treated as upcoming.
  bool _isUpcoming(Booking booking) {
    final date = booking.travelDate;
    if (date == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(today);
  }

  /// Whether the booking departs today. The whole feed is fetched once, so the
  /// "Today's trips" chip filters the cached rows instead of waiting on a new
  /// network request.
  bool _isToday(Booking booking) {
    final date = booking.travelDate;
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Derived views, recomputed only when the data or the filter changes.
  /// Previously these were getters, so each rebuild rescanned and reallocated
  /// the 100-row list four or five times.
  int _attentionCount = 0;
  List<Booking> _visibleBookings = const <Booking>[];

  void _recomputeDerived() {
    _attentionCount = _bookings
        .where((b) => _needsAttention(b) && _isUpcoming(b))
        .length;
    _visibleBookings = switch (_view) {
      _AgentView.action => _bookings
          .where((b) => _needsAttention(b) && _isUpcoming(b))
          .toList()
        ..sort(_compareBookings),
      _AgentView.today => _bookings
          .where((b) => _isPaid(b) && _isToday(b))
          .toList()
        ..sort(_compareBookings),
      _AgentView.completed =>
        _bookings.where(_hasProof).toList()..sort(_compareCompleted),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
    _listenForUpdates();

    // Safety net for accounts that signed in before permission was granted:
    // without POST_NOTIFICATIONS (Android 13+) every alert is silently dropped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notificationServiceProvider).requestPermission());
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
        'booking_paid',
        'booking_closed',
        'agent_reminder',
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

    // Always fetch the full feed. All three tabs filter the same cached rows,
    // so switching tabs is instant and never depends on a network round-trip.
    final result = await _repo.getAgentBookings(page: 1, limit: 100);
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (response) {
        // Completed rows are history; cancelled/rejected rows never belong here.
        final active = response.bookings
            .where(
              (b) => b.status != 'cancelled' && b.status != 'rejected',
            )
            .toList();
        setState(() {
          _bookings = active;
          _visibleLimit = 7;
          _recomputeDerived();
          _loading = false;
          _error = null;
        });
        _openPendingBooking();
      },
    );
  }

  /// A push/alarm deep-links to `/agent?booking=<id>`. Remember the id, then
  /// open that booking's detail sheet once the feed contains it.
  void _captureDeepLinkBooking() {
    final id =
        GoRouterState.of(context).uri.queryParameters['booking'];
    if (id == null || id.isEmpty || id == _handledDeepLinkId) return;
    _pendingBookingId = id;
  }

  void _openPendingBooking() {
    final id = _pendingBookingId;
    if (id == null || _openingPending || _bookings.isEmpty) return;
    if (_bookings.indexWhere((b) => b.id == id) < 0) {
      _pendingBookingId = null;
      _handledDeepLinkId = id;
      return;
    }
    _pendingBookingId = null;
    _handledDeepLinkId = id;
    _openingPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final index = _bookings.indexWhere((b) => b.id == id);
      if (index >= 0) {
        await _openBooking(_bookings[index]);
      }
      _openingPending = false;
    });
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

  /// Completed trips list newest-first so the agent sees the most recent
  /// departure at the top.
  int _compareCompleted(Booking a, Booking b) {
    final da = a.travelDate ?? DateTime(2000);
    final db = b.travelDate ?? DateTime(2000);
    final byDate = db.compareTo(da);
    if (byDate != 0) return byDate;
    return (b.travelTime ?? '').compareTo(a.travelTime ?? '');
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<Booking?> _markSeen(Booking booking) async {
    if (_busy.contains(booking.id)) return null;
    setState(() => _busy.add(booking.id));
    final result = await _repo.markSeen(booking.id);
    if (!mounted) return null;
    setState(() => _busy.remove(booking.id));
    return result.fold(
      (failure) {
        _showSnack(failure.message, isError: true);
        // The booking may have been claimed by another agent in the meantime;
        // refresh so it drops out of this agent's feed immediately.
        _scheduleReload();
        return null;
      },
      (updated) {
        _replaceBooking(updated);
        _showSnack('Booking confirmed. Capture the ticket photo next.');
        return updated;
      },
    );
  }

  Future<Booking?> _captureAndMarkReady(Booking booking) async {
    if (_busy.contains(booking.id)) return null;

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
      return null;
    }
    if (shot == null) return null;

    File photo = File(shot.path);
    while (mounted) {
      final choice = await _confirmPhoto(photo);
      if (!mounted) return null;
      if (choice == 'retake') {
        await _deleteQuietly(photo);
        try {
          final retake = await _picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.rear,
            imageQuality: 70,
            maxWidth: 1600,
          );
          if (retake == null) return null;
          photo = File(retake.path);
          continue;
        } catch (_) {
          _showSnack('Could not reopen the camera.', isError: true);
          return null;
        }
      }
      if (choice != 'use') {
        await _deleteQuietly(photo);
        return null;
      }
      break;
    }

    setState(() => _busy.add(booking.id));
    final result = await _repo.markReady(booking.id, photo);
    await _deleteQuietly(photo);
    if (!mounted) return null;
    setState(() => _busy.remove(booking.id));
    return result.fold(
      (failure) {
        _showSnack(failure.message, isError: true);
        _scheduleReload();
        return null;
      },
      (updated) {
        _replaceBooking(updated);
        _showSnack('Ticket marked ready. The passenger has been notified.');
        return updated;
      },
    );
  }

  /// Post-capture review, laid out on the wireframe: a square-ish white modal
  /// with centered content and a flush, full-width Cancel / Continue bar.
  Future<String?> _confirmPhoto(File photo) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.text.withValues(alpha: 0.55),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final imageHeight = (media.size.height * 0.40)
            .clamp(180.0, 360.0)
            .toDouble();

        Widget action(String label, Color bg, Color fg, String result) {
          return Expanded(
            child: Material(
              color: bg,
              child: InkWell(
                onTap: () => Navigator.pop(ctx, result),
                child: SizedBox(
                  height: 58,
                  child: Center(
                    child: Text(
                      label,
                      style: AppTypography.buttonMedium.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: media.size.height * 0.86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              height: imageHeight,
                              color: _kGray,
                              child: Image.file(
                                photo,
                                fit: BoxFit.contain,
                                cacheWidth: (media.size.width * 1.4).round(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Review ticket photo',
                            textAlign: TextAlign.center,
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Make sure the ticket number and passenger name '
                            'are readable. This photo is the proof sent to the '
                            'passenger.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSub,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => Navigator.pop(ctx, 'retake'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              textStyle: AppTypography.labelMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retake photo'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Flush, full-width action bar.
                Row(
                  children: [
                    action('Cancel', AppColors.primary, AppColors.white,
                        'cancel'),
                    action('Continue', _kTeal, AppColors.text, 'use'),
                  ],
                ),
              ],
            ),
          ),
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
      _recomputeDerived();
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
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Log out?',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        content: Text(
          'You will need to sign in again to see your assigned bookings.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSub,
            height: 1.5,
          ),
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
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_kControlRadius),
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
    context.go('/onboarding');
  }

  // ── Shell ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settingsTab = _tab == 1;
    // An alarm tap can carry a booking id; open it as soon as it is available.
    _captureDeepLinkBooking();
    // Only queue the callback when something is actually waiting, instead of
    // scheduling one on every frame this screen builds.
    if (!_loading && _pendingBookingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPendingBooking();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: KatishaAppBar(
        title: settingsTab ? 'Settings' : _portalTitle(),
        showLottie: false,
        showBell: false,
        extraActions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSub),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildBody(),
          AgentSettingsView(onLogout: _logout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavSelected,
        backgroundColor: AppColors.white,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: _kGray,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        surfaceTintColor: Colors.transparent,
        destinations: [
          NavigationDestination(
            icon: _bookingsTabIcon(
              const Icon(Icons.confirmation_num_outlined),
              selected: false,
            ),
            selectedIcon: _bookingsTabIcon(
              const Icon(Icons.confirmation_num),
              selected: true,
            ),
            label: 'Bookings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.check_circle_outline_rounded),
            selectedIcon: Icon(Icons.check_circle_rounded),
            label: 'Completed',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _bookingsTabIcon(Widget icon, {required bool selected}) {
    final count = _attentionCount;
    if (count == 0) return icon;
    return Badge(
      backgroundColor: AppColors.error,
      textColor: AppColors.white,
      label: Text(count > 9 ? '9+' : '$count'),
      child: icon,
    );
  }

  /// Bottom-nav index for the current view: Bookings (0), Completed (1),
  /// Settings (2). "Completed" reuses the Bookings screen with a filter, so it
  /// never navigates to a separate tab — it filters in place like the
  /// "Action required" / "Today's" chips.
  int get _navIndex {
    if (_tab == 1) return 2;
    return _view == _AgentView.completed ? 1 : 0;
  }

  /// Switches the bookings filter immediately from the cached rows and only
  /// refreshes in the background. A tab tap must never wait on the network:
  /// all three tabs share one feed, so filtering is instant.
  void _selectView(_AgentView view) {
    if (_view == view && _tab == 0) return;

    setState(() {
      _tab = 0;
      _view = view;
      _visibleLimit = 7;
      _recomputeDerived();
    });
    _scheduleReload();
  }

  void _onNavSelected(int index) {
    if (index == 2) {
      setState(() => _tab = 1);
      return;
    }
    _selectView(index == 1 ? _AgentView.completed : _AgentView.action);
  }

  /// The app-bar title: the assigned agency's name when the agent is bound to
  /// one, otherwise the generic portal label.
  String _portalTitle() {
    if (_view == _AgentView.completed) return 'Completed';
    final agency = ref.read(sessionProvider)?.agencyName;
    if (agency != null && agency.isNotEmpty) return agency;
    return 'Agent Portal';
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
    final shown = bookings.take(_visibleLimit).toList(growable: false);
    final hasMore = bookings.length > _visibleLimit;

    return Column(
      children: [
        _buildGreeting(),
        _buildFilters(bookings.length),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _load(silent: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (shown.isEmpty) _buildEmptyState(),
                ...shown.map(_buildBookingCard),
                if (hasMore) _buildViewMoreButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewMoreButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _visibleLimit += 7),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: const Text('View more'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(44),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_kControlRadius),
            ),
            textStyle: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildGreeting() {
    final user = ref.watch(sessionProvider);
    final rawName = (user?.name.trim().isNotEmpty ?? false)
        ? user!.name.trim()
        : (user?.username.trim().isNotEmpty == true
              ? user!.username.trim()
              : 'Agent');
    final firstName = rawName.split(_whitespace).first;
    final initials = rawName
        .split(_whitespace)
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: _kGray,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'A' : initials,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetingForNow(),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  firstName,
                  style: AppTypography.headlineSmall.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user?.agencyName != null && user!.agencyName!.isNotEmpty)
                  Text(
                    user.agencyName!,
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
    );
  }

  Widget _buildFilters(int visibleCount) {
    if (_view == _AgentView.completed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
        child: Row(
          children: [
            _filterChip('Completed', true, () {}),
            const Spacer(),
            Text(
              '$visibleCount ${visibleCount == 1 ? 'trip' : 'trips'}',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Row(
        children: [
          _filterChip(
            'Action required',
            _view == _AgentView.action,
            () => _selectView(_AgentView.action),
          ),
          const SizedBox(width: 8),
          _filterChip(
            'Today’s trips',
            _view == _AgentView.today,
            () => _selectView(_AgentView.today),
          ),
          const Spacer(),
          Text(
            '$visibleCount ${visibleCount == 1 ? 'booking' : 'bookings'}',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : _kGray,
          borderRadius: BorderRadius.circular(_kChipRadius),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: selected ? AppColors.white : AppColors.textSub,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: [
        _buildGreeting(),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: 5,
            itemBuilder: (_, _) => Container(
              height: 124,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _kGray,
                borderRadius: BorderRadius.circular(_kCardRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isCompleted = _view == _AgentView.completed;
    final isToday = _view == _AgentView.today;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: _kGray,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted
                  ? Icons.check_circle_outline_rounded
                  : isToday
                  ? Icons.today_rounded
                  : Icons.check_rounded,
              size: 36,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isCompleted
                ? 'No completed trips yet'
                : isToday
                ? 'No trips today'
                : 'You are all caught up',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isCompleted
                ? 'Trips you have completed will appear here.'
                : isToday
                ? 'No bookings are departing today.'
                : 'Every paid booking already has its physical ticket photo.',
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
                size: 34,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Could not load your bookings',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
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
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kControlRadius),
                ),
                textStyle: AppTypography.buttonMedium,
              ),
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
    final style = _statusFor(
      ready: _hasProof(booking),
      paid: booking.paymentStatus == 'paid',
      seen: booking.agentSeen,
    );
    final date = booking.travelDate;
    final dateLabel = date == null ? '\u2014' : _dateFormat.format(date);
    final time = booking.travelTime;
    final passenger = booking.passengerDetails.isNotEmpty
        ? booking.passengerDetails.first
        : null;
    final passengerName = passenger?.name.isNotEmpty == true
        ? passenger!.name
        : (booking.user?.name.isNotEmpty == true
              ? booking.user!.name
              : 'Passenger');

    final seatsLabel = '${booking.seats} seat${booking.seats == 1 ? '' : 's'}';
    final when = time != null && time.isNotEmpty
        ? '$dateLabel \u00b7 $time'
        : dateLabel;

    // An independent (agency-less) agent sees bookings across companies, so the
    // bus company must be shown on each card.
    final agencyName = booking.agency?.name;
    final showAgency = agencyName != null &&
        agencyName.isNotEmpty &&
        (ref.read(sessionProvider)?.agencyName ?? '').isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        hint: 'Opens booking details',
        label:
            '${style.label}. ${booking.origin} to ${booking.destination}. '
            '$passengerName, $seatsLabel, $when',
        child: Material(
          color: style.card,
          borderRadius: BorderRadius.circular(_kCardRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openBooking(booking),
            splashColor: style.fg.withValues(alpha: 0.08),
            highlightColor: style.fg.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _statusPill(style.label, style.fg, style.pill),
                            const SizedBox(width: 10),
                            Text(
                              _relativeTime(booking.createdAt),
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${booking.origin} \u2192 ${booking.destination}',
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (showAgency) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_bus_filled_rounded,
                                size: 13,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  agencyName,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSub,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '$passengerName \u00b7 $seatsLabel',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSub,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          when,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Affordance: tells the agent the card opens / expands.
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 24,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    }
    return _shortDateFormat.format(createdAt);
  }

  // ── Detail sheet ──────────────────────────────────────────────────────────

  Future<void> _openBooking(Booking booking) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.text.withValues(alpha: 0.45),
      builder: (_) => _BookingDetailsSheet(
        booking: booking,
        onUpdated: _replaceBooking,
        onMarkSeen: _markSeen,
        onMarkReady: _captureAndMarkReady,
        onViewProof: _showProof,
        imageHeaders: _imageHeaders,
      ),
    );
  }

  void _showProof(Booking booking) {
    final url = resolveMediaUrl(booking.ticketProofImage);
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ticket proof',
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: IconButton.styleFrom(
                      backgroundColor: _kGray,
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
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
                      child: Center(child: Text('Could not load the photo')),
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

// ── Shared button styles ────────────────────────────────────────────────────

ButtonStyle _primaryButtonStyle({double height = 52}) {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.white,
    elevation: 0,
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_kControlRadius),
    ),
    textStyle: AppTypography.buttonMedium,
  );
}

ButtonStyle _grayButtonStyle({double height = 48, Color? foreground}) {
  final fg = foreground ?? AppColors.text;
  return FilledButton.styleFrom(
    backgroundColor: _kGray,
    foregroundColor: fg,
    elevation: 0,
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(vertical: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_kControlRadius),
    ),
    textStyle: AppTypography.buttonSmall.copyWith(color: fg),
  );
}

// ---------------------------------------------------------------------------
// Booking detail sheet
// ---------------------------------------------------------------------------

class _BookingDetailsSheet extends ConsumerStatefulWidget {
  const _BookingDetailsSheet({
    required this.booking,
    required this.onUpdated,
    required this.onMarkSeen,
    required this.onMarkReady,
    required this.onViewProof,
    required this.imageHeaders,
  });

  final Booking booking;
  final ValueChanged<Booking> onUpdated;
  final Future<Booking?> Function(Booking) onMarkSeen;
  final Future<Booking?> Function(Booking) onMarkReady;
  final void Function(Booking) onViewProof;
  final Map<String, String>? imageHeaders;

  @override
  ConsumerState<_BookingDetailsSheet> createState() =>
      _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends ConsumerState<_BookingDetailsSheet> {
  late Booking _booking = widget.booking;
  bool _busy = false;

  bool get _paid => _booking.paymentStatus == 'paid';
  bool get _ready =>
      _booking.ticketProofImage != null &&
      _booking.ticketProofImage!.isNotEmpty;

  bool get _waitingOnAgent => _paid && !_ready;

  Future<void> _run(Future<Booking?> Function(Booking) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final updated = await action(_booking);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (updated != null) _booking = updated;
    });
    if (updated != null) widget.onUpdated(updated);
  }

  Future<void> _replaceOrRetake() => _run(widget.onMarkReady);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTripCard(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Passenger'),
                    const SizedBox(height: 12),
                    _buildPassengerCard(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Payment'),
                    const SizedBox(height: 12),
                    _buildPaymentCard(),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Ticket proof'),
                    const SizedBox(height: 12),
                    _buildProofCard(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: _kGrayStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final status = _statusFor(
      ready: _ready,
      paid: _paid,
      seen: _booking.agentSeen,
    );
    final label = status.label;
    final fg = status.fg;
    final bg = status.pill;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              'Booking details',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            style: IconButton.styleFrom(
              backgroundColor: _kGray,
              minimumSize: const Size(36, 36),
            ),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard() {
    final date = _booking.travelDate;
    final dateLabel = date == null ? '\u2014' : _numericDateFormat.format(date);
    final time = _booking.travelTime;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kGray,
        borderRadius: BorderRadius.circular(_kCardRadius),
      ),
      child: Column(
        children: [
          if (_booking.agency?.name != null &&
              _booking.agency!.name.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.directions_bus_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _booking.agency!.name,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSub,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _routeEndpoint(
                  label: 'From',
                  city: _booking.origin,
                  filled: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(width: 28, height: 2, color: _kGrayStrong),
                    const SizedBox(height: 3),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: AppColors.textSub,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _routeEndpoint(
                  label: 'To',
                  city: _booking.destination,
                  filled: false,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // White tone-on-tone panel instead of divider lines.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(_kControlRadius),
            ),
            child: Row(
              children: [
                Expanded(child: _miniDetail('Date', dateLabel)),
                Expanded(
                  child: _miniDetail(
                    'Time',
                    (time != null && time.isNotEmpty) ? time : '\u2014',
                  ),
                ),
                Expanded(child: _miniDetail('Seats', '${_booking.seats}')),
              ],
            ),
          ),
          if (_booking.seatNumbers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Seat ${_booking.seatNumbers.join(', ')}',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeEndpoint({
    required String label,
    required String city,
    required bool filled,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!alignEnd) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.text,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                city.isEmpty ? '\u2014' : city,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _miniDetail(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        // Scale down rather than clip: a full date (dd/MM/yyyy) and the seat
        // count must stay readable in a third of the card's width.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerCard() {
    final passenger = _booking.passengerDetails.isNotEmpty
        ? _booking.passengerDetails.first
        : null;
    final name = passenger?.name.isNotEmpty == true
        ? passenger!.name
        : (_booking.user?.name.isNotEmpty == true
              ? _booking.user!.name
              : 'Passenger');
    final phone = passenger?.phone.isNotEmpty == true
        ? passenger!.phone
        : (_booking.phone ??
              _booking.contactPhone ??
              _booking.user?.phone ??
              '');
    final initials = name
        .split(_whitespace)
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: _kGray,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'P' : initials,
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_booking.pickupPoint != null && _booking.pickupPoint!.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGray,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        _booking.pickupPoint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    final method = _methodLabel(_booking.paymentMethod);
    final total = _booking.totalAmount > 0
        ? '${_amountFormat.format(_booking.totalAmount)} RWF'
        : 'Free ticket';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          _infoRow('Amount', total, emphasize: true),
          const SizedBox(height: 12),
          _infoRow(
            'Payment',
            _paid ? 'Paid' : 'Awaiting payment',
            valueColor: _paid ? _kGreen : AppColors.warning,
          ),
          if (method != null) ...[
            const SizedBox(height: 12),
            _infoRow('Method', method),
          ],
          const SizedBox(height: 12),
          _infoRow(
            'Issued by agent',
            _booking.agentSeen ? 'Seen' : 'Not yet seen',
            valueColor: _booking.agentSeen ? _kGreen : AppColors.textSub,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color? valueColor,
    bool emphasize = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                (emphasize ? AppTypography.titleSmall : AppTypography.bodySmall)
                    .copyWith(
                      color:
                          valueColor ??
                          (emphasize ? AppColors.text : AppColors.textSub),
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ),
      ],
    );
  }

  String? _methodLabel(String? method) {
    return switch (method) {
      'mom' => 'MTN MoMo',
      'airtel' => 'Airtel Money',
      'mpesa' => 'M-Pesa',
      null || '' => null,
      _ => method,
    };
  }

  Widget _buildProofCard() {
    if (!_ready) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kGray,
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_camera_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _waitingOnAgent
                    ? 'No ticket photo yet. Capture it once the ticket is issued.'
                    : 'The photo is captured after the passenger has paid.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final url = resolveMediaUrl(_booking.ticketProofImage);
    return Material(
      color: _kGray,
      borderRadius: BorderRadius.circular(_kCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onViewProof(_booking),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: url == null
                    ? Container(
                        width: 52,
                        height: 52,
                        color: AppColors.white,
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.textSub,
                          size: 20,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                        httpHeaders: widget.imageHeaders,
                        placeholder: (_, _) => Container(
                          width: 52,
                          height: 52,
                          color: _kGrayStrong,
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 52,
                          height: 52,
                          color: AppColors.white,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket photo attached',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to inspect the proof',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
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
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTypography.titleSmall.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: _buildActions(),
    );
  }

  Widget _buildActions() {
    if (_busy) {
      return const SizedBox(
        height: 50,
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

    if (!_paid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kGray,
          borderRadius: BorderRadius.circular(_kControlRadius),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waiting for the passenger\u2019s payment',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_booking.agentSeen) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _run(widget.onMarkSeen),
          style: _primaryButtonStyle(),
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: const Text('Confirm I have seen this booking'),
        ),
      );
    }

    if (!_ready) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _run(widget.onMarkReady),
          style: _primaryButtonStyle(),
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: const Text('Mark ready & photograph ticket'),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => widget.onViewProof(_booking),
            style: _grayButtonStyle(height: 48),
            icon: const Icon(Icons.photo_outlined, size: 17),
            label: const Text('View proof'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: _replaceOrRetake,
            style: _grayButtonStyle(height: 48, foreground: AppColors.textSub),
            icon: const Icon(Icons.camera_alt_outlined, size: 17),
            label: const Text('Replace photo'),
          ),
        ),
      ],
    );
  }
}
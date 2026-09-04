import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/booking_model.dart';
import '../../data/my_bookings_repository.dart';

final _myBookingsRepoProvider = Provider<MyBookingsRepository>((ref) {
  return MyBookingsRepository(ref.read(apiClientProvider));
});

/// User's bookings screen - shows only non-expired, active bookings.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  int _page = 1;
  bool _hasMore = true;
  List<Booking> _bookings = [];
  bool _loading = true;
  String? _error;

  MyBookingsRepository get _repo => ref.read(_myBookingsRepoProvider);

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  bool _isNonExpired(Booking b) {
    if (b.status == 'cancelled' || b.status == 'rejected') return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (b.travelDate == null) return false;
    final travelDate =
        DateTime(b.travelDate!.year, b.travelDate!.month, b.travelDate!.day);
    return !travelDate.isBefore(today);
  }

  Future<void> _fetchBookings({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _bookings = [];
        _loading = true;
      });
    }
    setState(() => _loading = true);
    final result = await _repo.getMyBookings(_page, 50);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        // A session/auth failure just means we can't reach the user's
        // bookings (e.g. no session from a prior guest booking). We show the
        // empty "no tickets yet" state with a Make a Booking button instead of
        // a blocking error, matching the web frontend behaviour for users who
        // register when purchasing a ticket.
        _error = failure is AuthFailure ? null : failure.message;
        _loading = false;
      }),
      (response) {
        final nonExpired = response.bookings.where(_isNonExpired).toList();
        setState(() {
          if (_page == 1) {
            _bookings = nonExpired;
          } else {
            _bookings = [..._bookings, ...nonExpired];
          }
          _hasMore = _page < response.pages;
          _loading = false;
          _error = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: KatishaAppBar(
        title: l10n.translate('my_bookings'),
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading && _bookings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 16),
            Text(
              'Loading your trips...',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null && _bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 32,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _fetchBookings(refresh: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(l10n.translate('retry')),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Booking count pill
        if (_bookings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_bookings.length} upcoming ${_bookings.length == 1 ? 'trip' : 'trips'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),

        Expanded(
          child: _bookings.isEmpty
              ? _buildEmptyState(l10n)
              : RefreshIndicator(
                  onRefresh: () => _fetchBookings(refresh: true),
                  color: AppColors.primary,
                  strokeWidth: 2,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _bookings.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _bookings.length) {
                        _page++;
                        _fetchBookings();
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return _BookingCard(
                        booking: _bookings[index],
                        onTap: () =>
                            context.push('/ticket/${_bookings[index].id}'),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.confirmation_num_outlined,
                size: 36,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.translate('no_bookings'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.translate('no_tickets_subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go('/home'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(l10n.translate('book_your_ticket')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Status helpers ------------------------------------------------------------

Color _statusFgColor(String status) {
  switch (status) {
    case 'confirmed':
      return const Color(0xFF15803D);
    case 'pending':
      return const Color(0xFFB45309);
    case 'cancelled':
    case 'rejected':
      return const Color(0xFFB91C1C);
    default:
      return const Color(0xFF6B7280);
  }
}

Color _statusBgColor(String status) {
  switch (status) {
    case 'confirmed':
      return const Color(0xFFDCFCE7);
    case 'pending':
      return const Color(0xFFFEF3C7);
    case 'cancelled':
    case 'rejected':
      return const Color(0xFFFEE2E2);
    default:
      return const Color(0xFFF1F5F9);
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'confirmed':
      return 'Confirmed';
    case 'pending':
      return 'Pending';
    case 'cancelled':
      return 'Cancelled';
    case 'rejected':
      return 'Rejected';
    default:
      return status;
  }
}

// --- Booking Card -------------------------------------------------------------

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;

  const _BookingCard({required this.booking, this.onTap});

  void _showTicketModal(BuildContext context) {
    if (booking.ticketImage == null || booking.ticketImage!.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.88),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _TicketModal(ticketImage: booking.ticketImage!);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormat('EEE, d MMM yyyy');
    final dateStr = booking.travelDate != null
        ? dateFormat.format(booking.travelDate!)
        : '—';
    final hasImage =
        booking.ticketImage != null && booking.ticketImage!.isNotEmpty;
    final status = booking.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: AppColors.primary.withOpacity(0.04),
          highlightColor: AppColors.primary.withOpacity(0.02),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Route + Status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Origin ? Destination
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              booking.origin,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              booking.destination,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusBgColor(status),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _statusFgColor(status),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Divider
                const Divider(height: 1, color: Color(0xFFF3F4F6)),

                const SizedBox(height: 14),

                // Meta row: date, seats, agency
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: '$dateStr${booking.travelTime != null && booking.travelTime!.isNotEmpty ? ' · ${booking.travelTime}' : ''}',
                    ),
                    _MetaChip(
                      icon: Icons.event_seat_rounded,
                      label: '${booking.seats} seat${booking.seats > 1 ? 's' : ''}',
                    ),
                    if (booking.agency != null &&
                        booking.agency!.name.isNotEmpty)
                      _MetaChip(
                        icon: Icons.directions_bus_rounded,
                        label: booking.agency!.name,
                      ),
                  ],
                ),

                // View Ticket button (only if image exists)
                if (hasImage) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showTicketModal(context),
                      icon: const Icon(Icons.qr_code_rounded, size: 15),
                      label: Text(l10n.translate('view_ticket')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withOpacity(0.4),
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Meta chip ----------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// --- Ticket Modal -------------------------------------------------------------

class _TicketModal extends StatelessWidget {
  final String ticketImage;

  const _TicketModal({required this.ticketImage});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Ticket dimensions: 88% width, flexible height up to 78%
    final ticketWidth = screenSize.width * 0.88;
    final ticketHeight = screenSize.height * 0.78;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Centered ticket
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ticket container with shadow
                      Container(
                        width: ticketWidth,
                        constraints: BoxConstraints(
                          maxHeight: ticketHeight,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CachedNetworkImage(
                          imageUrl: ticketImage,
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topCenter,
                          memCacheWidth:
                              (ticketWidth * MediaQuery.of(context).devicePixelRatio).toInt(),
                          placeholder: (_, __) => SizedBox(
                            height: 280,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Loading ticket...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSub,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 280,
                            color: AppColors.surface,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.broken_image_rounded,
                                      size: 28,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Ticket unavailable',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSub,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap to dismiss',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Instruction label with better visibility
                      Container(
                        width: ticketWidth,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Show this ticket to the boarding officer',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
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

              // Close button - top right
              Positioned(
                top: 8,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
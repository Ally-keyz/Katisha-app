import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/my_bookings/data/my_bookings_repository.dart';
import '../network/api_client.dart';
import '../../shared/models/booking_model.dart';
import 'platform_providers.dart';

/// Holds the live counts shown as red badges on the bottom navigation bar.
///
/// The nav shell watches this provider so badges update automatically whenever
/// tickets are cached or notifications change.
class BadgeCounts {
  final int ticketCount;
  final int notificationCount;

  const BadgeCounts({
    this.ticketCount = 0,
    this.notificationCount = 0,
  });
}

class BadgeCountsNotifier extends Notifier<BadgeCounts> {
  bool _fetchedFromServer = false;

  @override
  BadgeCounts build() {
    final counts = const BadgeCounts();
    _refresh();
    return counts;
  }

  Future<void> _refresh() async {
    final store = ref.read(localTicketStoreProvider);
    final notifStore = ref.read(localNotificationStoreProvider);

    final ticketCount = await store.getActiveTicketCount();

    final notifications = await notifStore.getAll();
    final notifCount = notifications.where((n) => !n.read).length;

    state = BadgeCounts(
      ticketCount: ticketCount,
      notificationCount: notifCount,
    );

    // On first build, sync the real ticket list from the server so the badge
    // shows accurate counts even before the user opens "My Trips".
    if (!_fetchedFromServer) {
      _fetchedFromServer = true;
      unawaited(_syncTicketCountFromServer());
    }
  }

  Future<void> _syncTicketCountFromServer() async {
    try {
      final repo = MyBookingsRepository(ref.read(apiClientProvider));
      final result = await repo.getMyBookings(1, 50);
      await result.fold(
        (failure) async {},
        (response) async {
          final store = ref.read(localTicketStoreProvider);
          final api = ref.read(apiClientProvider);
          for (final b in response.bookings) {
            await store.cacheBooking(b.id, _bookingToJson(b));
            // Pre-download ticket images so they are available offline and stay
            // inside the app (never in the gallery or public file manager).
            final imageUrl = b.ticketImage;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              final exists = await store.getTicketImagePath(b.id);
              if (exists == null) {
                try {
                  final r = await api.downloadBytes(imageUrl);
                  final data = r.data;
                  if (data is List<int>) {
                    await store.saveTicketImage(
                      b.id,
                      Uint8List.fromList(data),
                    );
                  }
                } catch (_) {}
              }
            }
          }
          _refresh();
        },
      );
    } catch (_) {}
  }

  Map<String, dynamic> _bookingToJson(Booking booking) {
    return {
      'id': booking.id,
      'referenceCode': booking.referenceCode,
      'origin': booking.origin,
      'destination': booking.destination,
      'pickupPoint': booking.pickupPoint,
      'travelDate': booking.travelDate?.toIso8601String(),
      'travelTime': booking.travelTime,
      'seats': booking.seats,
      'seatNumbers': booking.seatNumbers,
      'status': booking.status,
      'paymentStatus': booking.paymentStatus,
      'paymentMethod': booking.paymentMethod,
      'agency': booking.agency != null
          ? {'id': booking.agency!.id, 'name': booking.agency!.name}
          : null,
      'totalAmount': booking.totalAmount,
    };
  }

  /// Recomputes both badges from their backing stores.
  Future<void> refresh() => _refresh();
}

/// Provider for the bottom-nav badge counts.
final badgeCountsProvider = NotifierProvider<BadgeCountsNotifier, BadgeCounts>(
  BadgeCountsNotifier.new,
);
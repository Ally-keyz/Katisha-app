import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/media_url.dart';
import 'local_ticket_store.dart';
import 'notification_service.dart';
import 'platform_providers.dart';

/// Fetches the logged-in user's tickets from the server and persists them
/// locally so they are available without an internet connection.
///
/// Runs in the background after login / on app start (unawaited), so the user
/// can open My Trips and ticket screens even when offline. It also re-arms the
/// 2h / 1h / 30m departure alarms for every upcoming trip, so the alarms exist
/// even after a reinstall or a fresh sign-in on another device.
///
/// Ticket images are saved to the app-private Documents folder (never the
/// gallery).
class TicketSyncService {
  final ApiClient _api;
  final LocalTicketStore _store;
  final NotificationService _notifications;
  bool _syncing = false;

  /// Remembers which departure time was last scheduled for a booking, so a
  /// sync that runs on every app action does not re-schedule the same alarms.
  final Map<String, String> _scheduledAlerts = {};

  TicketSyncService(this._api, this._store, this._notifications);

  /// Whether a sync is currently in flight.
  bool get isSyncing => _syncing;

  /// Fetches all pages of the logged-in user's bookings and caches each one
  /// (ticket JSON + private ticket image) locally. No-op when signed out.
  /// Never throws — failures just stop the background sync quietly.
  Future<void> syncAllTickets() async {
    if (!_api.isAuthenticated || _syncing) return;
    _syncing = true;
    var page = 1;
    try {
      // Cache as much as available (safety cap of 100 pages); if the session
      // is dropped mid-sync, stop early.
      while (_api.isAuthenticated && page <= 100) {
        final response = await _api.get(
          '/bookings',
          queryParameters: {'page': page, 'limit': 50},
        );
        final body = response.data;
        final data = (body is Map<String, dynamic>)
            ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
            : const <String, dynamic>{};
        final bookings = (data['bookings'] as List<dynamic>?) ?? const [];
        final pages = (data['pages'] as int?) ?? 1;

        // Download ticket images in small parallel batches (bounded concurrency
        // of 4) so lots of tickets sync fast without spiking memory.
        final imageDownloads = <Future<void>>[];
        for (final raw in bookings) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['_id'] as String? ?? raw['id'] as String?;
          if (id == null || id.isEmpty) continue;
          await _store.cacheBooking(id, raw);

          await _syncJourneyAlerts(id, raw);

          // Once the agent has photographed the physical ticket, that photo is
          // the real ticket and replaces the system-generated image everywhere.
          final proofUrl = raw['ticketProofImage'] as String?;
          final ticketUrl = raw['ticketImage'] as String?;
          final primaryUrl = (proofUrl != null && proofUrl.isNotEmpty)
              ? proofUrl
              : ticketUrl;
          if (primaryUrl == null || primaryUrl.isEmpty) continue;

          final cachedUrl = await _store.getTicketImageUrl(id);
          final hasImage = await _store.getTicketImagePath(id) != null;
          if (hasImage && cachedUrl == primaryUrl) continue;
          imageDownloads.add(_downloadImage(id, primaryUrl));
          if (imageDownloads.length >= 4) {
            await Future.wait(imageDownloads);
            imageDownloads.clear();
          }
        }
        if (imageDownloads.isNotEmpty) {
          await Future.wait(imageDownloads);
        }

        page++;
        if (page > pages) break;
      }
    } catch (_) {
      // Best-effort background sync — never crash the app on network errors.
    } finally {
      _syncing = false;
    }
  }

  /// Arms the 2h / 1h / 30m alarms for an upcoming, paid trip, and clears them
  /// for a cancelled one. Cheap to call repeatedly: unchanged departures skip
  /// the work.
  Future<void> _syncJourneyAlerts(
    String bookingId,
    Map<String, dynamic> raw,
  ) async {
    final status = raw['status'] as String? ?? '';
    final paymentStatus = raw['paymentStatus'] as String? ?? '';

    if (status == 'cancelled' || status == 'rejected') {
      if (_scheduledAlerts.remove(bookingId) != null) {
        await _notifications.cancelJourneyAlert(bookingId);
      }
      return;
    }

    if (paymentStatus != 'paid') return;
    if (status != 'confirmed' && status != 'issued') return;

    final departure = _departureOf(raw);
    if (departure == null || departure.isBefore(DateTime.now())) return;

    final marker = departure.toIso8601String();
    if (_scheduledAlerts[bookingId] == marker) return;

    await _notifications.scheduleJourneyAlerts(
      bookingId: bookingId,
      routeName:
          '${raw['origin'] ?? ''} → ${raw['destination'] ?? ''}',
      departureTime: departure,
    );
    _scheduledAlerts[bookingId] = marker;
  }

  DateTime? _departureOf(Map<String, dynamic> raw) {
    final dateRaw = raw['travelDate'];
    if (dateRaw == null) return null;
    final date = DateTime.tryParse(dateRaw.toString());
    if (date == null) return null;

    final timeRaw = raw['travelTime']?.toString() ?? '';
    final parts = timeRaw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Future<void> _downloadImage(String bookingId, String imageUrl) async {
    try {
      final response = await _api.downloadBytes(
        resolveMediaUrl(imageUrl) ?? imageUrl,
      );
      final data = response.data;
      if (data is List<int>) {
        await _store.saveTicketImage(bookingId, Uint8List.fromList(data));
        await _store.setTicketImageUrl(bookingId, imageUrl);
      }
    } catch (_) {}
  }
}

/// Provider for the background ticket sync service.
final ticketSyncServiceProvider = Provider<TicketSyncService>((ref) {
  return TicketSyncService(
    ref.read(apiClientProvider),
    ref.read(localTicketStoreProvider),
    ref.read(notificationServiceProvider),
  );
});

/// Kicks off the background ticket sync (fire-and-forget).
void startBackgroundTicketSync(WidgetRef ref) {
  final service = ref.read(ticketSyncServiceProvider);
  unawaited(service.syncAllTickets());
}

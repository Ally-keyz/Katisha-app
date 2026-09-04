import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'local_ticket_store.dart';
import 'platform_providers.dart';

/// Fetches the logged-in user's tickets from the server and persists them
/// locally so they are available without an internet connection.
///
/// Runs in the background after login / on app start (unawaited), so the user
/// can open My Trips and ticket screens even when offline. Ticket images are
/// saved to the app-private Documents folder (never the gallery).
class TicketSyncService {
  final ApiClient _api;
  final LocalTicketStore _store;
  bool _syncing = false;

  TicketSyncService(this._api, this._store);

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
          final imageUrl = raw['ticketImage'] as String?;
          if (imageUrl == null || imageUrl.isEmpty) continue;
          if (await _store.getTicketImagePath(id) != null) continue;
          imageDownloads.add(_downloadImage(id, imageUrl));
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

  Future<void> _downloadImage(String bookingId, String imageUrl) async {
    try {
      final response = await _api.downloadBytes(imageUrl);
      final data = response.data;
      if (data is List<int>) {
        await _store.saveTicketImage(bookingId, Uint8List.fromList(data));
      }
    } catch (_) {}
  }
}

/// Provider for the background ticket sync service.
final ticketSyncServiceProvider = Provider<TicketSyncService>((ref) {
  return TicketSyncService(
    ref.read(apiClientProvider),
    ref.read(localTicketStoreProvider),
  );
});

/// Kicks off the background ticket sync (fire-and-forget).
void startBackgroundTicketSync(WidgetRef ref) {
  final service = ref.read(ticketSyncServiceProvider);
  unawaited(service.syncAllTickets());
}
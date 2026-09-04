import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'platform_providers.dart';
import 'ticket_sync_service.dart';

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
  bool _firstRefreshDone = false;

  @override
  BadgeCounts build() {
    // Kick off a full background sync on first build (which also refreshes the
    // counts via the ticket sync service) so badge values stay accurate.
    if (!_firstRefreshDone) {
      _firstRefreshDone = true;
      unawaited(_syncAndRefresh());
    }
    return const BadgeCounts();
  }

  Future<void> _syncAndRefresh() async {
    final api = ref.read(apiClientProvider);
    if (!api.isAuthenticated) {
      await _refresh();
      return;
    }
    final service = ref.read(ticketSyncServiceProvider);
    await service.syncAllTickets();
    await _refresh();
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
  }

  /// Recomputes both badges from their backing stores.
  Future<void> refresh() => _refresh();
}

/// Provider for the bottom-nav badge counts.
final badgeCountsProvider = NotifierProvider<BadgeCountsNotifier, BadgeCounts>(
  BadgeCountsNotifier.new,
);
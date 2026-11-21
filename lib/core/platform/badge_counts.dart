import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_providers.dart';

/// Holds the live counts shown as red badges on the bottom navigation bar.
///
/// The nav shell watches this provider so badges update automatically whenever
/// tickets are cached or notifications change.
class BadgeCounts {
  final int ticketCount;
  final int notificationCount;

  const BadgeCounts({this.ticketCount = 0, this.notificationCount = 0});
}

class BadgeCountsNotifier extends Notifier<BadgeCounts> {
  bool _firstRefreshDone = false;

  /// When signed in, the server's unread count is the source of truth. The
  /// local store is only a fallback for signed-out/offline sessions.
  int? _serverUnreadCount;

  @override
  BadgeCounts build() {
    // Counts are derived from the local stores only. The network sync is kicked
    // off by the splash screen; doing it here meant merely *watching* a badge
    // could start a full multi-page ticket download.
    if (!_firstRefreshDone) {
      _firstRefreshDone = true;
      unawaited(_refresh());
    }
    return const BadgeCounts();
  }

  Future<void> _refresh() async {
    final store = ref.read(localTicketStoreProvider);
    final notifStore = ref.read(localNotificationStoreProvider);

    final ticketCount = await store.getActiveTicketCount();

    final notifications = await notifStore.getAll();
    final localUnread = notifications.where((n) => !n.read).length;

    state = BadgeCounts(
      ticketCount: ticketCount,
      notificationCount: _serverUnreadCount ?? localUnread,
    );
  }

  /// Recomputes both badges. Pass [unreadCount] from `/notifications` to make
  /// the bottom-nav badge agree with the notifications page; pass
  /// [useLocalUnread] when signed out so the local cache becomes authoritative
  /// again.
  Future<void> refresh({int? unreadCount, bool useLocalUnread = false}) async {
    if (unreadCount != null) {
      _serverUnreadCount = unreadCount < 0 ? 0 : unreadCount;
    } else if (useLocalUnread) {
      _serverUnreadCount = null;
    }
    await _refresh();
  }
}

/// Provider for the bottom-nav badge counts.
final badgeCountsProvider = NotifierProvider<BadgeCountsNotifier, BadgeCounts>(
  BadgeCountsNotifier.new,
);

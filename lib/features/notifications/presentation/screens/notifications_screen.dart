import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/notification_model.dart';
import '../../data/notifications_repository.dart';

final _notificationsRepoProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.read(apiClientProvider));
});

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _markingRead = false;
  bool _loadingMore = false;

  NotificationsRepository get _repo => ref.read(_notificationsRepoProvider);

  int get _unreadCount => _notifications.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _notifications = [];
    }
    setState(() => _loading = true);
    final result = await _repo.getNotifications(_page, 20);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
        _loadingMore = false;
      }),
      (response) async {
        final local = await ref
            .read(localNotificationStoreProvider)
            .getAll();
        final remote = _page == 1
            ? response.notifications
            : [..._notifications.where((n) => n.id.startsWith('local_')), ...response.notifications];
        if (!mounted) return;
        setState(() {
          if (_page == 1) {
            _notifications = [...local, ...remote];
          } else {
            _notifications = [..._notifications, ...response.notifications];
          }
          _hasMore = _page < response.pages;
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      },
    );
  }

  Future<void> _markAllRead() async {
    setState(() => _markingRead = true);
    await ref.read(localNotificationStoreProvider).markAllRead();
    final result = await _repo.markAllAsRead();
    if (!mounted) return;
    result.fold(
      (_) => setState(() {
        _markingRead = false;
        _notifications = _notifications
            .map((n) => NotificationModel(
                  id: n.id,
                  title: n.title,
                  message: n.message,
                  type: n.type,
                  read: true,
                  createdAt: n.createdAt,
                ))
            .toList();
      }),
      (_) => setState(() {
        _markingRead = false;
        _notifications = _notifications
            .map((n) => NotificationModel(
                  id: n.id,
                  title: n.title,
                  message: n.message,
                  type: n.type,
                  read: true,
                  createdAt: n.createdAt,
                ))
            .toList();
      }),
    );
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore || _loading) return;
    _loadingMore = true;
    _page++;
    _fetchNotifications();
  }

  // Removes a notification when the user swipes it left or right. Locally
  // stored notifications are also removed from the persisted store; server
  // notifications are removed from the in-memory list and deleted on the API.
  Future<void> _dismissNotification(NotificationModel notification) async {
    if (notification.id.startsWith('local_')) {
      await ref.read(localNotificationStoreProvider).remove(notification.id);
    } else {
      await _repo.deleteNotification(notification.id);
    }
    if (!mounted) return;
    setState(() {
      _notifications =
          _notifications.where((n) => n.id != notification.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: KatishaAppBar(
        title: l10n.translate('notifications'),
        extraActions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingRead ? null : _markAllRead,
              child: _markingRead
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Text(
                      l10n.translate('mark_all_read'),
                      style: AppTypography.labelLarge
                          .copyWith(color: AppColors.primary),
                    ),
            ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading && _notifications.isEmpty) {
      return _buildLoadingState();
    }

    if (_error != null && _notifications.isEmpty) {
      return _buildErrorState(l10n);
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState(l10n);
    }

    final itemCount =
        _notifications.length + (_hasMore ? 1 : 0);

    return Column(
      children: [
        if (_unreadCount > 0)
          _buildUnreadBanner(l10n),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _fetchNotifications(refresh: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                if (index == _notifications.length) {
                  _loadMore();
                  return _buildLoadMoreIndicator();
                }
                final notification = _notifications[index];
                return Dismissible(
                  key: ValueKey(notification.id),
                  direction: DismissDirection.horizontal,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppColors.white),
                  ),
                  secondaryBackground: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppColors.white),
                  ),
                  onDismissed: (_) => _dismissNotification(notification),
                  child: _NotificationTile(notification: notification),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnreadBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${_unreadCount} ${_unreadCount == 1 ? l10n.translate('unread_notification') : l10n.translate('unread_notifications')}',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const _NotificationShimmer(),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.errorBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _fetchNotifications(refresh: true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + AppSpacing.xs,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final isLoggedIn = ref.read(apiClientProvider).isAuthenticated;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isLoggedIn
                  ? l10n.translate('no_notifications')
                  : 'No notifications yet',
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isLoggedIn
                  ? l10n.translate('no_notifications_subtitle')
                  : 'Book a trip and you will see updates about your journey here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textMuted),
            ),
            if (!isLoggedIn) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/book'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.directions_bus_outlined, size: 18),
                  label: const Text(
                    'Make a booking',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Notification Tile
// ---------------------------------------------------------------------------

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final timeAgo = notification.createdAt != null
        ? _formatTimeAgo(notification.createdAt!)
        : '';

    return Container(
      decoration: BoxDecoration(
        color: notification.read
            ? AppColors.white
            : AppColors.primaryLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: notification.read
              ? AppColors.border
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!notification.read)
              Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppSpacing.radiusMd),
                    bottomLeft: Radius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatar(),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: AppTypography.titleSmall.copyWith(
                                    fontWeight: notification.read
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                    color: notification.read
                                        ? AppColors.text
                                        : AppColors.text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (timeAgo.isNotEmpty) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  timeAgo,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            notification.message,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSub,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _colorForType(notification.type).withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _iconForType(notification.type),
        size: 20,
        color: _colorForType(notification.type),
      ),
    );
  }

  Color _colorForType(String type) {
    return switch (type) {
      'booking' || 'booking_created' || 'booking_issued' =>
        AppColors.primary,
      'booking_confirmed' || 'payment' || 'payment_received' =>
        AppColors.statusPaid,
      'booking_rejected' || 'cancellation' => AppColors.error,
      'journey_alert' || 'journey_alert_snooze' => AppColors.warning,
      'ticket_uploaded' => AppColors.info,
      'announcement' || 'info' => AppColors.info,
      _ => AppColors.textMuted,
    };
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'booking' || 'booking_created' || 'booking_issued' =>
        Icons.confirmation_num_outlined,
      'booking_rejected' || 'cancellation' => Icons.cancel_outlined,
      'booking_confirmed' || 'payment' || 'payment_received' =>
        Icons.payment_rounded,
      'journey_alert' || 'journey_alert_snooze' =>
        Icons.directions_bus_rounded,
      'ticket_uploaded' => Icons.confirmation_number_outlined,
      'announcement' || 'info' => Icons.campaign_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('dd MMM').format(dateTime);
  }
}

// ---------------------------------------------------------------------------
// Shimmer placeholder for loading state
// ---------------------------------------------------------------------------

class _NotificationShimmer extends StatelessWidget {
  const _NotificationShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.border.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 32,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.border.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusSm,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  height: 12,
                  width: MediaQuery.of(context).size.width * 0.6,
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusSm,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

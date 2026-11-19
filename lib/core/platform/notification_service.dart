import 'dart:async';

/// Shared-preferences key holding the last FCM token registered with the
/// backend. Logout reads it to unregister the device before auth tokens are
/// cleared, so a signed-out phone stops receiving that account's pushes.
const String kDeviceTokenPrefsKey = 'katisha_device_token_v1';

/// Data class representing a push notification payload.
class NotificationPayload {
  final String title;
  final String body;
  final String? type;
  final String? entityId;

  const NotificationPayload({
    required this.title,
    required this.body,
    this.type,
    this.entityId,
  });

  factory NotificationPayload.fromMap(Map<String, dynamic> map) {
    return NotificationPayload(
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String?,
      entityId: map['entity_id'] as String?,
    );
  }
}

/// Abstract interface for all notification-related platform capabilities.
///
/// Implementations live in `core/platform/` per platform. No other part of the
/// codebase should import `flutter_local_notifications` or `firebase_messaging`
/// directly — they must go through this abstraction.
abstract class NotificationService {
  /// Initializes push notification infrastructure (FCM, local notifications).
  ///
  /// [requestPermissions] is false for background/action entry points, where
  /// prompting the user would be inappropriate.
  Future<void> initialize({bool requestPermissions = true});

  /// Returns the FCM device token for registration with the backend.
  Future<String?> getDeviceToken();

  /// Emits a fresh FCM token whenever Firebase rotates it. The backend must be
  /// updated or the device silently stops receiving push notifications.
  Stream<String> get onDeviceTokenRefresh;

  /// Requests notification permission from the user.
  /// Returns true if permission was granted.
  Future<bool> requestPermission();

  /// Current OS permission state, without prompting.
  ///
  /// `true` means alerts can be shown, `false` means the user (or the OS) has
  /// blocked them, and `null` means the platform could not be queried.
  Future<bool?> notificationsEnabled();

  /// Schedules the most urgent (30-minute) departure reminder.
  Future<void> scheduleJourneyAlert({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  });

  /// Schedules loud, snooze-to-dismiss local notifications 2 hours, 1 hour, and
  /// 30 minutes before [departureTime].
  Future<void> scheduleJourneyAlerts({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  });

  /// Shows an immediate notification with sound and vibration.
  ///
  /// Set [alarm] for alerts the recipient must act on (field-agent alerts):
  /// those use the loud, pinned "Action Required" channel with Open/Dismiss
  /// actions instead of the regular booking channel.
  Future<void> showImmediateAlert({
    required String title,
    required String body,
    required String type,
    String? entityId,
    bool alarm = false,
  });

  /// Cancels a previously scheduled journey alert by booking ID.
  Future<void> cancelJourneyAlert(String bookingId);

  /// Handles a snooze action — reschedules the alert for 5 minutes later.
  Future<void> handleSnooze(String bookingId);

  /// Stream that emits when a notification is tapped (for deep linking).
  Stream<NotificationPayload> get onNotificationTapped;

  /// Stream that emits when a journey alert fires in the foreground.
  Stream<NotificationPayload> get onForegroundAlert;
}

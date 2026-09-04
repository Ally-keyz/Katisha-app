import 'dart:async';

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
  Future<void> initialize();

  /// Returns the FCM device token for registration with the backend.
  Future<String?> getDeviceToken();

  /// Requests notification permission from the user.
  /// Returns true if permission was granted.
  Future<bool> requestPermission();

  /// Schedules a local notification 10 minutes before [departureTime].
  Future<void> scheduleJourneyAlert({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  });

  /// Schedules local notifications 30 and 10 minutes before [departureTime].
  Future<void> scheduleJourneyAlerts({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  });

  /// Shows an immediate notification with sound and vibration.
  Future<void> showImmediateAlert({
    required String title,
    required String body,
    required String type,
    String? entityId,
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

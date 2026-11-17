import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'notification_service.dart';

/// Departure alerts are deliberately loud and intrusive: one hour, thirty
/// minutes, and twenty minutes before departure. They stay on the lock screen
/// until the traveller snoozes them.
const List<int> _kAlertOffsetsMinutes = [60, 30, 20];
const int _kMaxSnoozeCount = 3;
const int _kSnoozeMinutes = 5;
const String _kSnoozePrefix = 'snooze_';
const String _kSnoozeActionId = 'snooze';
const String _kJourneyChannelId = 'Katisha_journey_alerts_v2';
const String _kBookingChannelId = 'Katisha_booking_alerts_v2';

/// White silhouette drawable used as the Android status-bar icon. Mipmap
/// launcher icons are not valid notification small icons (adaptive icons can
/// make the notification fail to render at all).
const String _kSmallIcon = 'ic_stat_katisha';

class NotificationServiceImpl implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferences _prefs;

  final _notificationTappedController =
      StreamController<NotificationPayload>.broadcast();
  final _foregroundAlertController =
      StreamController<NotificationPayload>.broadcast();

  late final AndroidNotificationDetails _journeyAndroidDetails;
  late final AndroidNotificationDetails _bookingAndroidDetails;
  late final DarwinNotificationDetails _journeyIOSDetails;
  late final DarwinNotificationDetails _bookingIOSDetails;
  late final NotificationDetails _journeyNotificationDetails;
  late final NotificationDetails _bookingNotificationDetails;

  NotificationServiceImpl({
    required FlutterLocalNotificationsPlugin plugin,
    required SharedPreferences prefs,
  })  : _plugin = plugin,
        _prefs = prefs {
    _journeyAndroidDetails = AndroidNotificationDetails(
      _kJourneyChannelId,
      'Departure Alerts',
      channelDescription:
          'Loud reminders one hour, thirty minutes, and twenty minutes before departure',
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'Departure Alert',
      icon: _kSmallIcon,
      sound: const RawResourceAndroidNotificationSound('notification'),
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 900, 450, 900]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      // Ongoing + non-auto-cancel keeps the alert pinned until the traveller
      // explicitly snoozes it.
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      actions: const [
        AndroidNotificationAction(
          _kSnoozeActionId,
          'Snooze 5 min',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    _bookingAndroidDetails = AndroidNotificationDetails(
      _kBookingChannelId,
      'Booking Alerts',
      channelDescription:
          'Notifications for new bookings, ticket issuance, and payment confirmations',
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'Booking Alert',
      icon: _kSmallIcon,
      sound: const RawResourceAndroidNotificationSound('notification'),
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 500, 250, 500]),
      visibility: NotificationVisibility.public,
    );
    _journeyIOSDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'journey_alert',
    );
    _bookingIOSDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.active,
    );
    _journeyNotificationDetails = NotificationDetails(
      android: _journeyAndroidDetails,
      iOS: _journeyIOSDetails,
    );
    _bookingNotificationDetails = NotificationDetails(
      android: _bookingAndroidDetails,
      iOS: _bookingIOSDetails,
    );
  }

  /// The plugin, timezone database and Android channels only need to be set up
  /// once. [initialize] can be reached from app startup, the login flow and the
  /// background snooze handler, so the work is memoized to avoid racing two
  /// initializations (which could swallow the permission prompt).
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings(_kSmallIcon);
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'journey_alert',
          actions: [
            DarwinNotificationAction.plain(
              _kSnoozeActionId,
              'Snooze 5 min',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );
    final settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final actionId = response.actionId;
        final payload = response.payload;
        if (payload != null) {
          final data = _parsePayload(payload);
          final bookingId = data['entity_id'];
          if (actionId == _kSnoozeActionId &&
              bookingId != null &&
              bookingId.isNotEmpty) {
            // The action is handled without opening the app on Android; on iOS
            // it arrives here. Either way, reschedule the alert quietly.
            unawaited(handleSnooze(bookingId));
            return;
          }
          _notificationTappedController.add(
            NotificationPayload.fromMap(data),
          );
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          notificationTapBackground,
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kJourneyChannelId,
          'Departure Alerts',
          description:
              'Loud reminders one hour, thirty minutes, and twenty minutes before departure',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kBookingChannelId,
          'Booking Alerts',
          description:
              'Notifications for new bookings, ticket issuance, and payment confirmations',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
  }

  @override
  Future<void> initialize({bool requestPermissions = true}) async {
    await _ensureInitialized();
    if (requestPermissions && Platform.isAndroid) {
      await requestPermission();
    } else if (requestPermissions && Platform.isIOS) {
      // Permission is requested explicitly from [requestPermission] during the
      // login flow, so don't prompt during background initialization.
    }
  }

  @override
  Future<String?> getDeviceToken() async {
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      // Never prompt before the plugin is ready — the request would be lost and
      // Android 13+ would keep suppressing every notification.
      await _ensureInitialized();
    } catch (_) {
      return false;
    }

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          final granted = await androidPlugin.requestNotificationsPermission();
          return granted ?? false;
        } catch (_) {
          return false;
        }
      }
    } else if (Platform.isIOS) {
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        try {
          // Do not request `critical` here: critical alerts require a special
          // Apple entitlement and asking for it without one makes the whole
          // authorization request fail on iOS.
          final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }

  @override
  Future<void> scheduleJourneyAlert({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  }) async {
    // A single-alert caller still receives the most urgent reminder.
    await _scheduleJourneyAlertAt(
      bookingId: bookingId,
      routeName: routeName,
      departureTime: departureTime,
      minutesBefore: 20,
    );
  }

  @override
  Future<void> scheduleJourneyAlerts({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  }) async {
    // Replacing the schedule must also drop any alert from a previous booking
    // state and reset the snooze budget.
    await cancelJourneyAlert(bookingId);
    for (final minutes in _kAlertOffsetsMinutes) {
      await _scheduleJourneyAlertAt(
        bookingId: bookingId,
        routeName: routeName,
        departureTime: departureTime,
        minutesBefore: minutes,
      );
    }
  }

  Future<void> _scheduleJourneyAlertAt({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
    required int minutesBefore,
  }) async {
    final scheduledTime =
        departureTime.subtract(Duration(minutes: minutesBefore));

    if (scheduledTime.isBefore(DateTime.now())) {
      return;
    }

    final title = minutesBefore >= 60
        ? 'Your journey starts in 1 hour'
        : 'Your journey starts in $minutesBefore minutes';
    final payload = _encodePayload({
      'title': title,
      'body': 'Route: $routeName. Snooze to dismiss this alert.',
      'type': 'journey_alert',
      'entity_id': bookingId,
      'minutes_before': minutesBefore,
    });

    final notificationId =
        _bookingToNotificationId(bookingId) + minutesBefore;
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      notificationId,
      title,
      'Route: $routeName. Snooze to dismiss this alert.',
      tzScheduledTime,
      _journeyNotificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancelJourneyAlert(String bookingId) async {
    for (final minutes in _kAlertOffsetsMinutes) {
      await _plugin.cancel(_bookingToNotificationId(bookingId) + minutes);
    }
    await _plugin.cancel(_bookingToNotificationId(bookingId) + _kSnoozeMinutes);
    await _resetSnoozeCount(bookingId);
  }

  @override
  Future<void> showImmediateAlert({
    required String title,
    required String body,
    required String type,
    String? entityId,
  }) async {
    final payload = _encodePayload({
      'title': title,
      'body': body,
      'type': type,
      'entity_id': entityId ?? '',
    });

    final notificationId =
        DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _plugin.show(
      notificationId,
      title,
      body,
      _bookingNotificationDetails,
      payload: payload,
    );
  }

  @override
  Future<void> handleSnooze(String bookingId) async {
    final currentCount = _getSnoozeCount(bookingId);
    if (currentCount >= _kMaxSnoozeCount) {
      // Final snooze budget spent: clear the pinned alert so it can't linger
      // forever. The next real departure alert will still fire.
      await _plugin.cancel(
        _bookingToNotificationId(bookingId) + _kSnoozeMinutes,
      );
      return;
    }

    final newCount = currentCount + 1;
    await _prefs.setInt('$_kSnoozePrefix$bookingId', newCount);

    final snoozeTime =
        DateTime.now().add(const Duration(minutes: _kSnoozeMinutes));
    final notificationId =
        _bookingToNotificationId(bookingId) + _kSnoozeMinutes;
    final title = 'Snoozed departure alert';
    final body =
        'Your journey departs soon. This alert will repeat in $_kSnoozeMinutes minutes ($newCount/$_kMaxSnoozeCount).';
    final payload = _encodePayload({
      'title': title,
      'body': body,
      'type': 'journey_alert_snooze',
      'entity_id': bookingId,
    });
    final tzSnoozeTime = tz.TZDateTime.from(snoozeTime, tz.local);

    await _plugin.zonedSchedule(
      notificationId,
      title,
      body,
      tzSnoozeTime,
      _journeyNotificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Stream<NotificationPayload> get onNotificationTapped =>
      _notificationTappedController.stream;

  @override
  Stream<NotificationPayload> get onForegroundAlert =>
      _foregroundAlertController.stream;

  void dispose() {
    _notificationTappedController.close();
    _foregroundAlertController.close();
  }

  int _getSnoozeCount(String bookingId) {
    return _prefs.getInt('$_kSnoozePrefix$bookingId') ?? 0;
  }

  Future<void> _resetSnoozeCount(String bookingId) async {
    await _prefs.remove('$_kSnoozePrefix$bookingId');
  }

  int _bookingToNotificationId(String bookingId) {
    return bookingId.hashCode & 0x7FFFFFFF;
  }

  String _encodePayload(Map<String, dynamic> data) {
    return data.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
  }

  Map<String, String> _parsePayload(String encoded) {
    return Uri.splitQueryString(encoded);
  }
}

/// Handles notification actions while the app is terminated or in the
/// background. Must be a top-level function for the plugin's entry point.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.actionId != _kSnoozeActionId) return;
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  final data = Uri.splitQueryString(payload);
  final bookingId = data['entity_id'];
  if (bookingId == null || bookingId.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final service = NotificationServiceImpl(
      plugin: FlutterLocalNotificationsPlugin(),
      prefs: prefs,
    );
    await service.initialize(requestPermissions: false);
    await service.handleSnooze(bookingId);
  } catch (_) {
    // The action is best-effort; the scheduled alerts remain in place.
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'notification_service.dart';

const _kMaxSnoozeCount = 3;
const _kSnoozeMinutes = 5;
const _kAlertOffsetMinutes = 10;
const _kEarlyAlertOffsetMinutes = 30;
const _kSnoozePrefix = 'snooze_';

class NotificationServiceImpl implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferences _prefs;

  final _notificationTappedController =
      StreamController<NotificationPayload>.broadcast();
  final _foregroundAlertController =
      StreamController<NotificationPayload>.broadcast();

  late final AndroidNotificationDetails _androidDetails;
  late final AndroidNotificationDetails _bookingAndroidDetails;
  late final DarwinNotificationDetails _iOSDetails;
  late final NotificationDetails _notificationDetails;
  late final NotificationDetails _bookingNotificationDetails;

  NotificationServiceImpl({
    required FlutterLocalNotificationsPlugin plugin,
    required SharedPreferences prefs,
  })  : _plugin = plugin,
        _prefs = prefs {
    _androidDetails = const AndroidNotificationDetails(
      'Katisha_journey_alerts',
      'Journey Alerts',
      channelDescription: 'Notifications for upcoming journey departures',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Journey Alert',
      icon: '@mipmap/ic_launcher',
      sound: RawResourceAndroidNotificationSound('notification'),
      enableVibration: true,
    );
    _bookingAndroidDetails = const AndroidNotificationDetails(
      'Katisha_booking_alerts',
      'Booking Alerts',
      channelDescription: 'Notifications for new bookings and payment confirmations',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Booking Alert',
      icon: '@mipmap/ic_launcher',
      sound: RawResourceAndroidNotificationSound('notification'),
      enableVibration: true,
    );
    _iOSDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    _notificationDetails = NotificationDetails(
      android: _androidDetails,
      iOS: _iOSDetails,
    );
    _bookingNotificationDetails = NotificationDetails(
      android: _bookingAndroidDetails,
      iOS: _iOSDetails,
    );
  }

  @override
  Future<void> initialize() async {
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) {
          _notificationTappedController.add(
            NotificationPayload.fromMap(
              _parsePayload(payload),
            ),
          );
        }
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'Katisha_journey_alerts',
          'Journey Alerts',
          description: 'Notifications for upcoming journey departures',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'Katisha_booking_alerts',
          'Booking Alerts',
          description: 'Notifications for new bookings and payment confirmations',
          importance: Importance.high,
          enableVibration: true,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  @override
  Future<String?> getDeviceToken() async {
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        return granted ?? false;
      }
    } else if (Platform.isIOS) {
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
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
    await _scheduleJourneyAlertAt(
      bookingId: bookingId,
      routeName: routeName,
      departureTime: departureTime,
      minutesBefore: _kAlertOffsetMinutes,
      title: 'Your journey starts in $_kAlertOffsetMinutes minutes',
    );
  }

  @override
  Future<void> scheduleJourneyAlerts({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  }) async {
    await _scheduleJourneyAlertAt(
      bookingId: bookingId,
      routeName: routeName,
      departureTime: departureTime,
      minutesBefore: _kEarlyAlertOffsetMinutes,
      title: 'Your journey starts in $_kEarlyAlertOffsetMinutes minutes',
    );
    await _scheduleJourneyAlertAt(
      bookingId: bookingId,
      routeName: routeName,
      departureTime: departureTime,
      minutesBefore: _kAlertOffsetMinutes,
      title: 'Your journey starts in $_kAlertOffsetMinutes minutes',
    );
    await _resetSnoozeCount(bookingId);
  }

  Future<void> _scheduleJourneyAlertAt({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
    required int minutesBefore,
    required String title,
  }) async {
    final scheduledTime =
        departureTime.subtract(Duration(minutes: minutesBefore));

    if (scheduledTime.isBefore(DateTime.now())) {
      return;
    }

    final payload = _encodePayload({
      'title': title,
      'body': 'Route: $routeName',
      'type': 'journey_alert',
      'entity_id': bookingId,
    });

    final notificationId =
        _bookingToNotificationId(bookingId) + minutesBefore;
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      notificationId,
      title,
      'Route: $routeName',
      tzScheduledTime,
      _notificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancelJourneyAlert(String bookingId) async {
    await _plugin.cancel(_bookingToNotificationId(bookingId) + _kEarlyAlertOffsetMinutes);
    await _plugin.cancel(_bookingToNotificationId(bookingId) + _kAlertOffsetMinutes);
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

    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

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
      return;
    }

    final newCount = currentCount + 1;
    await _prefs.setInt('$_kSnoozePrefix$bookingId', newCount);

    final snoozeTime =
        DateTime.now().add(const Duration(minutes: _kSnoozeMinutes));
    final notificationId =
        _bookingToNotificationId(bookingId) + _kAlertOffsetMinutes;
    final payload = _encodePayload({
      'title': 'Snoozed Journey Alert',
      'body': 'Your journey departs soon. Snooze $newCount/$_kMaxSnoozeCount',
      'type': 'journey_alert_snooze',
      'entity_id': bookingId,
    });
    final tzSnoozeTime = tz.TZDateTime.from(snoozeTime, tz.local);

    await _plugin.zonedSchedule(
      notificationId,
      'Snoozed Journey Alert',
      'Your journey departs soon. Snooze $newCount/$_kMaxSnoozeCount',
      tzSnoozeTime,
      _notificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
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
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
  }

  Map<String, String> _parsePayload(String encoded) {
    return Uri.splitQueryString(encoded);
  }
}

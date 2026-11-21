import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import 'notification_service.dart';

/// Departure alerts are deliberately loud and intrusive: two hours, one hour,
/// and thirty minutes before departure. They stay on the lock screen until the
/// traveller snoozes them.
const List<int> _kAlertOffsetsMinutes = [120, 60, 30];
const int _kMaxSnoozeCount = 3;
const int _kSnoozeMinutes = 5;
const String _kSnoozePrefix = 'snooze_';
const String _kSnoozeActionId = 'snooze';
const String _kOpenActionId = 'open_booking';
const String _kDismissAgentActionId = 'dismiss_agent_alert';
const String _kJourneyChannelId = 'Katisha_journey_alerts_v4';
const String _kBookingChannelId = 'Katisha_booking_alerts_v2';
const String _kAgentChannelId = 'Katisha_agent_alerts_v3';

/// White silhouette drawable used as the Android status-bar icon. Mipmap
/// launcher icons are not valid notification small icons (adaptive icons can
/// make the notification fail to render at all).
const String _kSmallIcon = 'ic_stat_katisha';

class NotificationServiceImpl implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferences _prefs;

  /// Local-notification action handlers run in a background isolate; wiring
  /// FCM there would create a second set of listeners for no benefit.
  final bool _firebaseEnabled;

  final _notificationTappedController =
      StreamController<NotificationPayload>.broadcast();
  final _foregroundAlertController =
      StreamController<NotificationPayload>.broadcast();
  final _deviceTokenRefreshController = StreamController<String>.broadcast();

  FirebaseMessaging? _messaging;
  bool _firebaseReady = false;
  StreamSubscription<RemoteMessage>? _fcmMessageSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;
  StreamSubscription<String>? _fcmTokenSub;
  NotificationPayload? _pendingInitialTap;
  bool _initialTapScheduled = false;

  /// The API emits both a Socket.IO event and an FCM push for the same
  /// notification. While the app is in the foreground both arrive; this short
  /// memory prevents the user seeing the same alert twice.
  static const Duration _dedupeWindow = Duration(seconds: 20);
  final Map<String, DateTime> _recentAlerts = {};

  /// Returns true when an alert for this type/entity was already shown within
  /// [_dedupeWindow]. Records the alert otherwise.
  bool _isDuplicate(String type, String? entityId, {String? title}) {
    final identity = (entityId != null && entityId.isNotEmpty)
        ? entityId
        : (title ?? '');
    final key = '$type|$identity';
    final now = DateTime.now();
    _recentAlerts.removeWhere((_, at) => now.difference(at) > _dedupeWindow);
    final last = _recentAlerts[key];
    if (last != null && now.difference(last) < _dedupeWindow) return true;
    _recentAlerts[key] = now;
    return false;
  }

  late final AndroidNotificationDetails _journeyAndroidDetails;
  late final AndroidNotificationDetails _bookingAndroidDetails;
  late final AndroidNotificationDetails _agentAndroidDetails;
  late final DarwinNotificationDetails _journeyIOSDetails;
  late final DarwinNotificationDetails _bookingIOSDetails;
  late final DarwinNotificationDetails _agentIOSDetails;
  late final NotificationDetails _journeyNotificationDetails;
  late final NotificationDetails _bookingNotificationDetails;
  late final NotificationDetails _agentNotificationDetails;

  NotificationServiceImpl({
    required FlutterLocalNotificationsPlugin plugin,
    required SharedPreferences prefs,
    bool firebaseEnabled = true,
  })  : _plugin = plugin,
        _prefs = prefs,
        _firebaseEnabled = firebaseEnabled {
    _journeyAndroidDetails = AndroidNotificationDetails(
      _kJourneyChannelId,
      'Departure Alerts',
      channelDescription:
          'Loud reminders two hours, one hour, and thirty minutes before departure',
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'Departure Alert',
      icon: _kSmallIcon,
      sound: const RawResourceAndroidNotificationSound('alarm_clock'),
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
    // Field-agent alarms: a new booking, a booking that has been paid, or a
    // booking that has been ignored for a day. Loud, pinned, and actionable so
    // it cannot be missed while the agent is at the counter.
    _agentAndroidDetails = AndroidNotificationDetails(
      _kAgentChannelId,
      'Action Required Alerts',
      channelDescription:
          'New bookings and bookings that still need the agent to act on them',
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'Action required',
      icon: _kSmallIcon,
      sound: const RawResourceAndroidNotificationSound('alarm_clock'),
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000, 500, 1000]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      actions: const [
        AndroidNotificationAction(
          _kOpenActionId,
          'Open',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _kDismissAgentActionId,
          'Dismiss',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
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
    _agentIOSDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'agent_alert',
    );
    _journeyNotificationDetails = NotificationDetails(
      android: _journeyAndroidDetails,
      iOS: _journeyIOSDetails,
    );
    _bookingNotificationDetails = NotificationDetails(
      android: _bookingAndroidDetails,
      iOS: _bookingIOSDetails,
    );
    _agentNotificationDetails = NotificationDetails(
      android: _agentAndroidDetails,
      iOS: _agentIOSDetails,
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
        DarwinNotificationCategory(
          'agent_alert',
          actions: [
            DarwinNotificationAction.plain(
              _kOpenActionId,
              'Open booking',
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
          // A dismissed agent alarm should not open the app.
          if (actionId == _kDismissAgentActionId) return;
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
              'Loud reminders two hours, one hour, and thirty minutes before departure',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_clock'),
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
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kAgentChannelId,
          'Action Required Alerts',
          description:
              'New bookings and bookings that still need the agent to act on them',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_clock'),
          enableVibration: true,
        ),
      );
    }

    // FCM is optional: without google-services.json (or on a platform where
    // Firebase is not configured) local notifications keep working and push
    // simply stays off.
    if (_firebaseEnabled) {
      await _initFirebaseMessaging();
    }
  }

  /// Wires Firebase Cloud Messaging so the app is woken for alerts even when it
  /// is backgrounded or closed.
  Future<void> _initFirebaseMessaging() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      _firebaseReady = true;

      await messaging.setAutoInitEnabled(true);
      // Foreground messages are drawn by our own local notification so they
      // match the in-app alert style. Letting iOS also present them would show
      // every alert twice.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      _fcmMessageSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp
          .listen(_handleMessageOpened);
      // `getToken` is the registration token the Admin SDK sends to. The new
      // `register()` API yields a Firebase Installation ID, which firebase-admin
      // cannot target, so the deprecated token APIs remain the correct choice.
      // ignore: deprecated_member_use
      _fcmTokenSub = messaging.onTokenRefresh.listen((token) {
        if (!_deviceTokenRefreshController.isClosed) {
          _deviceTokenRefreshController.add(token);
        }
      });

      // Tapping a notification that launched the app from a terminated state.
      // The tap stream has no listener yet, so hold it until one attaches.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _pendingInitialTap = _payloadFromMessage(initial);
        // The app may have finished starting while getInitialMessage ran; the
        // listener is already attached in that case.
        if (_notificationTappedController.hasListener) {
          _emitPendingInitialTap();
        }
      }
    } catch (error) {
      _firebaseReady = false;
      _messaging = null;
      debugPrint('[Notifications] Firebase is unavailable: $error');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final payload = _payloadFromMessage(message);
    if (payload.title.isEmpty && payload.body.isEmpty) return;
    if (!_foregroundAlertController.isClosed) {
      _foregroundAlertController.add(payload);
    }
    unawaited(_showRemoteAlert(payload));
  }

  Future<void> _showRemoteAlert(NotificationPayload payload) async {
    if (_isDuplicate(
      payload.type ?? 'notification',
      payload.entityId,
      title: payload.title,
    )) {
      return;
    }
    // Action-required pushes (field-agent alerts) use the loud pinned channel
    // even when they arrive as a foreground FCM message.
    final actionable = const {
      'new_booking',
      'booking_paid',
      'agent_reminder',
    }.contains(payload.type);

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        payload.title.isEmpty ? 'Katisha' : payload.title,
        payload.body,
        actionable ? _agentNotificationDetails : _bookingNotificationDetails,
        payload: _encodePayload({
          'title': payload.title,
          'body': payload.body,
          'type': payload.type ?? 'notification',
          'entity_id': payload.entityId ?? '',
        }),
      );
    } catch (error) {
      debugPrint('[Notifications] Could not show push alert: $error');
    }
  }

  void _handleMessageOpened(RemoteMessage message) {
    if (_notificationTappedController.isClosed) return;
    _notificationTappedController.add(_payloadFromMessage(message));
  }

  NotificationPayload _payloadFromMessage(RemoteMessage message) {
    final data = message.data;
    final title = (data['title'] ?? message.notification?.title ?? '').toString();
    final body = (data['body'] ?? message.notification?.body ?? '').toString();
    final type = (data['type'] ?? 'notification').toString();
    final rawId = (data['entity_id'] ?? data['bookingId'] ?? '').toString();
    return NotificationPayload(
      title: title.isEmpty ? 'Katisha' : title,
      body: body,
      type: type,
      entityId: rawId.isEmpty ? null : rawId,
    );
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
    try {
      await _ensureInitialized();
      if (!_firebaseReady) return null;
      // ignore: deprecated_member_use
      final token = await _messaging?.getToken();
      if (token == null || token.isEmpty) return null;
      // Persist so logout can unregister the exact token even after the auth
      // session has been cleared from memory.
      await _prefs.setString(kDeviceTokenPrefsKey, token);
      return token;
    } catch (error) {
      debugPrint('[Notifications] Could not read FCM token: $error');
      return null;
    }
  }

  @override
  Stream<String> get onDeviceTokenRefresh =>
      _deviceTokenRefreshController.stream;

  /// Requests the token again the moment permission is granted and hands it to
  /// the app so it can register the device with the API. Without this, a
  /// session restored before the prompt could keep a null token until the next
  /// cold start, silently disabling background push on iOS (APNs only issues a
  /// token after the user allows notifications).
  void _syncDeviceTokenAfterPermission() {
    unawaited(_retryDeviceTokenSync());
  }

  Future<void> _retryDeviceTokenSync() async {
    // iOS can take a few seconds after the prompt to hand out the APNs token,
    // which FCM needs before it can mint a registration token.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      final token = await getDeviceToken();
      if (token == null || token.isEmpty) continue;
      if (!_deviceTokenRefreshController.isClosed) {
        _deviceTokenRefreshController.add(token);
      }
      return;
    }
  }

  bool _permissionResult(bool granted) {
    if (granted) _syncDeviceTokenAfterPermission();
    return granted;
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

    // FCM requests the same OS permission. Using it first keeps the iOS APNs
    // registration in sync with the prompt (without permission iOS never issues
    // an APNs token, so FCM would keep returning a null device token).
    if (_firebaseReady) {
      try {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        final status = settings.authorizationStatus;
        if (status == AuthorizationStatus.authorized ||
            status == AuthorizationStatus.provisional) {
          return _permissionResult(true);
        }
        if (status == AuthorizationStatus.denied) return false;
      } catch (error) {
        debugPrint('[Notifications] FCM permission request failed: $error');
      }
    }

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          final granted = await androidPlugin.requestNotificationsPermission();
          return _permissionResult(granted ?? false);
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
          return _permissionResult(granted ?? false);
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }

  @override
  Future<bool?> notificationsEnabled() async {
    try {
      await _ensureInitialized();
    } catch (_) {
      return null;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        return await androidPlugin?.areNotificationsEnabled();
      } catch (_) {
        return null;
      }
    } else if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      try {
        final options = await iosPlugin?.checkPermissions();
        if (options == null) return null;
        return options.isEnabled || options.isProvisionalEnabled;
      } catch (_) {
        return null;
      }
    }
    return null;
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
      minutesBefore: 30,
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

    final title = minutesBefore >= 120
        ? 'Your journey starts in 2 hours'
        : minutesBefore >= 60
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

    // Exact alarms can be refused when the user has not granted "Alarms &
    // reminders" (Android 12+). Falling back to an inexact alarm still delivers
    // the reminder instead of losing it entirely.
    try {
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
    } catch (error) {
      debugPrint('[Notifications] Exact departure alarm refused: $error');
      try {
        await _plugin.zonedSchedule(
          notificationId,
          title,
          'Route: $routeName. Snooze to dismiss this alert.',
          tzScheduledTime,
          _journeyNotificationDetails,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (fallbackError) {
        debugPrint(
          '[Notifications] Departure alarm could not be scheduled: $fallbackError',
        );
      }
    }
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
    bool alarm = false,
  }) async {
    if (_isDuplicate(type, entityId, title: title)) return;

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
      alarm ? _agentNotificationDetails : _bookingNotificationDetails,
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

    try {
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
    } catch (_) {
      // See _scheduleJourneyAlertAt: inexact delivery beats a lost alarm.
      try {
        await _plugin.zonedSchedule(
          notificationId,
          title,
          body,
          tzSnoozeTime,
          _journeyNotificationDetails,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (error) {
        debugPrint('[Notifications] Snooze alarm failed: $error');
      }
    }
  }

  @override
  Stream<NotificationPayload> get onNotificationTapped {
    // A push that launched the app from a terminated state is only known after
    // Firebase initializes; replay it once a listener attaches.
    _emitPendingInitialTap();
    return _notificationTappedController.stream;
  }

  void _emitPendingInitialTap() {
    if (_pendingInitialTap == null || _initialTapScheduled) return;
    _initialTapScheduled = true;
    scheduleMicrotask(() {
      final payload = _pendingInitialTap;
      _pendingInitialTap = null;
      if (payload != null && !_notificationTappedController.isClosed) {
        _notificationTappedController.add(payload);
      }
    });
  }

  @override
  Stream<NotificationPayload> get onForegroundAlert =>
      _foregroundAlertController.stream;

  void dispose() {
    _fcmMessageSub?.cancel();
    _fcmOpenedSub?.cancel();
    _fcmTokenSub?.cancel();
    _notificationTappedController.close();
    _foregroundAlertController.close();
    _deviceTokenRefreshController.close();
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

  @override
  Future<NotificationPayload?> getLaunchNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details?.notificationResponse?.payload;
    if (payload == null || payload.isEmpty) return null;
    return NotificationPayload.fromMap(_parsePayload(payload));
  }

  Map<String, String> _parsePayload(String encoded) {
    return Uri.splitQueryString(encoded);
  }
}

/// Handles notification actions while the app is terminated or in the
/// background. Must be a top-level function for the plugin's entry point.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // The plugin's background engine creates a bare FlutterEngine without
  // registering shared_preferences / flutter_local_notifications. Calling
  // SharedPreferences.getInstance() or plugin.initialize() here threw
  // "getResources() on a null object reference" and the snooze was silently
  // lost. Keep this callback plugin-free: taps that launch the app are handled
  // at startup via getLaunchNotification(), and taps while running use the
  // in-isolate onDidReceiveNotificationResponse callback.
  debugPrint('[Notifications] background tap: ${response.payload ?? ''}');
}

/// Registers the top-level FCM background handler. Must run in `main()` before
/// `runApp` so messages received while the app is killed are delivered.
void registerFirebaseBackgroundHandler() {
  // FCM background delivery only exists on mobile; desktop/web runs of the app
  // (developer tooling) must not hit an unsupported-platform exception.
  if (!Platform.isAndroid && !Platform.isIOS) return;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}

/// Handles FCM messages while the app is in the background or terminated.
///
/// Messages sent by the API include a `notification` block, which Android and
/// iOS display themselves. Only data-only messages need to be rendered here
/// (for example a silent data push that should still surface to the user).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Firebase may not be configured on every platform; the OS still displays
    // notification-block messages without it.
  }

  // Server pushes always include a `notification` block, which Android and iOS
  // render themselves even when the app process is dead. That is the reliable
  // killed-state path; it needs the POST_NOTIFICATIONS permission and a
  // registered FCM token, both of which are now requested after guest checkout.
  if (message.notification != null) return;

  // Data-only pushes used to call FlutterLocalNotificationsPlugin.initialize()
  // and SharedPreferences here. Neither plugin is registered in FCM's background
  // isolate, so initialize() crashed with "getResources() on a null object
  // reference" and the catch block swallowed the message. Rendering a data-only
  // push needs a registered background engine, so simply skip it — the server
  // does not send data-only notifications.
  debugPrint('[Push] data-only message ignored in background isolate: '
      '${message.data}');
}

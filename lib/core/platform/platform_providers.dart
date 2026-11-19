import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/socket_service.dart';
import '../network/socket_service_impl.dart';
import 'file_service.dart';
import 'file_service_impl.dart';
import 'local_notification_store.dart';
import 'local_ticket_store.dart';
import 'notification_service.dart';
import 'notification_service_impl.dart';
import 'sound_service.dart';

/// Lazy default providers — overridden at startup for notification & socket.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return _NoOpNotificationService();
});

/// App-wide SharedPreferences instance, overridden at startup.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('sharedPreferencesProvider must be overridden');
});

final localNotificationStoreProvider = Provider<LocalNotificationStore>((ref) {
  throw StateError('localNotificationStoreProvider must be overridden');
});

final localTicketStoreProvider = Provider<LocalTicketStore>((ref) {
  throw StateError('localTicketStoreProvider must be overridden');
});

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  ref.onDispose(service.dispose);
  return service;
});

final fileServiceProvider = Provider<FileService>((ref) {
  return FileServiceImpl();
});

/// Initializes notification service, socket service, and returns proper
/// Riverpod overrides to inject into ProviderScope.
///
/// The notification plugin's initialization (timezone data, channel creation,
/// permission prompt) is kicked off in the background rather than awaited, so
/// the first frame / splash screen renders immediately and the app feels fast
/// to open.
Future<List<Override>> createAppOverrides() async {
  final plugin = FlutterLocalNotificationsPlugin();
  final prefs = await SharedPreferences.getInstance();
  final notificationService = NotificationServiceImpl(plugin: plugin, prefs: prefs);
  unawaited(_initializeNotifications(notificationService));

  final localStore = LocalNotificationStore(prefs);
  final localTicketStore = LocalTicketStore(prefs);

  final socketService = SocketServiceImpl();

  return [
    notificationServiceProvider.overrideWith((ref) {
      ref.onDispose(notificationService.dispose);
      return notificationService;
    }),
    localNotificationStoreProvider.overrideWithValue(localStore),
    localTicketStoreProvider.overrideWithValue(localTicketStore),
    sharedPreferencesProvider.overrideWithValue(prefs),
    socketServiceProvider.overrideWith((ref) {
      ref.onDispose(socketService.dispose);
      return socketService;
    }),
  ];
}

/// Runs notification setup in the background so it never blocks app startup.
Future<void> _initializeNotifications(NotificationServiceImpl service) async {
  try {
    // Permission is requested deliberately during login instead of at cold
    // start, so the app never fires a system prompt before the user acts.
    await service.initialize(requestPermissions: false);
  } catch (_) {
    // Never let background notification setup crash or delay the app.
  }
}

/// No-op fallback used when real service isn't initialized.
class _NoOpNotificationService implements NotificationService {
  @override
  Future<void> initialize({bool requestPermissions = true}) async {}
  @override
  Future<String?> getDeviceToken() async => null;
  @override
  Stream<String> get onDeviceTokenRefresh => const Stream.empty();
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool?> notificationsEnabled() async => null;
  @override
  Future<void> scheduleJourneyAlert({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  }) async {}
  @override
  Future<void> scheduleJourneyAlerts({
    required String bookingId,
    required String routeName,
    required DateTime departureTime,
  }) async {}
  @override
  Future<void> cancelJourneyAlert(String bookingId) async {}
  @override
  Future<void> showImmediateAlert({
    required String title,
    required String body,
    required String type,
    String? entityId,
    bool alarm = false,
  }) async {}
  @override
  Future<void> handleSnooze(String bookingId) async {}
  @override
  Stream<NotificationPayload> get onNotificationTapped =>
      const Stream.empty();
  @override
  Stream<NotificationPayload> get onForegroundAlert =>
      const Stream.empty();
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session.dart';
import 'core/network/api_client.dart';
import 'core/network/socket_service.dart';
import 'core/platform/badge_counts.dart';
import 'core/platform/notification_service.dart';
import 'core/platform/notification_service_impl.dart';
import 'core/platform/platform_providers.dart';
import 'core/platform/ticket_sync_service.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be registered before runApp so a message that arrives while the app
  // is terminated still reaches the background handler.
  registerFirebaseBackgroundHandler();

  // Cap the decoded-image cache so ticket PNGs and UI images can't balloon
  // memory. Every screen decodes at its render size (see the `cacheWidth` /
  // `memCacheWidth` arguments), so ~40 MB is several screens' worth of
  // bitmaps; anything above that just keeps stale photos alive.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 200;

  // White system bars with dark status-bar icons: the clock, signal and battery
  // sit on white app chrome, so the icons have to be dark to stay readable.
  // Screens with their own dark artwork (the welcome page) override this with
  // their own AnnotatedRegion.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final overrides = await createAppOverrides();

  // Resolve the stored/device locale before the first frame so the very first
  // build already uses the correct language. Otherwise the app briefly starts
  // with systemLocale() and any modal opened in that window (e.g. the booking
  // destination picker) renders its strings in the wrong language until it is
  // reopened.
  final initialLocale = await LanguagePreference.getLocale();
  overrides.add(appLocaleProvider.overrideWith((ref) => initialLocale));

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const KatishaApp(),
    ),
  );
}

class KatishaApp extends ConsumerStatefulWidget {
  const KatishaApp({super.key});

  @override
  ConsumerState<KatishaApp> createState() => _KatishaAppState();
}

class _KatishaAppState extends ConsumerState<KatishaApp>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationPayload>? _notificationTapSub;
  StreamSubscription<SocketEvent>? _socketEventSub;
  StreamSubscription<SessionUser?>? _sessionSub;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _registeredDeviceToken;
  SessionUser? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotificationTapListener();
    _setupDeviceTokenSync();
    _setupSessionAndSocket();
  }

  /// Refresh the offline ticket cache when the app comes back to the
  /// foreground. A ticket issued while the app was backgrounded is then saved
  /// (JSON + image) as soon as the user returns, before they ever open it.
  /// [TicketSyncService] throttles repeats, so quick app switches are cheap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final user = _session;
    if (user == null || user.isAgent) return;
    unawaited(ref.read(ticketSyncServiceProvider).syncAllTickets());
  }

  void _setupNotificationTapListener() {
    final notificationService = ref.read(notificationServiceProvider);
    _notificationTapSub =
        notificationService.onNotificationTapped.listen((payload) {
      if (!mounted) return;
      final router = ref.read(appRouterProvider);
      _handleNotificationNavigation(router, payload);
    });
  }

  /// Keeps the backend's copy of this device's FCM token current.
  void _setupDeviceTokenSync() {
    _tokenRefreshSub =
        ref.read(notificationServiceProvider).onDeviceTokenRefresh.listen(
      (token) {
        unawaited(_registerDeviceToken(tokenOverride: token));
      },
    );
  }

  /// Sends the FCM token to the API so the server can push to this device.
  /// Safe to call repeatedly: the last token is remembered and re-registration
  /// is skipped unless Firebase rotated it.
  ///
  /// Both fetching the token and the HTTP call are retried briefly. On a cold
  /// start the network may not be ready yet, and iOS can still be waiting for
  /// its APNs token; giving up on the first attempt would leave the phone
  /// without background alerts until the next app launch.
  Future<void> _registerDeviceToken({String? tokenOverride}) async {
    if (_session == null) return;

    var token = tokenOverride;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        token ??= await ref
            .read(notificationServiceProvider)
            .getDeviceToken();
        if (token == null || token.isEmpty) {
          // Clear an empty override so the next attempt fetches a fresh token
          // instead of looping with the same useless value.
          token = null;
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
            continue;
          }
          return;
        }
        if (token == _registeredDeviceToken) return;

        await ref.read(apiClientProvider).post(
          '/auth/device-token',
          data: {
            'token': token,
            'platform': Platform.isIOS ? 'ios' : 'android',
          },
        );
        _registeredDeviceToken = token;
        await ref
            .read(sharedPreferencesProvider)
            .setString(kDeviceTokenPrefsKey, token);
        return;
      } catch (error) {
        // A failed registration must never interrupt the session.
        debugPrint('[Push] Device token registration failed: $error');
        if (attempt == 2) return;
        await Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
  }

  /// Connects the real-time socket whenever a session exists and tears it down
  /// on logout, so event subscriptions never outlive the account that owns
  /// them.
  void _setupSessionAndSocket() {
    _sessionSub = ref.read(sessionProvider.notifier).stream.listen(
          _onSessionChanged,
        );
    _onSessionChanged(ref.read(sessionProvider));
  }

  void _onSessionChanged(SessionUser? user) {
    _session = user;

    if (user == null) {
      _socketEventSub?.cancel();
      _socketEventSub = null;
      _registeredDeviceToken = null;
      ref.read(socketServiceProvider).disconnect();
      // The server unread count belongs to the previous account.
      unawaited(
        ref.read(badgeCountsProvider.notifier).refresh(useLocalUnread: true),
      );
      return;
    }

    final token = ref.read(apiClientProvider).accessToken;
    if (token == null || token.isEmpty) return;

    final socket = ref.read(socketServiceProvider);
    // Always make sure the handler is attached. Returning early when the socket
    // happened to be connected could leave `_socketEventSub` null (for example
    // after a logout/login cycle), which silently suppressed every device
    // notification for the rest of the session.
    _socketEventSub ??= socket.onEvent.listen(_handleSocketEvent);
    if (!socket.isConnected) {
      unawaited(socket.connect(token));
    }

    // Register this device for background push now that we have a session.
    unawaited(_registerDeviceToken());
  }

  void _handleSocketEvent(SocketEvent event) {
    if (!mounted) return;
    final data = event.data;
    if (data is! Map<String, dynamic>) return;

    final notificationService = ref.read(notificationServiceProvider);

    switch (event.name) {
      case 'new_booking':
        if (_session?.isAgent != true) return;
        final reference = data['referenceCode']?.toString() ?? '';
        final message = data['message']?.toString();
        final origin = data['origin']?.toString();
        final destination = data['destination']?.toString();
        final body = message ??
            (origin != null && destination != null
                ? 'New booking $reference · $origin → $destination'
                : 'A new booking is waiting for you.');
        unawaited(
          notificationService.showImmediateAlert(
            title: 'New booking${reference.isEmpty ? '' : ' · $reference'}',
            body: body,
            type: 'new_booking',
            entityId: data['bookingId']?.toString(),
            // A just-created booking is usually still unpaid, so it is shown as
            // a normal alert. The alarm fires the moment it is paid (below).
          ),
        );
        break;

      case 'booking_paid':
        // Only agents act on this: the passenger already has their ticket.
        if (_session?.isAgent != true) return;
        final reference = data['referenceCode']?.toString() ?? '';
        final origin = data['origin']?.toString();
        final destination = data['destination']?.toString();
        unawaited(
          notificationService.showImmediateAlert(
            title: 'Booking paid${reference.isEmpty ? '' : ' · $reference'}',
            body: origin != null && destination != null
                ? '$origin → $destination · Issue the physical ticket and upload its photo.'
                : 'A booking was paid. Issue the physical ticket and upload its photo.',
            type: 'booking_paid',
            entityId: data['bookingId']?.toString(),
            alarm: true,
          ),
        );
        break;

      case 'agent_reminder':
        // A booking has been ignored for a day: it was never confirmed as seen
        // or its ticket photo was never uploaded.
        if (_session?.isAgent != true) return;
        final reference = data['referenceCode']?.toString() ?? '';
        final message = data['message']?.toString();
        unawaited(
          notificationService.showImmediateAlert(
            title: 'Booking needs attention${reference.isEmpty ? '' : ' · $reference'}',
            body: message ??
                'A booking has been waiting for your action for over 24 hours.',
            type: 'agent_reminder',
            entityId: data['bookingId']?.toString(),
            alarm: true,
          ),
        );
        break;

      case 'booking_closed':
        // The passenger cancelled or the agency rejected a booking the agent
        // may have been preparing to issue.
        if (_session?.isAgent != true) return;
        final reference = data['referenceCode']?.toString() ?? '';
        final cancelled = (data['status']?.toString().toLowerCase() ?? '') != 'rejected';
        unawaited(
          notificationService.showImmediateAlert(
            title: cancelled
                ? 'Booking cancelled${reference.isEmpty ? '' : ' · $reference'}'
                : 'Booking rejected${reference.isEmpty ? '' : ' · $reference'}',
            body: cancelled
                ? 'The passenger cancelled this booking. Do not issue a ticket for it.'
                : 'This booking was rejected. Do not issue a ticket for it.',
            type: 'booking_closed',
            entityId: data['bookingId']?.toString(),
          ),
        );
        break;

      case 'ticket_uploaded':
        if (_session?.isAgent == true) return;
        final reference = data['referenceCode']?.toString() ?? '';
        unawaited(
          notificationService.showImmediateAlert(
            title: 'Your ticket is ready',
            body:
                'The physical ticket${reference.isEmpty ? '' : ' for $reference'} has been issued. The photo proof is in your ticket.',
            type: 'ticket_uploaded',
            entityId: data['bookingId']?.toString(),
          ),
        );
        unawaited(
          ref.read(ticketSyncServiceProvider).syncAllTickets(force: true),
        );
        break;

      case 'booking_status':
        if (_session?.isAgent == true) return;
        final status = data['status']?.toString().toLowerCase() ?? '';
        final reference = data['referenceCode']?.toString() ?? '';
        if (status == 'issued') {
          // The proof-ready event carries the actionable message; ignore this
          // companion status to avoid notifying the passenger twice.
          break;
        }
        final (String title, String body) = switch (status) {
          'confirmed' => (
              'Booking confirmed',
              'Your booking${reference.isEmpty ? '' : ' $reference'} is confirmed and paid.',
            ),
          'cancelled' => (
              'Booking cancelled',
              'Your booking${reference.isEmpty ? '' : ' $reference'} has been cancelled.',
            ),
          'rejected' => (
              'Booking rejected',
              'Your booking${reference.isEmpty ? '' : ' $reference'} was rejected. Open the app for details.',
            ),
          'failed' => (
              'Payment failed',
              'We could not confirm your payment. Please try again.',
            ),
          _ => ('Booking update', 'There is an update on your booking.'),
        };
        unawaited(
          notificationService.showImmediateAlert(
            title: title,
            body: body,
            type: 'booking_status',
            entityId: data['bookingId']?.toString(),
          ),
        );
        break;

      case 'payment:failed':
        if (_session?.isAgent == true) return;
        unawaited(
          notificationService.showImmediateAlert(
            title: 'Payment failed',
            body: 'We could not confirm your payment. Please try again.',
            type: 'payment',
            entityId: data['bookingId']?.toString(),
          ),
        );
        break;

      case 'notification':
        final title = data['title']?.toString() ?? 'Katisha';
        final body = data['message']?.toString() ??
            data['body']?.toString() ??
            '';
        if (body.isEmpty) break;
        unawaited(
          notificationService.showImmediateAlert(
            title: title,
            body: body,
            type: data['type']?.toString() ?? 'notification',
            entityId: data['bookingId']?.toString(),
          ),
        );
        break;
    }

    if (event.name == 'new_booking' ||
        event.name == 'ticket_uploaded' ||
        event.name == 'booking_status' ||
        event.name == 'booking_ready' ||
        event.name == 'booking_issued' ||
        event.name == 'booking_paid' ||
        event.name == 'payment:confirmed' ||
        event.name == 'booking_closed' ||
        event.name == 'agent_reminder') {
      unawaited(ref.read(badgeCountsProvider.notifier).refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSub?.cancel();
    _socketEventSub?.cancel();
    _sessionSub?.cancel();
    _tokenRefreshSub?.cancel();
    _notificationTapSub = null;
    _socketEventSub = null;
    _sessionSub = null;
    _tokenRefreshSub = null;
    super.dispose();
  }

  void _handleNotificationNavigation(
    GoRouter router,
    NotificationPayload payload,
  ) {
    final type = payload.type;
    final entityId = payload.entityId;

    switch (type) {
      case 'journey_alert':
      case 'journey_alert_snooze':
        if (entityId != null) router.push('/ticket/$entityId');
        break;
      case 'new_booking':
      case 'booking_paid':
      case 'agent_reminder':
        // Open the exact booking so the agent can act immediately.
        router.push(
          entityId != null && entityId.isNotEmpty
              ? '/agent?booking=$entityId'
              : '/agent',
        );
        break;
      case 'booking_closed':
        router.push('/agent');
        break;
      case 'ticket_uploaded':
      case 'booking':
      case 'booking_status':
      case 'payment':
        if (entityId != null && entityId.isNotEmpty) {
          router.push('/ticket/$entityId');
        } else {
          router.push('/notifications');
        }
        break;
      case 'cancellation':
        router.push('/my-bookings');
        break;
      default:
        router.push('/notifications');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(appLocaleProvider);

    return MaterialApp.router(
      title: 'Katisha',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      locale: locale,
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: supportedLocales,
    );
  }
}

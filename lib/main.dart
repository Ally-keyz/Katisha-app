import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session.dart';
import 'core/network/api_client.dart';
import 'core/network/socket_service.dart';
import 'core/platform/badge_counts.dart';
import 'core/platform/notification_service.dart';
import 'core/platform/platform_providers.dart';
import 'core/platform/ticket_sync_service.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class _KatishaAppState extends ConsumerState<KatishaApp> {
  StreamSubscription<NotificationPayload>? _notificationTapSub;
  StreamSubscription<SocketEvent>? _socketEventSub;
  StreamSubscription<SessionUser?>? _sessionSub;
  SessionUser? _session;

  @override
  void initState() {
    super.initState();
    _setupNotificationTapListener();
    _setupSessionAndSocket();
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
      ref.read(socketServiceProvider).disconnect();
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
          ref.read(ticketSyncServiceProvider).syncAllTickets(),
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
        event.name == 'booking_issued') {
      unawaited(ref.read(badgeCountsProvider.notifier).refresh());
    }
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _socketEventSub?.cancel();
    _sessionSub?.cancel();
    _notificationTapSub = null;
    _socketEventSub = null;
    _sessionSub = null;
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

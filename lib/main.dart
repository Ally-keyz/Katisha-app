import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/platform/notification_service.dart';
import 'core/platform/platform_providers.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap the decoded-image cache so ticket PNGs and UI images can't balloon
  // memory. ~100 MB of decoded bitmaps is plenty for this app's screens.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 400;

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

  @override
  void initState() {
    super.initState();
    _setupNotificationTapListener();
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

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _notificationTapSub = null;
    super.dispose();
  }

  void _handleNotificationNavigation(GoRouter router, NotificationPayload payload) {
    final type = payload.type;
    final entityId = payload.entityId;

    if (entityId == null) return;

    switch (type) {
      case 'journey_alert':
      case 'journey_alert_snooze':
        router.push('/ticket/$entityId');
        break;
      case 'booking':
      case 'payment':
        router.push('/ticket/$entityId');
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

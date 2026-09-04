import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/platform/notification_service.dart';
import 'core/platform/platform_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final overrides = await createAppOverrides();

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
  bool _localeInitialized = false;

  @override
  void initState() {
    super.initState();
    _setupNotificationTapListener();
  }

  void _setupNotificationTapListener() {
    final notificationService = ref.read(notificationServiceProvider);
    notificationService.onNotificationTapped.listen((payload) {
      if (!mounted) return;
      final router = ref.read(appRouterProvider);
      _handleNotificationNavigation(router, payload);
    });
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

    // Initialize locale once from SharedPreferences
    if (!_localeInitialized) {
      _localeInitialized = true;
      initializeLocale(ref);
    }

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

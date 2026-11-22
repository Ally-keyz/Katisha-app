import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/core/network/api_client.dart';
import 'package:katisha/core/platform/badge_counts.dart';
import 'package:katisha/core/platform/local_notification_store.dart';
import 'package:katisha/core/platform/local_ticket_store.dart';
import 'package:katisha/core/platform/platform_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthenticatedApiClient extends ApiClient {
  @override
  bool get isAuthenticated => true;
}

ProviderContainer _containerWith(
  SharedPreferences prefs,
  LocalNotificationStore notifications,
  ApiClient api,
) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localNotificationStoreProvider.overrideWithValue(notifications),
      localTicketStoreProvider.overrideWithValue(LocalTicketStore(prefs)),
      apiClientProvider.overrideWithValue(api),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clear removes every locally cached notification', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalNotificationStore(prefs);

    await store.add(
      title: 'Old account',
      message: 'Previous booking',
      type: 'booking',
    );
    expect(await store.getAll(), hasLength(1));

    await store.clear();

    expect(await store.getAll(), isEmpty);
  });

  test('signed-out badge ignores locally cached notifications', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = LocalNotificationStore(prefs);
    await notifications.add(
      title: 'Old account',
      message: 'Previous booking',
      type: 'booking',
    );

    final container = _containerWith(prefs, notifications, ApiClient());
    addTearDown(container.dispose);

    await container.read(badgeCountsProvider.notifier).refresh();

    expect(container.read(badgeCountsProvider).notificationCount, 0);
  });

  test('authenticated badge still falls back to local unread rows', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = LocalNotificationStore(prefs);
    await notifications.add(
      title: 'Pending payment',
      message: 'Still processing',
      type: 'payment',
    );

    final container = _containerWith(
      prefs,
      notifications,
      _AuthenticatedApiClient(),
    );
    addTearDown(container.dispose);

    await container.read(badgeCountsProvider.notifier).refresh();

    expect(container.read(badgeCountsProvider).notificationCount, 1);
  });
}

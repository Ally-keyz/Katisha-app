import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/shared/models/notification_model.dart';

void main() {
  group('NotificationModel.fromJson', () {
    test('reads the current read field', () {
      final n = NotificationModel.fromJson({
        'id': 'n1',
        'title': 'Paid',
        'read': true,
      });
      expect(n.read, isTrue);
    });

    test('falls back to isRead and status on older payloads', () {
      expect(
        NotificationModel.fromJson({'id': 'n2', 'isRead': true}).read,
        isTrue,
      );
      expect(
        NotificationModel.fromJson({'id': 'n3', 'status': 'read'}).read,
        isTrue,
      );
      expect(
        NotificationModel.fromJson({'id': 'n4', 'status': 'unread'}).read,
        isFalse,
      );
    });
  });

  group('PaginatedNotifications.fromJson', () {
    test('parses the server unreadCount', () {
      final page = PaginatedNotifications.fromJson({
        'notifications': [
          {'id': 'n1', 'read': false},
        ],
        'unreadCount': 9,
        'total': 20,
        'page': 1,
        'limit': 20,
        'pages': 1,
      });
      expect(page.unreadCount, 9);
    });

    test('leaves unreadCount null when an older server omits it', () {
      final page = PaginatedNotifications.fromJson({
        'notifications': [],
        'total': 0,
      });
      expect(page.unreadCount, isNull);
    });
  });
}

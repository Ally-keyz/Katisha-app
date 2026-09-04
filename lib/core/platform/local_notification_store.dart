import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/notification_model.dart';

/// Persists a local record of notifications (journey alerts, booking and
/// payment events) so the in-app Notifications tab has content even when the
/// device is offline or the backend has not recorded the event yet.
class LocalNotificationStore {
  static const _storageKey = 'Katisha_local_notifications_v1';
  static const _maxEntries = 50;

  final SharedPreferences _prefs;

  LocalNotificationStore(this._prefs);

  Future<void> add({
    required String title,
    required String message,
    required String type,
    String? entityId,
  }) async {
    final entries = await _read();
    entries.insert(
      0,
      NotificationModel(
        id: entityId != null && entityId.isNotEmpty
            ? 'local_$entityId'
            : 'local_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        message: message,
        type: type,
        createdAt: DateTime.now(),
      ),
    );

    final deduped = <String, NotificationModel>{};
    for (final e in entries) {
      deduped[e.id] = e;
    }
    final list = deduped.values.toList();
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }

    await _write(list);
  }

  Future<List<NotificationModel>> getAll() async {
    return _read();
  }

  Future<void> markAllRead() async {
    final entries = await _read();
    final updated = entries
        .map((e) => NotificationModel(
              id: e.id,
              title: e.title,
              message: e.message,
              type: e.type,
              read: true,
              createdAt: e.createdAt,
            ))
        .toList();
    await _write(updated);
  }

  /// Removes a single persisted notification by its id, if present.
  Future<void> remove(String id) async {
    final entries = await _read();
    final updated = entries.where((e) => e.id != id).toList();
    if (updated.length != entries.length) {
      await _write(updated);
    }
  }

  Future<List<NotificationModel>> _read() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<NotificationModel> entries) async {
    final encoded = jsonEncode(
      entries.map((e) => {
            'id': e.id,
            'title': e.title,
            'message': e.message,
            'type': e.type,
            'read': e.read,
            'createdAt': e.createdAt?.toIso8601String(),
          }).toList(),
    );
    await _prefs.setString(_storageKey, encoded);
  }
}

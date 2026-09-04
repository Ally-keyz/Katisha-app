import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists tickets locally so they can be viewed offline.
///
/// Two kinds of data are stored:
///  * The booking/ticket JSON (in [SharedPreferences]) so the ticket screen can
///    render without a network call.
///  * The ticket image bytes (in the app-private Documents directory) so the
///    ticket image is available offline and is NOT visible in the gallery or
///    the user's public file manager.
class LocalTicketStore {
  static const _indexKey = 'Katisha_local_tickets_v1';

  final SharedPreferences _prefs;

  LocalTicketStore(this._prefs);

  /// The sub-folder (inside app Documents) that holds ticket images.
  static const _dirName = 'katisha_tickets';

  /// Caches the booking/ticket JSON for a booking id.
  Future<void> cacheBooking(String bookingId, Map<String, dynamic> json) async {
    final index = await _readIndex();
    index[bookingId] = jsonEncode(json);
    await _writeIndex(index);
  }

  /// Returns the cached booking/ticket JSON, or null when absent.
  Future<Map<String, dynamic>?> getBooking(String bookingId) async {
    final index = await _readIndex();
    final raw = index[bookingId];
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Returns all locally cached tickets as raw JSON maps (order not
  /// guaranteed). Used to render the offline "My Trips" list.
  Future<List<Map<String, dynamic>>> getCachedBookings() async {
    final index = await _readIndex();
    final list = <Map<String, dynamic>>[];
    for (final raw in index.values) {
      try {
        list.add(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return list;
  }

  /// Downloads nothing itself - callers pass already-downloaded image bytes.
  /// Saves them to the private app Documents folder (not the gallery).
  Future<String?> saveTicketImage(String bookingId, Uint8List bytes) async {
    try {
      final dir = await _ticketDir();
      final file = File('${dir.path}/$bookingId.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Returns the local file path of a stored ticket image, or null.
  Future<String?> getTicketImagePath(String bookingId) async {
    try {
      final dir = await _ticketDir();
      final file = File('${dir.path}/$bookingId.png');
      return await file.exists() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes a cached ticket (data + image) for a booking id.
  Future<void> removeTicket(String bookingId) async {
    final index = await _readIndex();
    index.remove(bookingId);
    await _writeIndex(index);
    try {
      final dir = await _ticketDir();
      final file = File('${dir.path}/$bookingId.png');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Counts tickets that are still active (not cancelled/rejected and not past
  /// their travel date). Used for the "My Tickets" badge.
  Future<int> getActiveTicketCount() async {
    final index = await _readIndex();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int count = 0;
    for (final raw in index.values) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final status = (json['status'] as String?) ?? '';
        if (status == 'cancelled' || status == 'rejected') continue;
        final travelDateStr = json['travelDate'] as String?;
        if (travelDateStr == null) continue;
        final date = DateTime.tryParse(travelDateStr);
        if (date == null) continue;
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(today)) continue;
        count++;
      } catch (_) {}
    }
    return count;
  }

  Future<Directory> _ticketDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Map<String, String>> _readIndex() async {
    final raw = _prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, String> index) async {
    await _prefs.setString(_indexKey, jsonEncode(index));
  }
}

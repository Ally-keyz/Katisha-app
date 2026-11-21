import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A locally cached ticket: the booking JSON plus the private image on disk and
/// the remote URL that image came from.
class CachedTicket {
  final Map<String, dynamic>? booking;
  final String? imagePath;
  final String? imageUrl;

  const CachedTicket({this.booking, this.imagePath, this.imageUrl});
}

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

  /// Maps a booking id to the remote image URL the cached file was downloaded
  /// from, so a newly issued (agent) ticket replaces the older system receipt
  /// instead of being skipped because a file already exists.
  static const _imageUrlIndexKey = 'Katisha_local_ticket_image_urls_v1';

  final SharedPreferences _prefs;

  /// Resolved once per process: `getApplicationDocumentsDirectory()` is a
  /// platform round-trip and every image read/write used to repeat it.
  Future<Directory>? _dirFuture;

  LocalTicketStore(this._prefs);

  /// The sub-folder (inside app Documents) that holds ticket images.
  static const _dirName = 'katisha_tickets';

  /// Caches the booking/ticket JSON for a booking id.
  Future<void> cacheBooking(String bookingId, Map<String, dynamic> json) {
    return cacheBookings({bookingId: json});
  }

  /// Caches many bookings with a single read and a single write of the index.
  ///
  /// Writing per booking encoded the whole index once per ticket, which is
  /// quadratic: a 100-ticket sync encoded a growing map 100 times and wrote it
  /// to disk 100 times on the UI isolate.
  Future<void> cacheBookings(Map<String, Map<String, dynamic>> entries) async {
    if (entries.isEmpty) return;
    final index = await _readIndex();
    for (final entry in entries.entries) {
      index[entry.key] = jsonEncode(entry.value);
    }
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

  /// Everything the ticket screen needs, read once: one pass over the booking
  /// index, one over the image-URL index and one file stat. The screen used to
  /// repeat those three lookups (and a fourth for the URL) on every open.
  Future<CachedTicket> getTicketSnapshot(String bookingId) async {
    final index = await _readIndex();
    final imageUrls = await _readImageUrls();

    Map<String, dynamic>? booking;
    final raw = index[bookingId];
    if (raw != null && raw.isNotEmpty) {
      try {
        booking = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }

    String? imagePath;
    try {
      final dir = await _ticketDir();
      final file = File('${dir.path}/$bookingId.png');
      if (await file.exists()) imagePath = file.path;
    } catch (_) {}

    return CachedTicket(
      booking: booking,
      imagePath: imagePath,
      imageUrl: imageUrls[bookingId],
    );
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

  /// The remote URL the cached image was downloaded from, or null.
  Future<String?> getTicketImageUrl(String bookingId) async {
    final map = await _readImageUrls();
    return map[bookingId];
  }

  /// Every booking id mapped to the remote image it was downloaded from.
  /// Reading the whole index once beats one decode per booking in a sync.
  Future<Map<String, String>> getTicketImageUrls() => _readImageUrls();

  /// Records which remote image is stored for a booking.
  Future<void> setTicketImageUrl(String bookingId, String url) {
    return setTicketImageUrls({bookingId: url});
  }

  /// Records several images with one read and one write of the index.
  Future<void> setTicketImageUrls(Map<String, String> urls) async {
    if (urls.isEmpty) return;
    final map = await _readImageUrls();
    map.addAll(urls);
    await _prefs.setString(_imageUrlIndexKey, jsonEncode(map));
  }

  /// Removes a cached ticket (data + image) for a booking id.
  Future<void> removeTicket(String bookingId) async {
    final index = await _readIndex();
    index.remove(bookingId);
    await _writeIndex(index);
    final imageUrls = await _readImageUrls();
    if (imageUrls.remove(bookingId) != null) {
      await _prefs.setString(_imageUrlIndexKey, jsonEncode(imageUrls));
    }
    try {
      final dir = await _ticketDir();
      final file = File('${dir.path}/$bookingId.png');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Counts booked tickets that are actually paid and still upcoming.
  ///
  /// Checkout caches a booking as soon as the server accepts it, with
  /// `status: confirmed` and `paymentStatus: processing`. Counting that as an
  /// active ticket made the bottom-nav badge include failed and abandoned
  /// payments. Only a confirmed payment counts; legacy caches written before
  /// `paymentStatus` existed still count when the ticket was issued.
  Future<int> getActiveTicketCount() async {
    final index = await _readIndex();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int count = 0;
    for (final raw in index.values) {
      try {
        final booking = jsonDecode(raw) as Map<String, dynamic>;
        final status = (booking['status'] as String?)?.toLowerCase() ?? '';
        if (status == 'cancelled' || status == 'rejected' || status == 'failed') {
          continue;
        }
        final paymentStatus =
            (booking['paymentStatus'] as String?)?.toLowerCase() ?? '';
        if (paymentStatus.isEmpty) {
          // Legacy entry: an issued ticket could only exist after payment.
          if (status != 'issued') continue;
        } else if (paymentStatus != 'paid') {
          continue;
        }
        final travelDateStr = booking['travelDate'] as String?;
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

  /// Removes cached bookings the server has marked failed/cancelled, so a
  /// previous checkout attempt can never keep inflating the ticket badge.
  /// Called after a successful ticket sync, which has just refreshed the
  /// authoritative statuses in the index.
  Future<void> pruneUnsuccessfulTickets() async {
    final index = await _readIndex();
    final imageUrls = await _readImageUrls();
    final doomed = <String>[];

    for (final entry in index.entries) {
      try {
        final booking = jsonDecode(entry.value) as Map<String, dynamic>;
        final status = (booking['status'] as String?)?.toLowerCase() ?? '';
        final paymentStatus =
            (booking['paymentStatus'] as String?)?.toLowerCase() ?? '';
        if (status == 'cancelled' ||
            status == 'rejected' ||
            status == 'failed' ||
            paymentStatus == 'failed' ||
            paymentStatus == 'refunded') {
          doomed.add(entry.key);
        }
      } catch (_) {}
    }
    if (doomed.isEmpty) return;

    for (final id in doomed) {
      index.remove(id);
      imageUrls.remove(id);
      try {
        final dir = await _ticketDir();
        final file = File('${dir.path}/$id.png');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _writeIndex(index);
    await _prefs.setString(_imageUrlIndexKey, jsonEncode(imageUrls));
  }

  /// Resolves (and creates) the ticket image folder once per process. The
  /// future is cached so a 100-ticket sync does not do 100 platform lookups;
  /// a failure clears the cache so the next call retries.
  Future<Directory> _ticketDir() async {
    final cached = _dirFuture;
    if (cached != null) return cached;
    final future = _resolveTicketDir();
    _dirFuture = future;
    try {
      return await future;
    } catch (_) {
      _dirFuture = null;
      rethrow;
    }
  }

  Future<Directory> _resolveTicketDir() async {
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

  Future<Map<String, String>> _readImageUrls() async {
    final raw = _prefs.getString(_imageUrlIndexKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }
}

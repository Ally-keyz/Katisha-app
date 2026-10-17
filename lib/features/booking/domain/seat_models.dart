/// Shared seat-selection contracts. These mirror the `/api/v1` payload exactly
/// so the seat map never re-derives geometry or seat numbers — everything comes
/// from the backend layout JSON. Ported from the web `src/types/seat.ts`.
library;

/// Seat cell type. `driver` marks the row that carries the driver cabin.
class SeatCellType {
  static const seat = 'seat';
  static const aisle = 'aisle';
  static const gap = 'gap';
  static const door = 'door';
  static const driver = 'driver';
}

/// A single cell in the seat layout.
class SeatCell {
  final String type;

  /// Present only for `type == 'seat'`. Always supplied by the API.
  final String? label;

  /// One of: available, booked_online, booked_manual, blocked, held.
  final String? status;

  /// True when a hold belongs to this client's own checkout session.
  final bool heldByMe;

  /// Admin mode only.
  final String? passengerName;
  final String? passengerPhone;
  final String? note;
  final String? paymentMethod;

  const SeatCell({
    required this.type,
    this.label,
    this.status,
    this.heldByMe = false,
    this.passengerName,
    this.passengerPhone,
    this.note,
    this.paymentMethod,
  });

  factory SeatCell.fromJson(Map<String, dynamic> json) {
    return SeatCell(
      type: json['type'] as String? ?? SeatCellType.gap,
      label: json['label'] as String?,
      status: json['status'] as String?,
      heldByMe: json['heldByMe'] as bool? ?? false,
      passengerName: json['passengerName'] as String?,
      passengerPhone: json['passengerPhone'] as String?,
      note: json['note'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
    );
  }

  bool get isSeat => type == SeatCellType.seat;

  /// True when the seat cannot be picked by this client.
  bool get isInteractive => status == null || status == 'available' || (status == 'held' && heldByMe);

  bool get isOccupied =>
      status == 'booked_online' ||
      status == 'booked_manual' ||
      status == 'blocked' ||
      status == 'held';

  SeatCell copyWith({String? status, bool? heldByMe}) {
    return SeatCell(
      type: type,
      label: label,
      status: status ?? this.status,
      heldByMe: heldByMe ?? this.heldByMe,
      passengerName: passengerName,
      passengerPhone: passengerPhone,
      note: note,
      paymentMethod: paymentMethod,
    );
  }
}

class SeatRow {
  final int y;
  final List<SeatCell> cells;

  const SeatRow({required this.y, required this.cells});

  factory SeatRow.fromJson(Map<String, dynamic> json) {
    return SeatRow(
      y: (json['y'] as num?)?.toInt() ?? 0,
      cells: (json['cells'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(SeatCell.fromJson)
              .toList() ??
          const [],
    );
  }
}

class SeatTripInfo {
  final String id;
  final String agencyId;
  final String agencyName;
  final String? agencyLogo;
  final String routeId;
  final String origin;
  final String destination;
  final String? via;
  final String travelDate;
  final String travelTime;
  final num price;
  final String currency;
  final int totalSeats;
  final int seatVersion;

  const SeatTripInfo({
    required this.id,
    required this.agencyId,
    required this.agencyName,
    this.agencyLogo,
    required this.routeId,
    required this.origin,
    required this.destination,
    this.via,
    required this.travelDate,
    required this.travelTime,
    required this.price,
    required this.currency,
    required this.totalSeats,
    required this.seatVersion,
  });

  factory SeatTripInfo.fromJson(Map<String, dynamic> json) {
    final agency = json['agency'] as Map<String, dynamic>? ?? const {};
    final route = json['route'] as Map<String, dynamic>? ?? const {};
    return SeatTripInfo(
      id: json['id']?.toString() ?? '',
      agencyId: agency['id']?.toString() ?? '',
      agencyName: agency['name'] as String? ?? '',
      agencyLogo: agency['logo'] as String?,
      routeId: route['id']?.toString() ?? '',
      origin: route['origin'] as String? ?? '',
      destination: route['destination'] as String? ?? '',
      via: route['via'] as String?,
      travelDate: json['travelDate']?.toString() ?? '',
      travelTime: json['travelTime'] as String? ?? '',
      price: (json['price'] as num?) ?? 0,
      currency: json['currency'] as String? ?? 'RWF',
      totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
      seatVersion: (json['seatVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

class SeatSummary {
  final int total;
  final int available;
  final int taken;
  final int blocked;

  const SeatSummary({
    required this.total,
    required this.available,
    required this.taken,
    required this.blocked,
  });

  factory SeatSummary.fromJson(Map<String, dynamic> json) {
    return SeatSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      available: (json['available'] as num?)?.toInt() ?? 0,
      taken: (json['taken'] as num?)?.toInt() ?? 0,
      blocked: (json['blocked'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The full `/v1/trips/:tripId/seats` payload.
class TripSeatMap {
  final SeatTripInfo trip;
  final List<SeatRow> rows;
  final SeatSummary summary;
  final int maxPerBooking;

  const TripSeatMap({
    required this.trip,
    required this.rows,
    required this.summary,
    required this.maxPerBooking,
  });

  factory TripSeatMap.fromJson(Map<String, dynamic> json) {
    final layout = json['layout'] as Map<String, dynamic>? ?? const {};
    return TripSeatMap(
      trip: SeatTripInfo.fromJson(
          json['trip'] as Map<String, dynamic>? ?? const {}),
      rows: (layout['rows'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(SeatRow.fromJson)
              .toList() ??
          const [],
      summary: SeatSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {}),
      maxPerBooking: (json['maxPerBooking'] as num?)?.toInt() ?? 5,
    );
  }

  TripSeatMap copyWith({
    List<SeatRow>? rows,
    SeatTripInfo? trip,
  }) {
    return TripSeatMap(
      trip: trip ?? this.trip,
      rows: rows ?? this.rows,
      summary: summary,
      maxPerBooking: maxPerBooking,
    );
  }
}

/// What the UI actually switches on. Both booking kinds render as "taken".
enum VisualSeatState { available, selected, taken, blocked }

VisualSeatState visualStateOf(SeatCell cell, bool selected) {
  if (selected) return VisualSeatState.selected;
  switch (cell.status) {
    case null:
    case 'available':
      return VisualSeatState.available;
    case 'held':
      return cell.heldByMe ? VisualSeatState.available : VisualSeatState.taken;
    case 'blocked':
      return VisualSeatState.blocked;
    default:
      return VisualSeatState.taken;
  }
}

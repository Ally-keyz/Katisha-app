import 'booking_model.dart';

class BookingResponse {
  final List<Booking> bookings;
  final int total;
  final int page;
  final int limit;
  final int pages;

  const BookingResponse({
    required this.bookings,
    required this.total,
    required this.page,
    required this.limit,
    required this.pages,
  });

  factory BookingResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    return BookingResponse(
      bookings: (data['bookings'] as List<dynamic>?)
              ?.map((b) => Booking.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      total: data['total'] as int? ?? 0,
      page: data['page'] as int? ?? 1,
      limit: data['limit'] as int? ?? 10,
      pages: data['pages'] as int? ?? 1,
    );
  }
}

class RouteScheduleRoute {
  final String id;
  final String origin;
  final String destination;

  const RouteScheduleRoute({
    required this.id,
    required this.origin,
    required this.destination,
  });

  factory RouteScheduleRoute.fromJson(Map<String, dynamic> json) {
    return RouteScheduleRoute(
      id: json['_id'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
    );
  }
}

class RouteSchedule {
  final RouteScheduleRoute route;
  final DateTime? travelDate;
  final String travelTime;
  final String status;
  final int bookingCount;
  final int seatCount;

  const RouteSchedule({
    required this.route,
    this.travelDate,
    required this.travelTime,
    required this.status,
    this.bookingCount = 0,
    this.seatCount = 0,
  });

  factory RouteSchedule.fromJson(Map<String, dynamic> json) {
    final routeData = json['route'];
    return RouteSchedule(
      route: routeData is Map<String, dynamic>
          ? RouteScheduleRoute.fromJson(routeData)
          : const RouteScheduleRoute(id: '', origin: '', destination: ''),
      travelDate: json['travelDate'] != null
          ? DateTime.tryParse(json['travelDate'] as String)
          : null,
      travelTime: json['travelTime'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      bookingCount: json['bookingCount'] as int? ?? 0,
      seatCount: json['seatCount'] as int? ?? 0,
    );
  }
}

class RouteStop {
  final String name;
  final int price;

  const RouteStop({required this.name, required this.price});

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      name: json['name'] as String? ?? '',
      price: json['price'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class RouteAgency {
  final String id;
  final String name;
  final String? logo;
  final String? workingHours;
  final String? busLayout;

  const RouteAgency({
    required this.id,
    required this.name,
    this.logo,
    this.workingHours,
    this.busLayout,
  });

  factory RouteAgency.fromJson(Map<String, dynamic> json) {
    return RouteAgency(
      id: json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logo: json['logo'] as String?,
      workingHours: json['workingHours'] as String?,
      busLayout: json['busLayout'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'logo': logo,
        'workingHours': workingHours,
        'busLayout': busLayout,
      };
}

class RouteModel {
  final String id;
  final RouteAgency agency;
  final String type;
  final String origin;
  final String destination;
  final int price;
  final int? effectivePrice;
  final List<RouteStop> stops;
  final List<String> provinces;
  final List<String> countries;
  final String? estimatedDuration;
  final String status;

  const RouteModel({
    required this.id,
    required this.agency,
    required this.type,
    required this.origin,
    required this.destination,
    required this.price,
    this.effectivePrice,
    this.stops = const [],
    this.provinces = const [],
    this.countries = const [],
    this.estimatedDuration,
    required this.status,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    final agencyData = json['agency'];
    return RouteModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      agency: agencyData is Map<String, dynamic>
          ? RouteAgency.fromJson(agencyData)
          : const RouteAgency(id: '', name: ''),
      type: json['type'] as String? ?? 'intercity',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      price: json['price'] as int? ?? 0,
      effectivePrice: json['effectivePrice'] as int?,
      stops: (json['stops'] as List<dynamic>?)
              ?.map((s) => RouteStop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      provinces: (json['provinces'] as List<dynamic>?)
              ?.map((p) => p as String)
              .toList() ??
          [],
      countries: (json['countries'] as List<dynamic>?)
              ?.map((c) => c as String)
              .toList() ??
          [],
      estimatedDuration: json['estimatedDuration'] as String?,
      status: json['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'agency': agency.toJson(),
        'type': type,
        'origin': origin,
        'destination': destination,
        'price': price,
        'effectivePrice': effectivePrice,
        'stops': stops.map((s) => s.toJson()).toList(),
        'provinces': provinces,
        'countries': countries,
        'estimatedDuration': estimatedDuration,
        'status': status,
      };
}

/// The server populates `confirmedBy`/`rejectedBy` as `{ _id, name, username }`
/// objects (or leaves them as ObjectId strings), so resolve either to a
/// display name without tripping the `as String?` cast.
String? _agentName(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) {
    final name = value['name'];
    if (name is String && name.isNotEmpty) return name;
    final username = value['username'];
    if (username is String && username.isNotEmpty) return username;
    return value['_id']?.toString();
  }
  return value.toString();
}

class PassengerDetail {
  final String name;
  final String phone;

  const PassengerDetail({required this.name, required this.phone});

  factory PassengerDetail.fromJson(Map<String, dynamic> json) {
    return PassengerDetail(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

class BookingAgency {
  final String id;
  final String name;

  const BookingAgency({required this.id, required this.name});

  factory BookingAgency.fromJson(Map<String, dynamic> json) {
    return BookingAgency(
      id: json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

class BookingUser {
  final String id;
  final String name;
  final String phone;
  final String? email;

  const BookingUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
  });

  factory BookingUser.fromJson(Map<String, dynamic> json) {
    return BookingUser(
      id: json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
    );
  }
}

class BookingRoute {
  final String id;
  final String origin;
  final String destination;
  final int price;

  const BookingRoute({
    required this.id,
    required this.origin,
    required this.destination,
    required this.price,
  });

  factory BookingRoute.fromJson(Map<String, dynamic> json) {
    return BookingRoute(
      id: json['_id'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      price: json['price'] as int? ?? 0,
    );
  }
}

class Booking {
  final String id;
  final String referenceCode;
  final String origin;
  final String destination;
  final String? pickupPoint;
  final DateTime? travelDate;
  final String? travelTime;
  final int seats;
  final List<String> seatNumbers;
  final List<PassengerDetail> passengerDetails;
  final int totalAmount;
  final int systemFee;
  final int payAmount;
  final String status;
  final String paymentStatus;
  final String? paymentMethod;
  final String? phone;
  final bool isGuest;
  final bool isBulkBooking;
  final String? purpose;
  final String? pickupDistrict;
  final String? pickupDescription;
  final String? contactPhone;
  final String? ticketImage;
  final String? ticketHash;
  final String? receiptImage;
  final String? ticketProofImage;
  final DateTime? ticketProofUploadedAt;
  final bool agentSeen;
  final DateTime? agentSeenAt;
  final DateTime? readyAt;
  final BookingAgency? agency;
  final BookingUser? user;
  final BookingRoute? route;
  final String? confirmedBy;
  final String? rejectedBy;
  final String? rejectionReason;
  final DateTime? createdAt;
  final bool freeTicketUsed;

  const Booking({
    required this.id,
    required this.referenceCode,
    required this.origin,
    required this.destination,
    this.pickupPoint,
    this.travelDate,
    this.travelTime,
    this.seats = 1,
    this.seatNumbers = const [],
    this.passengerDetails = const [],
    this.totalAmount = 0,
    this.systemFee = 0,
    this.payAmount = 0,
    this.status = 'pending',
    this.paymentStatus = 'pending',
    this.paymentMethod,
    this.phone,
    this.isGuest = false,
    this.isBulkBooking = false,
    this.purpose,
    this.pickupDistrict,
    this.pickupDescription,
    this.contactPhone,
    this.ticketImage,
    this.ticketHash,
    this.receiptImage,
    this.ticketProofImage,
    this.ticketProofUploadedAt,
    this.agentSeen = false,
    this.agentSeenAt,
    this.readyAt,
    this.agency,
    this.user,
    this.route,
    this.confirmedBy,
    this.rejectedBy,
    this.rejectionReason,
    this.createdAt,
    this.freeTicketUsed = false,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      referenceCode: json['referenceCode'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      pickupPoint: json['pickupPoint'] as String?,
      travelDate: json['travelDate'] != null
          ? DateTime.tryParse(json['travelDate'] as String)
          : null,
      travelTime: json['travelTime'] as String?,
      seats: json['seats'] as int? ?? 1,
      seatNumbers: (json['seatNumbers'] as List<dynamic>?)
              ?.map((s) => s as String)
              .toList() ??
          [],
      passengerDetails: (json['passengerDetails'] as List<dynamic>?)
              ?.map((p) =>
                  PassengerDetail.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      totalAmount: json['totalAmount'] as int? ?? 0,
      systemFee: json['systemFee'] as int? ?? 0,
      payAmount: json['payAmount'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['paymentStatus'] as String? ?? 'pending',
      paymentMethod: json['paymentMethod'] as String?,
      phone: json['phone'] as String?,
      isGuest: json['isGuest'] as bool? ?? false,
      isBulkBooking: json['isBulkBooking'] as bool? ?? false,
      purpose: json['purpose'] as String?,
      pickupDistrict: json['pickupDistrict'] as String?,
      pickupDescription: json['pickupDescription'] as String?,
      contactPhone: json['contactPhone'] as String?,
      ticketImage: json['ticketImage'] as String?,
      ticketHash: json['ticketHash'] as String?,
      receiptImage: json['receiptImage'] as String?,
      ticketProofImage: json['ticketProofImage'] as String?,
      ticketProofUploadedAt: json['ticketProofUploadedAt'] != null
          ? DateTime.tryParse(json['ticketProofUploadedAt'] as String)
          : null,
      agentSeen: json['agentSeen'] as bool? ?? false,
      agentSeenAt: json['agentSeenAt'] != null
          ? DateTime.tryParse(json['agentSeenAt'] as String)
          : null,
      readyAt: json['readyAt'] != null
          ? DateTime.tryParse(json['readyAt'] as String)
          : null,
      agency: json['agency'] is Map<String, dynamic>
          ? BookingAgency.fromJson(json['agency'] as Map<String, dynamic>)
          : null,
      user: json['user'] is Map<String, dynamic>
          ? BookingUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      route: json['route'] is Map<String, dynamic>
          ? BookingRoute.fromJson(json['route'] as Map<String, dynamic>)
          : null,
      confirmedBy: _agentName(json['confirmedBy']),
      rejectedBy: _agentName(json['rejectedBy']),
      rejectionReason: json['rejectionReason'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      freeTicketUsed: json['freeTicketUsed'] as bool? ?? false,
    );
  }
}

import 'app_role.dart';

/// Authenticated user data model.
class AppUser {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final AppRole role;
  final String? agencyId;
  final String? agencyName;
  final int loyaltyPoints;
  final int freeTickets;
  final int bookingCount;
  final String? language;

  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.agencyId,
    this.agencyName,
    this.loyaltyPoints = 0,
    this.freeTickets = 0,
    this.bookingCount = 0,
    this.language,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final agency = json['agency'];
    return AppUser(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      role: AppRole.fromString(json['role'] as String? ?? 'user'),
      agencyId: agency is Map<String, dynamic>
          ? agency['_id'] as String?
          : agency as String?,
      agencyName: agency is Map<String, dynamic>
          ? agency['name'] as String?
          : null,
      loyaltyPoints: json['loyaltyPoints'] as int? ?? 0,
      freeTickets: json['freeTickets'] as int? ?? 0,
      bookingCount: json['bookingCount'] as int? ?? 0,
      language: json['language'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'role': role.value,
        'agencyId': agencyId,
        'agencyName': agencyName,
        'loyaltyPoints': loyaltyPoints,
        'freeTickets': freeTickets,
        'bookingCount': bookingCount,
        'language': language,
      };

  AppUser copyWith({
    String? name,
    String? phone,
    String? email,
    String? language,
    int? loyaltyPoints,
    int? freeTickets,
    int? bookingCount,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role,
      agencyId: agencyId,
      agencyName: agencyName,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      freeTickets: freeTickets ?? this.freeTickets,
      bookingCount: bookingCount ?? this.bookingCount,
      language: language ?? this.language,
    );
  }

  bool get isUser => role == AppRole.user;
}

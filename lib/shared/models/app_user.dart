import 'app_role.dart';

/// Authenticated user data model.
class AppUser {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final AppRole role;

  /// Every role granted to the account, resolved from the backend `roles[]`
  /// array with the legacy `role` field as a fallback.
  final List<AppRole> roles;
  final String? agencyId;
  final String? agencyName;
  final int loyaltyPoints;
  final int freeTickets;
  final int bookingCount;
  final String? language;

  /// Referral code issued to this user when they became a promoter.
  final String? promoterCode;

  /// Promoter lifecycle state: `pending`, `active` or `suspended`.
  final String? promoterStatus;

  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.roles = const [],
    this.agencyId,
    this.agencyName,
    this.loyaltyPoints = 0,
    this.freeTickets = 0,
    this.bookingCount = 0,
    this.language,
    this.promoterCode,
    this.promoterStatus,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final agency = json['agency'];
    final roles = <AppRole>[];
    final rawRoles = json['roles'];
    if (rawRoles is List) {
      for (final raw in rawRoles) {
        if (raw is! String) continue;
        final parsed = AppRole.fromString(raw);
        if (!roles.contains(parsed)) roles.add(parsed);
      }
    }
    final primary = AppRole.fromUserJson(json);
    if (!roles.contains(primary)) roles.add(primary);

    return AppUser(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      role: primary,
      roles: roles,
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
      promoterCode: json['promoterCode'] as String?,
      promoterStatus: json['promoterStatus'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'role': role.value,
    'roles': roles.map((r) => r.value).toList(),
    'agencyId': agencyId,
    'agencyName': agencyName,
    'loyaltyPoints': loyaltyPoints,
    'freeTickets': freeTickets,
    'bookingCount': bookingCount,
    'language': language,
    'promoterCode': promoterCode,
    'promoterStatus': promoterStatus,
  };

  AppUser copyWith({
    String? name,
    String? phone,
    String? email,
    String? language,
    int? loyaltyPoints,
    int? freeTickets,
    int? bookingCount,
    String? promoterCode,
    String? promoterStatus,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role,
      roles: roles,
      agencyId: agencyId,
      agencyName: agencyName,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      freeTickets: freeTickets ?? this.freeTickets,
      bookingCount: bookingCount ?? this.bookingCount,
      language: language ?? this.language,
      promoterCode: promoterCode ?? this.promoterCode,
      promoterStatus: promoterStatus ?? this.promoterStatus,
    );
  }

  bool get isUser => role == AppRole.user || roles.contains(AppRole.user);

  bool get isPromoter =>
      role == AppRole.promoter || roles.contains(AppRole.promoter);

  /// Promoters can only transact once an admin has approved them; a pending or
  /// suspended account still gets a dashboard but no payout actions.
  ///
  /// Compared case-insensitively to match `PromoterStatus.parse`; this lives
  /// here rather than importing that enum so the shared user model stays free of
  /// feature-layer types.
  bool get isPromoterActive =>
      promoterStatus?.trim().toLowerCase() == 'active';
}

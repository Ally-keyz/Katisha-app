import '../../../../shared/models/app_role.dart';

/// Outcome of `POST /promoter/setup`.
class SetupResult {
  /// True when the server created the account without returning a session, so
  /// the client has to sign in with the credentials it just submitted.
  final bool needsSignIn;
  final String? message;

  const SetupResult({required this.needsSignIn, this.message});
}

/// Paginated envelope shared by the promoter list endpoints.
class PromoterPagination {
  final int page;
  final int limit;
  final int total;
  final int pages;

  const PromoterPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory PromoterPagination.fromJson(Map<String, dynamic>? json) {
    return PromoterPagination(
      page: _int(json?['page'], fallback: 1),
      limit: _int(json?['limit'], fallback: 20),
      total: _int(json?['total']),
      pages: _int(json?['pages']),
    );
  }

  bool get hasMore => page < pages;
}

// ── Profile ─────────────────────────────────────────────

/// `GET /promoter/profile`
class PromoterProfile {
  final String name;
  final String phone;
  final String? promoterCode;
  final String status;
  final String payoutPhone;

  /// False when the promoter has never set their own number, in which case
  /// payouts fall back to their account phone.
  final bool hasCustomPayoutPhone;
  final String? termsAcceptedAt;
  final double commissionRate;
  final double minPayout;

  const PromoterProfile({
    required this.name,
    required this.phone,
    this.promoterCode,
    required this.status,
    required this.payoutPhone,
    required this.hasCustomPayoutPhone,
    this.termsAcceptedAt,
    required this.commissionRate,
    required this.minPayout,
  });

  factory PromoterProfile.fromJson(Map<String, dynamic> json) {
    return PromoterProfile(
      name: _string(json['name']),
      phone: _string(json['phone']),
      promoterCode: _nullableString(json['promoterCode']),
      status: _string(json['status'], fallback: 'pending'),
      payoutPhone: _string(json['payoutPhone']),
      hasCustomPayoutPhone: json['hasCustomPayoutPhone'] == true,
      termsAcceptedAt: _nullableString(json['termsAcceptedAt']),
      commissionRate: _double(json['commissionRate'], fallback: 25),
      minPayout: _double(json['minPayout'], fallback: 1),
    );
  }

  PromoterProfile copyWith({String? payoutPhone, bool? hasCustomPayoutPhone}) {
    return PromoterProfile(
      name: name,
      phone: phone,
      promoterCode: promoterCode,
      status: status,
      payoutPhone: payoutPhone ?? this.payoutPhone,
      hasCustomPayoutPhone: hasCustomPayoutPhone ?? this.hasCustomPayoutPhone,
      termsAcceptedAt: termsAcceptedAt,
      commissionRate: commissionRate,
      minPayout: minPayout,
    );
  }
}

// ── Earnings summary ────────────────────────────────────

/// Aggregate commission ledger totals, produced by the server's
/// `getPromoterEarnings`.
class PromoterEarningsSummary {
  final String currency;
  final double availableBalance;
  final double paidTotal;
  final double reversedTotal;
  final double lifetimeEarned;
  final int pendingCount;
  final int paidCount;
  final int reversedCount;
  final int commissionCount;

  const PromoterEarningsSummary({
    required this.currency,
    required this.availableBalance,
    required this.paidTotal,
    required this.reversedTotal,
    required this.lifetimeEarned,
    required this.pendingCount,
    required this.paidCount,
    required this.reversedCount,
    required this.commissionCount,
  });

  factory PromoterEarningsSummary.fromJson(Map<String, dynamic>? json) {
    return PromoterEarningsSummary(
      currency: _string(json?['currency'], fallback: 'RWF'),
      availableBalance: _double(json?['availableBalance']),
      paidTotal: _double(json?['paidTotal']),
      reversedTotal: _double(json?['reversedTotal']),
      lifetimeEarned: _double(json?['lifetimeEarned']),
      pendingCount: _int(json?['pendingCount']),
      paidCount: _int(json?['paidCount']),
      reversedCount: _int(json?['reversedCount']),
      commissionCount: _int(json?['commissionCount']),
    );
  }
}

// ── Stats ──────────────────────────────────────────────

class PromoterReferralStats {
  final int total;
  final int converted;
  final int conversionRate;

  const PromoterReferralStats({
    required this.total,
    required this.converted,
    required this.conversionRate,
  });

  factory PromoterReferralStats.fromJson(Map<String, dynamic>? json) {
    return PromoterReferralStats(
      total: _int(json?['total']),
      converted: _int(json?['converted']),
      conversionRate: _int(json?['conversionRate']),
    );
  }
}

class PromoterMonthStats {
  final double total;
  final int count;

  const PromoterMonthStats({required this.total, required this.count});

  factory PromoterMonthStats.fromJson(Map<String, dynamic>? json) {
    return PromoterMonthStats(
      total: _double(json?['total']),
      count: _int(json?['count']),
    );
  }
}

/// One point on the monthly earnings trend.
class PromoterTrendPoint {
  final int year;
  final int month;
  final double total;

  const PromoterTrendPoint({
    required this.year,
    required this.month,
    required this.total,
  });

  factory PromoterTrendPoint.fromJson(Map<String, dynamic> json) {
    return PromoterTrendPoint(
      year: _int(json['year']),
      month: _int(json['month']),
      total: _double(json['total']),
    );
  }
}

/// `GET /promoter/stats` — everything the dashboard needs in one round-trip.
class PromoterStats {
  final PromoterEarningsSummary earnings;
  final PromoterReferralStats referrals;
  final PromoterMonthStats thisMonth;
  final List<PromoterTrendPoint> trend;
  final List<PromoterCommission> recentCommissions;
  final double minPayout;
  final bool canRequestPayout;
  final int linkClicks;

  const PromoterStats({
    required this.earnings,
    required this.referrals,
    required this.thisMonth,
    required this.trend,
    required this.recentCommissions,
    required this.minPayout,
    required this.canRequestPayout,
    this.linkClicks = 0,
  });

  factory PromoterStats.fromJson(Map<String, dynamic> json) {
    final commissions = json['recentCommissions'];
    final trend = json['trend'];
    return PromoterStats(
      earnings: PromoterEarningsSummary.fromJson(_map(json['earnings'])),
      referrals: PromoterReferralStats.fromJson(_map(json['referrals'])),
      thisMonth: PromoterMonthStats.fromJson(_map(json['thisMonth'])),
      trend: trend is List
          ? trend
                .whereType<Map<String, dynamic>>()
                .map(PromoterTrendPoint.fromJson)
                .toList()
          : const [],
      recentCommissions: commissions is List
          ? commissions
                .whereType<Map<String, dynamic>>()
                .map(PromoterCommission.fromJson)
                .toList()
          : const [],
      minPayout: _double(json['minPayout'], fallback: 1),
      canRequestPayout: json['canRequestPayout'] == true,
      linkClicks: _int(json['linkClicks']),
    );
  }
}

// ── Referrals ──────────────────────────────────────────

/// A customer signed up with the promoter's referral code.
class PromoterReferral {
  final String id;
  final String? customerName;

  /// Already masked by the server, e.g. `078****007`.
  final String? customerPhone;
  final String status;
  final double lifetimeValue;
  final DateTime? createdAt;

  const PromoterReferral({
    required this.id,
    this.customerName,
    this.customerPhone,
    required this.status,
    required this.lifetimeValue,
    this.createdAt,
  });

  factory PromoterReferral.fromJson(Map<String, dynamic> json) {
    final customer = _map(json['customer']);
    return PromoterReferral(
      id: _string(json['id']),
      customerName: _nullableString(customer?['name']),
      customerPhone: _nullableString(customer?['phone']),
      status: _string(json['status']),
      lifetimeValue: _double(json['lifetimeValue']),
      createdAt: _date(json['createdAt']),
    );
  }

  bool get isConverted => status == 'converted';
}

// ── Commissions ────────────────────────────────────────

class PromoterCommissionBooking {
  final String referenceCode;
  final DateTime? travelDate;

  const PromoterCommissionBooking({
    required this.referenceCode,
    this.travelDate,
  });

  factory PromoterCommissionBooking.fromJson(Map<String, dynamic> json) {
    return PromoterCommissionBooking(
      referenceCode: _string(json['referenceCode']),
      travelDate: _date(json['travelDate']),
    );
  }
}

/// One commission row in the ledger: `pending`, `earned`, `paid` or `reversed`.
class PromoterCommission {
  final String id;
  final double amount;
  final String currency;
  final double rate;
  final double baseAmount;
  final String status;
  final DateTime? earnedAt;
  final DateTime? paidAt;
  final DateTime? reversedAt;
  final PromoterCommissionBooking? booking;

  const PromoterCommission({
    required this.id,
    required this.amount,
    required this.currency,
    required this.rate,
    required this.baseAmount,
    required this.status,
    this.earnedAt,
    this.paidAt,
    this.reversedAt,
    this.booking,
  });

  factory PromoterCommission.fromJson(Map<String, dynamic> json) {
    return PromoterCommission(
      id: _string(json['id']),
      amount: _double(json['amount']),
      currency: _string(json['currency'], fallback: 'RWF'),
      rate: _double(json['rate']),
      baseAmount: _double(json['baseAmount']),
      status: _string(json['status']),
      earnedAt: _date(json['earnedAt']),
      paidAt: _date(json['paidAt']),
      reversedAt: _date(json['reversedAt']),
      booking: json['booking'] is Map<String, dynamic>
          ? PromoterCommissionBooking.fromJson(
              json['booking'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// `GET /promoter/earnings` — the paginated ledger plus its summary.
class PromoterEarningsPage {
  final PromoterEarningsSummary earnings;
  final List<PromoterCommission> commissions;
  final PromoterPagination pagination;

  const PromoterEarningsPage({
    required this.earnings,
    required this.commissions,
    required this.pagination,
  });

  factory PromoterEarningsPage.fromJson(Map<String, dynamic> json) {
    final commissions = json['commissions'];
    return PromoterEarningsPage(
      earnings: PromoterEarningsSummary.fromJson(_map(json['earnings'])),
      commissions: commissions is List
          ? commissions
                .whereType<Map<String, dynamic>>()
                .map(PromoterCommission.fromJson)
                .toList()
          : const [],
      pagination: PromoterPagination.fromJson(_map(json['pagination'])),
    );
  }
}

/// `GET /promoter/referrals`
class PromoterReferralsPage {
  final List<PromoterReferral> referrals;
  final PromoterPagination pagination;

  const PromoterReferralsPage({
    required this.referrals,
    required this.pagination,
  });

  factory PromoterReferralsPage.fromJson(Map<String, dynamic> json) {
    final referrals = json['referrals'];
    return PromoterReferralsPage(
      referrals: referrals is List
          ? referrals
                .whereType<Map<String, dynamic>>()
                .map(PromoterReferral.fromJson)
                .toList()
          : const [],
      pagination: PromoterPagination.fromJson(_map(json['pagination'])),
    );
  }
}

// ── Payouts ────────────────────────────────────────────

/// A mobile-money payout attempt: `pending`, `processing`, `paid` or `failed`.
class PromoterPayout {
  final String id;
  final String reference;
  final double amount;
  final String currency;
  final String status;

  /// Masked by the server.
  final String? phone;
  final int commissionCount;
  final String? failureReason;
  final DateTime? createdAt;
  final DateTime? processedAt;

  const PromoterPayout({
    required this.id,
    required this.reference,
    required this.amount,
    required this.currency,
    required this.status,
    this.phone,
    required this.commissionCount,
    this.failureReason,
    this.createdAt,
    this.processedAt,
  });

  factory PromoterPayout.fromJson(Map<String, dynamic> json) {
    return PromoterPayout(
      id: _string(json['id']),
      reference: _string(json['reference']),
      amount: _double(json['amount']),
      currency: _string(json['currency'], fallback: 'RWF'),
      status: _string(json['status']),
      phone: _nullableString(json['phone']),
      commissionCount: _int(json['commissionCount']),
      failureReason: _nullableString(json['failureReason']),
      createdAt: _date(json['createdAt']),
      processedAt: _date(json['processedAt']),
    );
  }

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';
}

/// `GET /promoter/payouts`
class PromoterPayoutsPage {
  final List<PromoterPayout> payouts;
  final PromoterPagination pagination;

  const PromoterPayoutsPage({required this.payouts, required this.pagination});

  factory PromoterPayoutsPage.fromJson(Map<String, dynamic> json) {
    final payouts = json['payouts'];
    return PromoterPayoutsPage(
      payouts: payouts is List
          ? payouts
                .whereType<Map<String, dynamic>>()
                .map(PromoterPayout.fromJson)
                .toList()
          : const [],
      pagination: PromoterPagination.fromJson(_map(json['pagination'])),
    );
  }
}

/// The promoter status values the UI needs to distinguish.
enum PromoterStatus {
  pending,
  active,
  suspended,
  unknown;

  static PromoterStatus parse(String? value) {
    // Normalized because this is the single place status strings become enum
    // values; the server sends lowercase but a hand-edited payload or a future
    // migration should not silently render as "Unknown".
    return switch (value?.trim().toLowerCase()) {
      'pending' => PromoterStatus.pending,
      'active' => PromoterStatus.active,
      'suspended' => PromoterStatus.suspended,
      _ => PromoterStatus.unknown,
    };
  }
}

/// Convenience for screens that only need to know if this user is a promoter.
bool userIsPromoter(Map<String, dynamic> userJson) {
  return AppRole.hasRole(userJson, AppRole.promoter);
}

// ── Lenient parsing helpers ────────────────────────────

/// The server serialises Mongoose money fields and dates loosely, so every read
/// goes through these instead of casting straight to `double`/`DateTime`.
Map<String, dynamic>? _map(dynamic value) {
  return value is Map<String, dynamic> ? value : null;
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

double _double(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _int(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

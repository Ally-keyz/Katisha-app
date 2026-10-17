/// Katisha Ticket Pricing Engine — client mirror.
///
/// MUST stay identical to `frontend/src/utils/serviceFee.ts` and
/// `server/src/utils/serviceFee.ts`. The backend is the source of truth for
/// the amount actually charged; the client mirrors the same engine so the
/// price shown in the wizard matches exactly what is charged.
///
/// Deterministic quote for a booking. Currency is RWF. The customer pays
/// `total_price` to us through pawaPay (a DEPOSIT); pawaPay takes a deposit fee
/// out of that total; the operator is paid EXACTLY the ticket price `T` (a
/// PAYOUT) and pawaPay takes a payout fee for that. Whatever is left must be at
/// least our service fee (3.5% of T):
///
///   total_price - deposit_fee - T (operator) - payout_fee >= service_fee
///
/// The customer's processing fee must cover BOTH the deposit fee and the payout
/// fee. Because the deposit fee is charged on the whole total (including the
/// service fee and the processing fee itself) the total is divided by
/// (1 - deposit_rate) instead of just adding a percentage.
///
/// MONEY RULES (never change):
///  - service_fee = round_half_up(T × serviceFeeRate); never discounted or waived.
///  - operator_payout is always exactly T; never more, never less.
///  - processing_fee = total_price − T − service_fee (covers deposit + payout),
///    computed by subtraction so the three parts always add up exactly.
///
/// The JavaScript engine works on `double` arithmetic and rounds half up with
/// `Math.floor(x + 0.5)`; every value here is kept as a double for parity and
/// only rounded to whole RWF where the TypeScript does.
library;

/// Supported mobile-money networks.
enum Mno { mtn, airtel }

/// Katisha ticket pricing configuration — mirrors TICKET_PRICING.
class TicketPricingConfig {
  /// Katisha service fee as a fraction of the ticket value.
  final double serviceFeeRate;

  /// Deposit transaction cost as a fraction of the customer total, per network.
  final Map<Mno, double> depositRate;

  /// Payout transaction cost as a fraction of the ticket value, per network.
  final Map<Mno, double> payoutRate;

  /// Fixed payout transaction cost in RWF, per network.
  final Map<Mno, double> payoutFixed;

  const TicketPricingConfig({
    required this.serviceFeeRate,
    required this.depositRate,
    required this.payoutRate,
    required this.payoutFixed,
  });
}

/// CONFIG — update here if pawaPay rates change.
///
///   deposit_rate : MTN = 2.1% MTN + 1% pawaPay = 3.1%
///                  AIRTEL = 1.5% Airtel + 1% pawaPay = 2.5%
///   payout_fixed : MTN = 60 RWF, AIRTEL = 0 RWF
///   payout_rate  : MTN = 1%, AIRTEL = 1%
const TicketPricingConfig ticketPricing = TicketPricingConfig(
  serviceFeeRate: 0.035,
  depositRate: {Mno.mtn: 0.031, Mno.airtel: 0.025},
  payoutRate: {Mno.mtn: 0.01, Mno.airtel: 0.01},
  payoutFixed: {Mno.mtn: 60, Mno.airtel: 0},
);

/// Coerce an unknown network label to a supported MNO (defaults to MTN).
Mno normalizeMno(String? value) {
  return (value ?? '').trim().toUpperCase() == 'AIRTEL' ? Mno.airtel : Mno.mtn;
}

/// Map a stored payment method ('mom' | 'airtel' | 'mpesa') to its network.
Mno mnoFromPaymentMethod(String? method) {
  return normalizeMno((method ?? '').toLowerCase() == 'airtel' ? 'AIRTEL' : 'MTN');
}

/// Round half up to the nearest whole RWF (`Math.floor(value + 0.5)`).
int roundHalfUp(double value) => (value + 0.5).floor();

/// Service fee = 3.5% of the ticket value, rounded half up.
int serviceFeeFor(num ticketPrice,
    [TicketPricingConfig config = ticketPricing]) {
  return roundHalfUp((ticketPrice.toDouble()) * config.serviceFeeRate);
}

/// The deterministic quote for a booking — mirrors `ticketQuote`.
class TicketQuote {
  final int ticketPrice;
  final int serviceFee;
  final int processingFee;
  final int totalPrice;
  final String currency;
  final Mno depositMno;
  final Mno payoutMno;
  final Settlement settlement;

  const TicketQuote({
    required this.ticketPrice,
    required this.serviceFee,
    required this.processingFee,
    required this.totalPrice,
    required this.currency,
    required this.depositMno,
    required this.payoutMno,
    required this.settlement,
  });
}

/// Settlement report — mirrors the `settlement` object of the TS quote.
class Settlement {
  final double depositFee;
  final int operatorPayout;
  final double payoutFee;
  final double serviceFeeKept;
  final bool serviceFeeProtected;

  const Settlement({
    required this.depositFee,
    required this.operatorPayout,
    required this.payoutFee,
    required this.serviceFeeKept,
    required this.serviceFeeProtected,
  });
}

/// Full deterministic quote for a request. `ticketPrice` is the operator's
/// total payable for the booking (unit price × seats). Throws
/// [ArgumentError] when the price is missing, zero, negative or not a number.
TicketQuote ticketQuote({
  required num ticketPrice,
  String? depositMno,
  String? payoutMno,
  TicketPricingConfig config = ticketPricing,
}) {
  final price = ticketPrice.toDouble();
  if (!price.isFinite || price <= 0) {
    throw ArgumentError('invalid ticket_price');
  }

  final deposit = normalizeMno(depositMno);
  final payout = normalizeMno(payoutMno);

  final serviceFee = roundHalfUp(price * config.serviceFeeRate);
  final operatorPayout = price;
  final payoutFee =
      config.payoutFixed[payout]! + config.payoutRate[payout]! * price;
  final depositRate = config.depositRate[deposit]!;

  // Gross up so the deposit fee (charged on the whole total) still leaves the
  // full service fee intact.
  var totalPrice = ((price + serviceFee + payoutFee) / (1 - depositRate)).ceilToDouble();
  var processingFee = totalPrice - price - serviceFee;

  // Mandatory settlement check: bump the total by 1 RWF until the deposit and
  // payout fees can never eat into the service fee.
  var depositFee = depositRate * totalPrice;
  var serviceFeeKept = totalPrice - depositFee - operatorPayout - payoutFee;
  var guard = 0;
  while (serviceFeeKept < serviceFee && guard < 1000) {
    totalPrice += 1;
    processingFee = totalPrice - price - serviceFee;
    depositFee = depositRate * totalPrice;
    serviceFeeKept = totalPrice - depositFee - operatorPayout - payoutFee;
    guard += 1;
  }

  return TicketQuote(
    ticketPrice: price.round(),
    serviceFee: serviceFee,
    processingFee: processingFee.round(),
    totalPrice: totalPrice.round(),
    currency: 'RWF',
    depositMno: deposit,
    payoutMno: payout,
    settlement: Settlement(
      depositFee: _round2(depositFee),
      operatorPayout: operatorPayout.round(),
      payoutFee: _round2(payoutFee),
      serviceFeeKept: _round2(serviceFeeKept),
      serviceFeeProtected: serviceFeeKept >= serviceFee,
    ),
  );
}

/// Round to 2 decimals for settlement reporting (`Math.round(v * 100) / 100`).
double _round2(double value) => (value * 100).roundToDouble() / 100;

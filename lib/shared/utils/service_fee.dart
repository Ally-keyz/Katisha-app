/// Katisha Service-Fee & Margin Pricing System - client mirror.
///
/// MUST stay identical to `frontend/src/utils/serviceFee.ts`. The backend is
/// the source of truth for the amount actually charged; the client mirrors
/// the same engine so the fee shown in the wizard matches exactly what is
/// charged.
///
/// The customer pays `Ticket Price + Service Fee`. Katisha keeps the service
/// fee as revenue and must cover two transaction costs on every booking:
///
///   Deposit cost = 1% of (Ticket Price + Service Fee)
///   Payout cost  = 1% of Ticket Price + 60 RWF
///
/// Pricing rules:
///  1. Every single ticket keeps its margin in a target band: 600-800 RWF on
///     low-value tickets, then 1.5k / 2.5k / 3k on 50k / 70k / 90k+ journeys.
///  2. The per-ticket fee is hard-capped at [maxFeePerTicket] so expensive
///     fares never scare the customer away with a huge service fee.
///  3. Multi-passenger discounts reduce the fee per seat, but the margin must
///     never fall below [minMarginRate] of the ticket value (the discount
///     floor).
library;

class PricingConfig {
  /// Deposit transaction cost as a fraction of the customer total.
  final double depositRate;

  /// Payout transaction cost as a fraction of the ticket value.
  final double payoutRate;

  /// Fixed payout cost in RWF per booking.
  final double payoutFixed;

  /// Margin target (RWF) for tickets below the first MARGIN_TARGET band.
  final double lowValueMargin;

  /// Lowest acceptable margin as a fraction of the ticket value.
  final double minMarginRate;

  /// Fees are always rounded up to this step (RWF).
  final double roundingStep;

  /// Hard cap on the service fee added per ticket (RWF).
  final double maxFeePerTicket;

  const PricingConfig({
    required this.depositRate,
    required this.payoutRate,
    required this.payoutFixed,
    required this.lowValueMargin,
    required this.minMarginRate,
    required this.roundingStep,
    required this.maxFeePerTicket,
  });
}

const PricingConfig defaultPricing = PricingConfig(
  depositRate: 0.01,
  payoutRate: 0.01,
  payoutFixed: 60,
  lowValueMargin: 700,
  minMarginRate: 0.01,
  roundingStep: 100,
  maxFeePerTicket: 5500,
);

/// Minimum Katisha margin per booking, keyed by ticket price (checked
/// highest-first):
///
///   price >= 90k   -> 3,000 RWF
///   price >= 70k   -> 2,500 RWF
///   price >= 50k   -> 1,500 RWF
///   otherwise      -> lowValueMargin (700 RWF - lands in 600-800 on cheap fares)
const List<({int minPrice, int margin})> marginTargets = [
  (minPrice: 90000, margin: 3000),
  (minPrice: 70000, margin: 2500),
  (minPrice: 50000, margin: 1500),
];

/// Margin target for a ticket price (band-based).
double targetMarginFor(num ticketPrice, [PricingConfig cfg = defaultPricing]) {
  final price = ticketPrice.toDouble();
  for (final band in marginTargets) {
    if (price >= band.minPrice) return band.margin.toDouble();
  }
  return cfg.lowValueMargin;
}

/// Effective minimum margin for a booking of [totalTicketValue] at a given
/// ticket price: the price-band target, floored by [minMarginRate] of the
/// total ticket value so a multi-passenger discount can never drag the margin
/// percentage below the floor.
double requiredMarginFor(num totalTicketValue, num ticketPrice,
    [PricingConfig cfg = defaultPricing]) {
  final value = totalTicketValue.toDouble();
  final target = targetMarginFor(ticketPrice, cfg);
  final floor = cfg.minMarginRate * value;
  return target > floor ? target : floor;
}

/// Round a fee up to the nearest [step] (default 100 RWF).
double roundFee(num fee, [num step = 100]) {
  if (step <= 0) return fee.roundToDouble();
  return ((fee / step).ceil() * step).toDouble();
}

/// Katisha margin for a booking-level fee over a given total ticket value.
///   Margin = (1 - depositRate) * Fee - (depositRate + payoutRate) * Value - payoutFixed
double marginFor(num bookingFee, num totalTicketValue,
    [PricingConfig cfg = defaultPricing]) {
  final fee = bookingFee.toDouble();
  final value = totalTicketValue.toDouble();
  return (1 - cfg.depositRate) * fee -
      (cfg.depositRate + cfg.payoutRate) * value -
      cfg.payoutFixed;
}

/// Minimum booking fee required to keep a target margin on a total ticket value.
///   Fee = (targetMargin + payoutFixed + (depositRate + payoutRate) * Value) / (1 - depositRate)
double requiredFeeForMargin(num totalTicketValue,
    [num targetMargin = 700, PricingConfig cfg = defaultPricing]) {
  final value = totalTicketValue.toDouble();
  final target = targetMargin.toDouble();
  return (target +
          cfg.payoutFixed +
          (cfg.depositRate + cfg.payoutRate) * value) /
      (1 - cfg.depositRate);
}

/// Single-ticket service fee, derived purely from the margin target and the
/// per-ticket cap. Used as the pre-discount base for multi-passenger bookings
/// and as the per-seat fee for display.
double singleSeatFee(num ticketPrice, [PricingConfig cfg = defaultPricing]) {
  final price = ticketPrice.toDouble();
  final fee = roundFee(
      requiredFeeForMargin(price, targetMarginFor(price, cfg), cfg),
      cfg.roundingStep);
  final capped = fee < cfg.maxFeePerTicket ? fee : cfg.maxFeePerTicket;
  return capped;
}

/// Multi-passenger discount rate for a seat count (1 when no discount applies).
double multiPassengerRate(num seats) {
  final n = seats >= 1 ? seats.floor() : 1;
  if (n <= 2) return 1;
  for (final tier in multiPassengerRates) {
    if (n >= tier.minSeats) return tier.rate;
  }
  return 1;
}

/// Multi-passenger discount tiers - bigger groups get a better per-seat fee.
const List<({int minSeats, double rate})> multiPassengerRates = [
  (minSeats: 6, rate: 0.65),
  (minSeats: 5, rate: 0.72),
  (minSeats: 4, rate: 0.78),
  (minSeats: 3, rate: 0.85),
];

/// Full booking-level service fee for a ticket price and passenger count.
double bookingServiceFee(num ticketPrice, num seats,
    [PricingConfig cfg = defaultPricing]) {
  final n = seats <= 0 ? 1 : seats.floor();
  final price = ticketPrice.toDouble();
  final totalValue = price * n;

  final rate = multiPassengerRate(n);
  final proposed = roundFee(singleSeatFee(price, cfg) * n * rate, cfg.roundingStep);
  final minFee = roundFee(
      requiredFeeForMargin(totalValue, requiredMarginFor(totalValue, price, cfg), cfg),
      cfg.roundingStep);

  final fee = proposed > minFee ? proposed : minFee;
  final cap = cfg.maxFeePerTicket * n;
  return fee < cap ? fee : cap;
}

/// Rwandan intercity journeys carry a flat 200 RWF system fee; every other
/// journey type uses the margin-driven booking fee.
double systemFeeFor(String? journeyType, num ticketPrice, num seats,
    [PricingConfig cfg = defaultPricing]) {
  if (journeyType == 'intercity') return intercityFlatFee;
  return bookingServiceFee(ticketPrice, seats, cfg);
}

const double intercityFlatFee = 200;

class PricingBreakdown {
  final int ticketPrice;
  final int seats;
  final int totalTicketValue;
  final int perTicketFee;
  final double multiPassengerRate;
  final int bookingFee;
  final int depositCost;
  final int payoutCost;
  final int margin;
  final int customerTotal;
  final bool marginPass;

  const PricingBreakdown({
    required this.ticketPrice,
    required this.seats,
    required this.totalTicketValue,
    required this.perTicketFee,
    required this.multiPassengerRate,
    required this.bookingFee,
    required this.depositCost,
    required this.payoutCost,
    required this.margin,
    required this.customerTotal,
    required this.marginPass,
  });
}

/// Full pricing breakdown for a booking - used for validation, display & audit.
PricingBreakdown pricingBreakdown(num ticketPrice, num seats,
    [PricingConfig cfg = defaultPricing]) {
  final n = seats <= 0 ? 1 : seats.floor();
  final price = ticketPrice.toDouble();
  final totalValue = price * n;
  final bookingFee = bookingServiceFee(price, n, cfg);
  final customerTotal = totalValue + bookingFee;
  final depositCost = (customerTotal * cfg.depositRate).round();
  final payoutCost = (totalValue * cfg.payoutRate).round() + cfg.payoutFixed.round();
  final margin = marginFor(bookingFee, totalValue, cfg);

  final required = requiredMarginFor(totalValue, price, cfg);
  final achievableUnderCap = marginFor(cfg.maxFeePerTicket * n, totalValue, cfg);
  final floor = required < achievableUnderCap ? required : achievableUnderCap;

  return PricingBreakdown(
    ticketPrice: price.round(),
    seats: n,
    totalTicketValue: totalValue.round(),
    perTicketFee: singleSeatFee(price, cfg).round(),
    multiPassengerRate: multiPassengerRate(n),
    bookingFee: bookingFee.round(),
    depositCost: depositCost,
    payoutCost: payoutCost,
    margin: margin.round(),
    customerTotal: customerTotal.round(),
    marginPass: margin >= floor,
  );
}

/// Full PawaPay processing fee - deposit cost + payout cost.
///
///   Deposit cost = depositRate * customerTotal  (PawaPay 1% + MTN 0.8791%)
///   Payout cost  = payoutRate * ticketValue + payoutFixed  (PawaPay 1% + 60 RWF)
int pawapayFee(num customerTotal, num ticketValue,
    {double depositRate = 0.018791,
    double payoutRate = 0.01,
    double payoutFixed = 60}) {
  final total = customerTotal.toDouble();
  final ticket = ticketValue.toDouble();
  if (total <= 0 && ticket <= 0) return 0;
  final depositCost = (total * depositRate).round();
  final payoutCost = (ticket * payoutRate).round() + payoutFixed.round();
  return depositCost + payoutCost;
}

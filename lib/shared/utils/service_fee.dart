/// Katisha Ticket Pricing Engine — client mirror.
///
/// MUST stay identical to `frontend/src/utils/serviceFee.ts` and
/// `server/src/utils/serviceFee.ts` (the backend is the source of truth for the
/// amount actually charged). The mobile wizard mirrors the same engine so the
/// price shown matches exactly what is charged and what the web shows.
///
/// Currency is RWF. The customer pays `totalPrice` as a DEPOSIT; pawaPay takes
/// a deposit fee out of that total; the operator is paid EXACTLY the ticket
/// price (a PAYOUT) and pawaPay takes a payout fee for that. Whatever is left
/// must be at least our service fee (3.5% of the ticket value):
///
///   totalPrice - depositFee - ticketPrice (operator) - payoutFee >= serviceFee
///
/// Because the deposit fee is charged on the whole total, the total is divided
/// by (1 - depositRate) instead of just adding a percentage.
///
/// MONEY RULES (never change):
///  - service_fee = round_half_up(T × serviceFeeRate); never discounted/waived.
///  - operator_payout is always exactly T; never more, never less.
///  - processing_fee = totalPrice − T − serviceFee (covers deposit + payout).
library;

import 'dart:math';

/// pawaPay/MTN/Airtel network labels.
enum Mno { mtn, airtel }

/// Coerce an unknown network label to a supported MNO (defaults to MTN).
Mno normalizeMno(String? value) =>
    (value ?? '').trim().toUpperCase() == 'AIRTEL' ? Mno.airtel : Mno.mtn;

/// Map a stored payment method ('mom' | 'airtel' | 'mpesa' …) to its network.
Mno mnoFromPaymentMethod(String? method) =>
    normalizeMno((method ?? '').toLowerCase() == 'airtel' ? 'AIRTEL' : 'MTN');

/// Round half up to the nearest whole RWF.
int roundHalfUp(num value) => (value + 0.5).floor();

// ── CONFIG — mirror of `TICKET_PRICING` in server/web serviceFee.ts ─────
//   deposit_rate : MTN = 2.1% MTN + 1% pawaPay = 3.1%
//                  AIRTEL = 1.5% Airtel + 1% pawaPay = 2.5%
//   payout_fixed : MTN = 60 RWF, AIRTEL = 0 RWF
//   payout_rate  : MTN = 1%, AIRTEL = 1%
const double _serviceFeeRate = 0.035;
const double _mtnDepositRate = 0.031;
const double _airtelDepositRate = 0.025;
const double _payoutRate = 0.01; // both networks
const double _mtnPayoutFixed = 60;
const double _airtelPayoutFixed = 0;

/// Service fee = 3.5% of the ticket value, rounded half up.
int serviceFeeFor(num ticketPrice) => roundHalfUp(ticketPrice * _serviceFeeRate);

/// Deterministic quote for a booking.
class TicketQuote {
  final int ticketPrice;
  final int serviceFee;
  final int processingFee;
  final int totalPrice;
  final Mno depositMno;
  final Mno payoutMno;

  const TicketQuote({
    required this.ticketPrice,
    required this.serviceFee,
    required this.processingFee,
    required this.totalPrice,
    required this.depositMno,
    required this.payoutMno,
  });
}

/// Full deterministic quote. [ticketPrice] is the operator's total payable for
/// the booking (unit price × seats). Throws when the price is missing/<= 0.
TicketQuote ticketQuote({
  required int ticketPrice,
  String? depositMno,
  String? payoutMno,
}) {
  if (ticketPrice <= 0) {
    throw ArgumentError.value(ticketPrice, 'ticketPrice', 'invalid ticket_price');
  }

  final deposit = normalizeMno(depositMno);
  final payout = normalizeMno(payoutMno);

  final serviceFee = serviceFeeFor(ticketPrice);
  final operatorPayout = ticketPrice;
  final payoutFee = (payout == Mno.mtn ? _mtnPayoutFixed : _airtelPayoutFixed) +
      _payoutRate * ticketPrice;
  final depositRate =
      deposit == Mno.mtn ? _mtnDepositRate : _airtelDepositRate;

  // Gross up so the deposit fee (charged on the whole total) still leaves the
  // full service fee intact.
  var totalPrice =
      ((ticketPrice + serviceFee + payoutFee) / (1 - depositRate)).ceil();
  var processingFee = totalPrice - ticketPrice - serviceFee;

  // Mandatory settlement check: bump the total by 1 RWF until the deposit and
  // payout fees can never eat into the service fee.
  var depositFee = depositRate * totalPrice;
  var serviceFeeKept = totalPrice - depositFee - operatorPayout - payoutFee;
  var guard = 0;
  while (serviceFeeKept < serviceFee && guard < 1000) {
    totalPrice += 1;
    processingFee = totalPrice - ticketPrice - serviceFee;
    depositFee = depositRate * totalPrice;
    serviceFeeKept = totalPrice - depositFee - operatorPayout - payoutFee;
    guard += 1;
  }

  return TicketQuote(
    ticketPrice: ticketPrice,
    serviceFee: serviceFee,
    processingFee: processingFee,
    totalPrice: totalPrice,
    depositMno: deposit,
    payoutMno: payout,
  );
}

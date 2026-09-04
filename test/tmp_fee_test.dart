import 'package:katisha/shared/utils/service_fee.dart';

void main() {
  final cases = [
    (price: 1000, seats: 1, type: 'intercity'),
    (price: 1000, seats: 2, type: 'east_africa'),
    (price: 3500, seats: 1, type: 'east_africa'),
    (price: 3500, seats: 5, type: 'east_africa'),
    (price: 50000, seats: 1, type: 'east_africa'),
    (price: 70000, seats: 1, type: 'east_africa'),
    (price: 90000, seats: 1, type: 'east_africa'),
    (price: 120000, seats: 1, type: 'east_africa'),
    (price: 3500, seats: 8, type: 'east_africa'),
  ];
  for (final c in cases) {
    final fee = systemFeeFor(c.type, c.price, c.seats);
    print('type=${c.type} price=${c.price} seats=${c.seats} -> fee=$fee');
  }
  // pricing breakdown sample
  final b = pricingBreakdown(3500, 5);
  print('breakdown: ${b.bookingFee} total=${b.customerTotal} pass=${b.marginPass}');
}

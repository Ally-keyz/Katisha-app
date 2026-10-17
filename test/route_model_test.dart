import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/shared/models/route_model.dart';

RouteModel _route({
  int price = 5000,
  int? effectivePrice,
  int? originalPrice,
  bool promotionActive = false,
  String? promotionLabel,
}) {
  return RouteModel(
    id: 'r1',
    agency: const RouteAgency(id: 'a1', name: 'Volcano'),
    type: 'east_africa',
    origin: 'Kigali',
    destination: 'Musanze',
    price: price,
    effectivePrice: effectivePrice,
    originalPrice: originalPrice,
    promotionActive: promotionActive,
    promotionLabel: promotionLabel,
    status: 'active',
  );
}

void main() {
  group('RouteModel pricing', () {
    test('routePrice falls back to price when effectivePrice is null', () {
      expect(_route(price: 7000).routePrice, 7000);
    });

    test('routePrice prefers effectivePrice when present', () {
      expect(_route(price: 7000, effectivePrice: 5000).routePrice, 5000);
    });
  });

  group('RouteModel promotion', () {
    test('is off when no promotion is active', () {
      expect(
        _route(originalPrice: 8000, effectivePrice: 5000).hasPromotion,
        isFalse,
      );
    });

    test('is off when the original price is not above the current fare', () {
      expect(
        _route(
          originalPrice: 5000,
          effectivePrice: 5000,
          promotionActive: true,
        ).hasPromotion,
        isFalse,
      );
    });

    test('is on when active and the original price is higher', () {
      expect(
        _route(
          originalPrice: 8000,
          effectivePrice: 5000,
          promotionActive: true,
        ).hasPromotion,
        isTrue,
      );
    });
  });

  group('RouteModel.fromJson', () {
    test('reads the promotion fields from the search payload', () {
      final route = RouteModel.fromJson({
        'id': 'r1',
        'type': 'east_africa',
        'origin': 'Kigali',
        'destination': 'Musanze',
        'price': 5000,
        'effectivePrice': 5000,
        'originalPrice': 8000,
        'promotionActive': true,
        'promotionLabel': 'Umuganura',
        'status': 'active',
        'agency': {'_id': 'a1', 'name': 'Volcano'},
      });

      expect(route.originalPrice, 8000);
      expect(route.promotionActive, isTrue);
      expect(route.promotionLabel, 'Umuganura');
      expect(route.hasPromotion, isTrue);
      expect(route.routePrice, 5000);
    });

    test('defaults promotion fields when the payload omits them', () {
      final route = RouteModel.fromJson({
        'price': 3000,
        'agency': {'_id': 'a1', 'name': 'Volcano'},
      });

      expect(route.originalPrice, isNull);
      expect(route.promotionActive, isFalse);
      expect(route.promotionLabel, isNull);
      expect(route.hasPromotion, isFalse);
    });

    test('round-trips promotion fields through toJson', () {
      final json = _route(
        originalPrice: 9000,
        effectivePrice: 6000,
        promotionActive: true,
        promotionLabel: 'Promo',
      ).toJson();

      expect(json['originalPrice'], 9000);
      expect(json['promotionActive'], isTrue);
      expect(json['promotionLabel'], 'Promo');
    });
  });
}

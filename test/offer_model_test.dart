import 'package:flutter_test/flutter_test.dart';
import 'package:motocar/models/offer.dart';

void main() {
  test('calcula duracao entre aceite e finalizacao', () {
    final offer = RideOffer(
      platform: RidePlatform.uber,
      fare: 10,
      pickupKm: 1,
      destinationKm: 4,
      detectedAt: DateTime(2026, 5, 28, 17),
      isWorthwhile: true,
      source: 'test',
      acceptedAt: DateTime(2026, 5, 28, 17, 10),
      completedAt: DateTime(2026, 5, 28, 17, 37),
    );

    expect(offer.rideDuration, const Duration(minutes: 27));
  });

  test('nao calcula duracao sem aceite e finalizacao', () {
    final offer = RideOffer(
      platform: RidePlatform.ninetyNine,
      fare: 10,
      pickupKm: 1,
      destinationKm: 4,
      detectedAt: DateTime(2026, 5, 28, 17),
      isWorthwhile: true,
      source: 'test',
    );

    expect(offer.rideDuration, isNull);
  });
}

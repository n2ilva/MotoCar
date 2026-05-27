import 'package:flutter_test/flutter_test.dart';
import 'package:motocar/models/driver_settings.dart';
import 'package:motocar/models/offer.dart';
import 'package:motocar/services/offer_parser.dart';

void main() {
  const parser = OfferParser();

  test('extrai uma oferta Uber e calcula valor por km', () {
    final offer = parser.parse(
      'Uber Comfort\nR\$ 32,50\nBuscar passageiro 2,5 km\nViagem 10 km',
      const DriverSettings(minimumFarePerKm: 1),
    );

    expect(offer?.platform, RidePlatform.uber);
    expect(offer?.fare, 32.5);
    expect(offer?.totalKm, 12.5);
    expect(offer?.farePerKm, closeTo(2.6, 0.001));
  });

  test('classifica 99 fora dos limites definidos', () {
    final offer = parser.parse(
      '99Pop R\$ 20,00\n4 km ate voce\n8 km corrida',
      const DriverSettings(maxPickupKm: 3),
    );

    expect(offer?.platform, RidePlatform.ninetyNine);
    expect(offer?.isWorthwhile, isFalse);
  });

  test('ignora OCR incompleto', () {
    expect(
      parser.parse('Uber R\$ 20,00 somente 3 km', const DriverSettings()),
      isNull,
    );
  });
}

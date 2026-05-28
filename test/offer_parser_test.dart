import 'package:flutter_test/flutter_test.dart';
import 'package:motocar/models/driver_settings.dart';
import 'package:motocar/models/offer.dart';
import 'package:motocar/services/offer_parser.dart';

void main() {
  const parser = OfferParser();

  test('extrai uma oferta Uber e calcula valor por km', () {
    final offer = parser.parse(
      'UberX\nR\$ 32,50\nBuscar passageiro 2,5 km\nViagem 10 km',
      const DriverSettings(minimumFarePerKm: 1),
    );

    expect(offer?.platform, RidePlatform.uber);
    expect(offer?.fare, 32.5);
    expect(offer?.totalKm, 12.5);
    expect(offer?.farePerKm, closeTo(2.6, 0.001));
  });

  test('classifica 99 fora dos limites definidos', () {
    final offer = parser.parse(
      'Oferta nova\nR\$ 20,00\n4 km ate voce\n8 km corrida',
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

  test('converte metros ate o passageiro para km', () {
    final offer = parser.parse(
      'UberX\nR\$ 10,00\n500 m ate voce\n4 km viagem',
      const DriverSettings(minimumFarePerKm: 1),
    );

    expect(offer?.pickupKm, 0.5);
    expect(offer?.destinationKm, 4);
    expect(offer?.farePerKm, closeTo(2.222, 0.001));
  });

  test('nao usa valor por km como distancia de destino', () {
    expect(
      parser.parse(
        'UberX\nR\$ 10,00\nR\$ 2,50 /km\n500 m ate voce',
        const DriverSettings(),
      ),
      isNull,
    );
  });

  test('nao identifica nome de rua do mapa sem solicitacao completa', () {
    expect(parser.parse('R. 7\nUberX\n500 m', const DriverSettings()), isNull);
  });

  test('ignora dados financeiros e distancias fora de card de solicitacao', () {
    expect(
      parser.parse(
        'Mapa aberto\nR\$ 18,00\n2 km avenida central\n7 km restante',
        const DriverSettings(),
      ),
      isNull,
    );
  });

  test('reconhece card 99 com marcadores de embarque e destino', () {
    final offer = parser.parse(
      '99Pop\nSolicitação\nR\$ 18,00\nAté você 500 m\nDestino 7 km',
      const DriverSettings(),
    );

    expect(offer?.platform, RidePlatform.ninetyNine);
    expect(offer?.pickupKm, 0.5);
    expect(offer?.destinationKm, 7);
  });

  test(
    'reconhece card visual da 99 com tempos e distancias entre parenteses',
    () {
      final offer = parser.parse(
        'Prioritário\nR\$8,50\nR\$1,63/km\nTarifa base dinâmica incl.\n'
        '4,97 • 312 corridas • Cartão verif.\n'
        '2min (596m)\nChiquinho Sorvetes\n'
        '9min (4,6km)\nCmei Professor Edival Calaça',
        const DriverSettings(),
      );

      expect(offer?.platform, RidePlatform.ninetyNine);
      expect(offer?.fare, 8.5);
      expect(offer?.pickupKm, closeTo(0.596, 0.001));
      expect(offer?.destinationKm, 4.6);
      expect(offer?.farePerKm, closeTo(1.635, 0.001));
    },
  );
}

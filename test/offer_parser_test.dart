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

  test('ignora painel do proprio app quando aparece sozinho no OCR', () {
    expect(
      parser.parse(
        '17:07 GOIANIA\n'
        '99 | R\$ 6,80 | Busca 2,10 km | Destino 3,50 km\n'
        'R\$ 1,21/km\n'
        'FORA DO LIMITE',
        const DriverSettings(),
      ),
      isNull,
    );
  });

  test('reconhece card real da 99 ignorando painel do proprio app', () {
    final offer = parser.parse(
      '17:07 GOIANIA\n'
      '99 | R\$ 6,80 | Busca 2,10 km | Destino 3,50 km\n'
      'R\$ 1,21/km\n'
      'FORA DO LIMITE\n'
      'R\$6,80\n'
      'R\$1,23/km\n'
      'R\$1,45 Tarifa base dinamica incl.\n'
      '4,92 641 corridas Perfil Premium\n'
      '4min (2,1km)\n'
      'Senador Canedo\n'
      '5min (3,5km)\n'
      'PSF Vila Sao Sebastiao, Av Senador Canedo',
      const DriverSettings(),
    );

    expect(offer?.platform, RidePlatform.ninetyNine);
    expect(offer?.fare, 6.8);
    expect(offer?.pickupKm, 2.1);
    expect(offer?.destinationKm, 3.5);
    expect(offer?.farePerKm, closeTo(1.214, 0.001));
  });

  test('ignora painel Uber do proprio app quando aparece sozinho no OCR', () {
    expect(
      parser.parse(
        'Uber | R\$ 6,42 | Busca 1,70 km | Destino 2,90 km\n'
        'R\$ 1,40/km\n'
        'VALE A PENA',
        const DriverSettings(),
      ),
      isNull,
    );
  });

  test('ignora painel UberX do proprio app quando aparece sozinho no OCR', () {
    expect(
      parser.parse(
        'UberX | R\$ 6,42 | Busca 1,70 km | Destino 2,90 km\n'
        'R\$ 1,40/km\n'
        'VALE A PENA',
        const DriverSettings(),
      ),
      isNull,
    );
  });

  test('reconhece card visual da Uber ignorando valor do mapa', () {
    final offer = parser.parse(
      '17:10 GOIANIA\nR\$7,10\nSecretaria de Esportes Senador Canedo\n'
      'UberX\nExclusivo\nR\$ 6,42\n4,93 (438)\nVerificado\n'
      '+10% de ganhos Uber Pro\n'
      '4 minutos (1.7 km) de distancia\n'
      'rua benjamin santos, Senador Canedo\n'
      'Viagem de 6 minutos (2.9 km)\n'
      '- Jardim Sevilha - Goiania - GO, 75250\n'
      'Aceitar',
      const DriverSettings(),
    );

    expect(offer?.platform, RidePlatform.uber);
    expect(offer?.fare, 6.42);
    expect(offer?.pickupKm, 1.7);
    expect(offer?.destinationKm, 2.9);
    expect(offer?.farePerKm, closeTo(1.395, 0.001));
  });

  test('reconhece card real da Uber ignorando painel do proprio app', () {
    final offer = parser.parse(
      'Uber | R\$ 6,42 | Busca 1,70 km | Destino 2,90 km\n'
      'R\$ 1,40/km\n'
      'VALE A PENA\n'
      'UberX\n'
      'Exclusivo\n'
      'R\$ 6,42\n'
      '4 minutos (1.7 km) de distancia\n'
      'rua benjamin santos, Senador Canedo\n'
      'Viagem de 6 minutos (2.9 km)\n'
      '- Jardim Sevilha - Goiania - GO, 75250',
      const DriverSettings(),
    );

    expect(offer?.platform, RidePlatform.uber);
    expect(offer?.fare, 6.42);
    expect(offer?.pickupKm, 1.7);
    expect(offer?.destinationKm, 2.9);
  });
}

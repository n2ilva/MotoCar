import '../models/driver_settings.dart';
import '../models/offer.dart';

class OfferParser {
  const OfferParser();

  // ---------------------------------------------------------------------------
  // Distâncias válidas obrigatoriamente aparecem entre parênteses no card,
  // ex: "(1,2 km)"  "(850 m)"  "(12,5 km)"
  // Isso evita capturar números de km que aparecem em badges de taxa média.
  // ---------------------------------------------------------------------------
  static final _distanceInParens = RegExp(
    r'\(\s*(\d+(?:[.,]\d+)?)\s*(km|m)\s*\)',
    caseSensitive: false,
  );

  static const _distanceValue = r'(\d+(?:[.,]\d+)?)\s*(km|m)';

  // Valor da corrida: R$ seguido de número, desde que NÃO seja taxa "/km".
  static final _farePattern = RegExp(
    r'r\$\s*(\d+(?:[.,]\d{1,2})?)(?![\d.,]|\s*/\s*km)',
  );

  static final _uberCardStart = RegExp(
    r'\b(uber\s*x|uberx|uber\s*moto|uber\s*flash|comfort|black)\b',
  );

  static final _nonUberCardStart = RegExp(
    r'\b(99pop|99|prioritario|solicitacao|oferta|nova corrida|chamada)\b',
  );

  static final _ninetyNineCardStart = RegExp(
    r'\b(99pop|prioritario|solicitacao|oferta|nova corrida|chamada|tarifa base|perfil premium|corridas)\b',
  );

  static final _ownOverlaySummary = RegExp(
    r'\b(?:uberx?|99)\s*\|\s*r\$\s*\d+(?:[.,]\d{1,2})?\s*\|\s*busca\s*'
    r'\d+(?:[.,]\d+)?\s*km\s*\|\s*destino\s*\d+(?:[.,]\d+)?\s*km\b',
    caseSensitive: false,
  );

  static final _pickupDistanceBeforeLabel = RegExp(
    '$_distanceValue\\s*(?:ate voce|ate o passageiro|ate passageiro|'
    'buscar passageiro|busca|de distancia|distancia)',
    caseSensitive: false,
  );

  static final _pickupDistanceAfterLabel = RegExp(
    '(?:ate voce|ate o passageiro|ate passageiro|buscar passageiro|'
    'busca|passageiro|embarque|coleta)\\D{0,30}$_distanceValue',
    caseSensitive: false,
  );

  static final _destinationDistanceBeforeLabel = RegExp(
    '$_distanceValue\\s*(?:viagem|corrida|destino|desembarque)',
    caseSensitive: false,
  );

  static final _destinationDistanceAfterLabel = RegExp(
    '(?:viagem|corrida|destino|desembarque)\\D{0,40}$_distanceValue',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Marcadores que indicam o início da seção de ação do card (parte inferior).
  // O texto acima do primeiro marcador é descartado para evitar ler badges
  // de taxa média que aparecem no topo (ex: "R$1,80/km" da 99).
  // ---------------------------------------------------------------------------
  static const _bottomMarkers = [
    'corrida',
    'viagem',
    'aceitar',
    'recusar',
    'rejeitar',
    'embarque',
    'desembarque',
    'destino',
    'passageiro',
    'buscar',
    'coleta',
    'solicitacao',
  ];

  // ---------------------------------------------------------------------------
  // Entrada pública
  // ---------------------------------------------------------------------------
  RideOffer? parse(
    String rawText,
    DriverSettings settings, {
    String source = 'monitor_android',
  }) {
    final normFull = _stripOwnOverlay(_normalise(rawText));

    // Plataforma é detectada no texto completo (o badge do topo ajuda).
    if (!_looksLikeRequestCard(normFull)) return null;
    final platform = _platform(normFull);

    // Descarta o topo do card para não capturar taxa média como valor de corrida.
    final text = _trimToOfferCard(normFull, platform);

    // --- Valor da corrida ---
    final fareMatch = _farePattern.firstMatch(text);
    if (fareMatch == null) return null;

    // --- Distâncias: aceita APENAS valores entre parênteses ---
    final detailsText = text.substring(fareMatch.end);
    final distances = _distances(detailsText);
    if (distances.length < 2) return null;

    final fare = _number(fareMatch.group(1)!);
    final pickup = distances[0];
    final destination = distances[1];
    if (fare <= 0 || pickup < 0 || destination <= 0) return null;

    final perKm = fare / (pickup + destination);

    return RideOffer(
      platform: platform,
      fare: fare,
      pickupKm: pickup,
      destinationKm: destination,
      detectedAt: DateTime.now(),
      isWorthwhile: settings.accepts(
        pickupKm: pickup,
        destinationKm: destination,
        farePerKm: perKm,
      ),
      source: source,
      rawText: rawText,
    );
  }

  // ---------------------------------------------------------------------------
  // Plataforma
  // ---------------------------------------------------------------------------
  RidePlatform _platform(String text) => RegExp(r'\buber\s*x\b').hasMatch(text)
      ? RidePlatform.uber
      : RidePlatform.ninetyNine;

  // ---------------------------------------------------------------------------
  // Validação: o texto parece um card de solicitação de corrida?
  // A checagem usa o texto COMPLETO (antes do trim) para aproveitar o topo.
  // ---------------------------------------------------------------------------
  bool _looksLikeRequestCard(String text) {
    // Uber: identificado pelo label "uber x"
    if (RegExp(r'\buber\s*x\b').hasMatch(text)) return true;

    // Qualquer plataforma: exige pelo menos 2 distâncias entre parênteses,
    // garantindo que é realmente um card com pickup + destino.
    final hasOfferMarker =
        _nonUberCardStart.hasMatch(text) ||
        RegExp(
          r'\b(aceitar|recusar|tarifa base|perfil premium|corridas)\b',
        ).hasMatch(text);
    if (hasOfferMarker && _farePattern.hasMatch(text)) {
      return _distances(text).length >= 2;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Extrai distâncias que estejam entre parênteses, ex: "(1,2 km)" "(800 m)".
  // Converte metros para km.
  // ---------------------------------------------------------------------------
  List<double> _distancesInParens(String text) {
    return _distanceInParens.allMatches(text).map((m) {
      final value = _number(m.group(1)!);
      return m.group(2)!.toLowerCase() == 'm' ? value / 1000 : value;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Descarta tudo antes do primeiro marcador de "parte inferior do card".
  // Isso remove badges de taxa média (ex: "R$1,80/km") que ficam no topo.
  // ---------------------------------------------------------------------------
  String _trimToOfferCard(String normText, RidePlatform platform) {
    if (platform == RidePlatform.uber) {
      final uberStart = _uberCardStart.firstMatch(normText);
      if (uberStart != null) return normText.substring(uberStart.start);
    }
    final ninetyNineStart = _ninetyNineCardStart.firstMatch(normText);
    if (ninetyNineStart != null) {
      RegExpMatch? fareBeforeMarker;
      for (final match in _farePattern.allMatches(
        normText.substring(0, ninetyNineStart.start),
      )) {
        fareBeforeMarker ??= match;
      }
      if (fareBeforeMarker != null) {
        return normText.substring(fareBeforeMarker.start);
      }
      return normText.substring(ninetyNineStart.start);
    }
    final nonUberStart = _nonUberCardStart.firstMatch(normText);
    if (nonUberStart != null) return normText.substring(nonUberStart.start);
    return _trimToBottom(normText);
  }

  String _stripOwnOverlay(String text) => text
      .replaceAll(_ownOverlaySummary, ' ')
      .replaceAll(RegExp(r'\b(?:vale a pena|fora do limite)\b'), ' ');

  String _trimToBottom(String normText) {
    int earliest = normText.length;
    for (final marker in _bottomMarkers) {
      final idx = normText.indexOf(marker);
      if (idx != -1 && idx < earliest) earliest = idx;
    }
    return earliest < normText.length ? normText.substring(earliest) : normText;
  }

  List<double> _distances(String text) {
    final inParens = _distancesInParens(text);
    if (inParens.length >= 2) return inParens;

    final pickup = _firstDistance(text, [
      _pickupDistanceBeforeLabel,
      _pickupDistanceAfterLabel,
    ]);
    final destination = _firstDistance(text, [
      _destinationDistanceAfterLabel,
      _destinationDistanceBeforeLabel,
    ]);
    if (pickup == null || destination == null) return inParens;
    return [pickup, destination];
  }

  double? _firstDistance(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      return _distanceFromMatch(match);
    }
    return null;
  }

  double _distanceFromMatch(RegExpMatch match) {
    for (var i = 1; i <= match.groupCount - 1; i++) {
      final value = match.group(i);
      final unit = match.group(i + 1);
      if (value == null || unit == null) continue;
      if (!RegExp(r'^\d').hasMatch(value)) continue;
      final distance = _number(value);
      return unit.toLowerCase() == 'm' ? distance / 1000 : distance;
    }
    throw StateError('Distance pattern did not expose value and unit groups.');
  }

  // ---------------------------------------------------------------------------
  // Normalização de acentos e quebras de linha
  // ---------------------------------------------------------------------------
  String _normalise(String text) => text
      .toLowerCase()
      .replaceAll('\u00e3', 'a')
      .replaceAll('\u00e1', 'a')
      .replaceAll('\u00e0', 'a')
      .replaceAll('\u00e2', 'a')
      .replaceAll('\u00e9', 'e')
      .replaceAll('\u00ea', 'e')
      .replaceAll('\u00ed', 'i')
      .replaceAll('\u00f3', 'o')
      .replaceAll('\u00f4', 'o')
      .replaceAll('\u00f5', 'o')
      .replaceAll('\u00fa', 'u')
      .replaceAll('\u00e7', 'c')
      .replaceAll('ã', 'a')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll('\n', ' ');

  double _number(String value) {
    if (value.contains(',')) {
      return double.parse(value.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.parse(value);
  }
}

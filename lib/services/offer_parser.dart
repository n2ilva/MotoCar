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

  // Valor da corrida: R$ seguido de número, desde que NÃO seja taxa "/km".
  static final _farePattern = RegExp(
    r'r\$\s*(\d+(?:[.,]\d{1,2})?)(?!\s*/\s*km)',
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
    final normFull = _normalise(rawText);

    // Plataforma é detectada no texto completo (o badge do topo ajuda).
    if (!_looksLikeRequestCard(normFull)) return null;
    final platform = _platform(normFull);

    // Descarta o topo do card para não capturar taxa média como valor de corrida.
    final text = _trimToBottom(normFull);

    // --- Valor da corrida ---
    final fareMatch = _farePattern.firstMatch(text);
    if (fareMatch == null) return null;

    // --- Distâncias: aceita APENAS valores entre parênteses ---
    final distances = _distancesInParens(text);
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
  RidePlatform _platform(String text) =>
      RegExp(r'\buber\s*x\b').hasMatch(text)
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
    if (_distancesInParens(text).length >= 2) {
      final hasOfferMarker = RegExp(
        r'\b(99|99pop|oferta|solicitacao|aceitar|recusar|nova corrida|chamada)\b',
      ).hasMatch(text);
      return hasOfferMarker;
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
  String _trimToBottom(String normText) {
    int earliest = normText.length;
    for (final marker in _bottomMarkers) {
      final idx = normText.indexOf(marker);
      if (idx != -1 && idx < earliest) earliest = idx;
    }
    return earliest < normText.length ? normText.substring(earliest) : normText;
  }

  // ---------------------------------------------------------------------------
  // Normalização de acentos e quebras de linha
  // ---------------------------------------------------------------------------
  String _normalise(String text) => text
      .toLowerCase()
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

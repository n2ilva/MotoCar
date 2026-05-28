import '../models/driver_settings.dart';
import '../models/offer.dart';

class OfferParser {
  const OfferParser();

  RideOffer? parse(
    String rawText,
    DriverSettings settings, {
    String source = 'monitor_android',
  }) {
    final text = _normalise(rawText);
    if (!_looksLikeRequestCard(text)) return null;

    final fareMatch = RegExp(r'r\$\s*(\d+(?:[.,]\d{2})?)').firstMatch(text);
    final distances = _distances(text);
    if (fareMatch == null || distances.length < 2) return null;

    final fare = _number(fareMatch.group(1)!);
    final pickup = distances[0];
    final destination = distances[1];
    if (fare <= 0 || pickup < 0 || destination <= 0) return null;
    final perKm = fare / (pickup + destination);

    return RideOffer(
      platform: _platform(text),
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

  RidePlatform _platform(String text) => RegExp(r'\buber\s*x\b').hasMatch(text)
      ? RidePlatform.uber
      : RidePlatform.ninetyNine;

  bool _looksLikeRequestCard(String text) {
    if (RegExp(r'\buber\s*x\b').hasMatch(text)) return true;

    final timedRouteLines = RegExp(
      r'\d+\s*min\s*\(\s*\d+(?:[.,]\d+)?\s*(?:km|m)\s*\)',
    ).allMatches(text);
    if (timedRouteLines.length >= 2) return true;

    final hasRequestMarker = RegExp(
      r'\b(99|99pop|oferta|solicitacao|aceitar|recusar|nova corrida|chamada)\b',
    ).hasMatch(text);
    final hasPickupMarker = RegExp(
      r'\b(ate voce|buscar|passageiro|embarque|coleta)\b',
    ).hasMatch(text);
    final hasDestinationMarker = RegExp(
      r'\b(viagem|corrida|destino|desembarque)\b',
    ).hasMatch(text);
    return hasRequestMarker && hasPickupMarker && hasDestinationMarker;
  }

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
      .replaceAll('ç', 'c');

  List<double> _distances(String text) {
    final matches = RegExp(r'(\d+(?:[.,]\d+)?)\s*(km|m)\b').allMatches(text);
    final distances = <double>[];
    for (final match in matches) {
      final before = text.substring(0, match.start).trimRight();
      if (before.endsWith('/') || before.endsWith('r\$')) continue;
      final value = _number(match.group(1)!);
      distances.add(match.group(2) == 'm' ? value / 1000 : value);
    }
    return distances;
  }

  double _number(String value) {
    if (value.contains(',')) {
      return double.parse(value.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.parse(value);
  }
}

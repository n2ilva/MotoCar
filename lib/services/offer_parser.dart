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
    final platform = _platform(text);
    final fareMatch = RegExp(r'r\$\s*(\d+(?:[.,]\d{2})?)').firstMatch(text);
    final kms = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*km',
    ).allMatches(text).map((match) => _number(match.group(1)!)).toList();
    if (platform == null || fareMatch == null || kms.length < 2) return null;

    final fare = _number(fareMatch.group(1)!);
    final pickup = kms[0];
    final destination = kms[1];
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

  RidePlatform? _platform(String text) {
    if (text.contains('uber')) return RidePlatform.uber;
    if (RegExp(r'(^|\D)99(\D|$)').hasMatch(text) || text.contains('99pop')) {
      return RidePlatform.ninetyNine;
    }
    return null;
  }

  String _normalise(String text) => text
      .toLowerCase()
      .replaceAll('ã', 'a')
      .replaceAll('á', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('\n', ' ');

  double _number(String value) {
    if (value.contains(',')) {
      return double.parse(value.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.parse(value);
  }
}

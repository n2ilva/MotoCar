enum RidePlatform { uber, ninetyNine }

class RideOffer {
  const RideOffer({
    this.id,
    required this.platform,
    required this.fare,
    required this.pickupKm,
    required this.destinationKm,
    required this.detectedAt,
    required this.isWorthwhile,
    required this.source,
    this.rawText = '',
    this.acceptedAt,
    this.completedAt,
  });

  final int? id;
  final RidePlatform platform;
  final double fare;
  final double pickupKm;
  final double destinationKm;
  final DateTime detectedAt;
  final bool isWorthwhile;
  final String source;
  final String rawText;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  double get totalKm => pickupKm + destinationKm;
  double get farePerKm => totalKm == 0 ? 0 : fare / totalKm;
  String get platformLabel => platform == RidePlatform.uber ? 'Uber' : '99';
  bool get accepted => acceptedAt != null;
  bool get completed => completedAt != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'platform': platform.name,
    'fare': fare,
    'pickup_km': pickupKm,
    'destination_km': destinationKm,
    'detected_at': detectedAt.toIso8601String(),
    'is_worthwhile': isWorthwhile ? 1 : 0,
    'source': source,
    'raw_text': rawText,
    'accepted_at': acceptedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };

  factory RideOffer.fromMap(Map<String, Object?> map) => RideOffer(
    id: map['id'] as int?,
    platform: RidePlatform.values.byName(map['platform']! as String),
    fare: (map['fare']! as num).toDouble(),
    pickupKm: (map['pickup_km']! as num).toDouble(),
    destinationKm: (map['destination_km']! as num).toDouble(),
    detectedAt: DateTime.parse(map['detected_at']! as String),
    isWorthwhile: (map['is_worthwhile']! as int) == 1,
    source: map['source']! as String,
    rawText: (map['raw_text'] as String?) ?? '',
    acceptedAt: map['accepted_at'] == null
        ? null
        : DateTime.parse(map['accepted_at']! as String),
    completedAt: map['completed_at'] == null
        ? null
        : DateTime.parse(map['completed_at']! as String),
  );
}

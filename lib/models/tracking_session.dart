class TrackingSession {
  const TrackingSession({
    this.id,
    required this.startedAt,
    this.finishedAt,
    this.distanceKm = 0,
  });

  final int? id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final double distanceKm;

  bool get active => finishedAt == null;

  Map<String, Object?> toMap() => {
    'id': id,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'distance_km': distanceKm,
  };

  factory TrackingSession.fromMap(Map<String, Object?> map) => TrackingSession(
    id: map['id'] as int?,
    startedAt: DateTime.parse(map['started_at']! as String),
    finishedAt: map['finished_at'] == null
        ? null
        : DateTime.parse(map['finished_at']! as String),
    distanceKm: (map['distance_km']! as num).toDouble(),
  );

  TrackingSession copyWith({DateTime? finishedAt, double? distanceKm}) =>
      TrackingSession(
        id: id,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        distanceKm: distanceKm ?? this.distanceKm,
      );
}

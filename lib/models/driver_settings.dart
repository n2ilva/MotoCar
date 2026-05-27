class DriverSettings {
  const DriverSettings({
    this.maxPickupKm = 3,
    this.maxDestinationKm = 50,
    this.minimumFarePerKm = 2.50,
    this.gasolinePrice = 6.20,
    this.ethanolPrice = 4.20,
    this.gasolineConsumption = 11,
    this.ethanolConsumption = 7.5,
    this.otherCostPerKm = 0.35,
  });

  final double maxPickupKm;
  final double maxDestinationKm;
  final double minimumFarePerKm;
  final double gasolinePrice;
  final double ethanolPrice;
  final double gasolineConsumption;
  final double ethanolConsumption;
  final double otherCostPerKm;

  double get gasolineCostPerKm => gasolinePrice / gasolineConsumption;
  double get ethanolCostPerKm => ethanolPrice / ethanolConsumption;
  bool get useEthanol => ethanolCostPerKm < gasolineCostPerKm;
  double get selectedFuelCostPerKm =>
      useEthanol ? ethanolCostPerKm : gasolineCostPerKm;
  double get operationCostPerKm => selectedFuelCostPerKm + otherCostPerKm;
  String get recommendedFuel => useEthanol ? 'Etanol' : 'Gasolina';

  bool accepts({
    required double pickupKm,
    required double destinationKm,
    required double farePerKm,
  }) =>
      pickupKm <= maxPickupKm &&
      destinationKm <= maxDestinationKm &&
      farePerKm >= minimumFarePerKm;

  Map<String, Object?> toMap() => {
    'id': 1,
    'max_pickup_km': maxPickupKm,
    'max_destination_km': maxDestinationKm,
    // Kept in the existing SQLite column to migrate installed copies safely.
    'min_profit_km': minimumFarePerKm,
    'gasoline_price': gasolinePrice,
    'ethanol_price': ethanolPrice,
    'gasoline_consumption': gasolineConsumption,
    'ethanol_consumption': ethanolConsumption,
    'other_cost_km': otherCostPerKm,
  };

  factory DriverSettings.fromMap(Map<String, Object?> map) => DriverSettings(
    maxPickupKm: (map['max_pickup_km']! as num).toDouble(),
    maxDestinationKm: (map['max_destination_km']! as num).toDouble(),
    minimumFarePerKm: (map['min_profit_km']! as num).toDouble(),
    gasolinePrice: (map['gasoline_price']! as num).toDouble(),
    ethanolPrice: (map['ethanol_price']! as num).toDouble(),
    gasolineConsumption: (map['gasoline_consumption']! as num).toDouble(),
    ethanolConsumption: (map['ethanol_consumption']! as num).toDouble(),
    otherCostPerKm: (map['other_cost_km']! as num).toDouble(),
  );

  DriverSettings copyWith({
    double? maxPickupKm,
    double? maxDestinationKm,
    double? minimumFarePerKm,
    double? gasolinePrice,
    double? ethanolPrice,
    double? gasolineConsumption,
    double? ethanolConsumption,
    double? otherCostPerKm,
  }) => DriverSettings(
    maxPickupKm: maxPickupKm ?? this.maxPickupKm,
    maxDestinationKm: maxDestinationKm ?? this.maxDestinationKm,
    minimumFarePerKm: minimumFarePerKm ?? this.minimumFarePerKm,
    gasolinePrice: gasolinePrice ?? this.gasolinePrice,
    ethanolPrice: ethanolPrice ?? this.ethanolPrice,
    gasolineConsumption: gasolineConsumption ?? this.gasolineConsumption,
    ethanolConsumption: ethanolConsumption ?? this.ethanolConsumption,
    otherCostPerKm: otherCostPerKm ?? this.otherCostPerKm,
  );
}

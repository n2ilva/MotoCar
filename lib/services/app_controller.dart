import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/driver_settings.dart';
import '../models/offer.dart';
import '../models/tracking_session.dart';
import 'android_monitor_bridge.dart';
import 'database_service.dart';
import 'offer_parser.dart';

class AppController extends ChangeNotifier {
  AppController({
    DatabaseService? database,
    AndroidMonitorBridge? monitor,
    OfferParser? parser,
  }) : _database = database ?? DatabaseService(),
       _monitor = monitor ?? AndroidMonitorBridge(),
       _parser = parser ?? const OfferParser();

  final DatabaseService _database;
  final AndroidMonitorBridge _monitor;
  final OfferParser _parser;

  DriverSettings settings = const DriverSettings();
  List<RideOffer> offers = [];
  List<TrackingSession> sessions = [];
  TrackingSession? currentSession;
  RideOffer? newestOffer;
  String? message;
  bool loading = true;
  bool screenMonitorRunning = false;
  bool tracking = false;

  StreamSubscription<Map<Object?, Object?>>? _offerSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  String? _lastFingerprint;
  DateTime? _lastDetectedAt;

  Future<void> initialise() async {
    settings = await _database.loadSettings();
    await _refreshHistory();
    screenMonitorRunning = await _monitor.isRunning();
    _offerSubscription = _monitor.offers.listen(_onNativeOffer);
    for (final map in await _monitor.pendingOffers()) {
      await _onNativeOffer(map);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _onNativeOffer(Map<Object?, Object?> map) async {
    final raw = (map['rawText'] as String?) ?? '';
    final parsed = _parser.parse(raw, settings, source: 'monitor_android');
    if (parsed == null) return;
    switch ((map['eventType'] as String?) ?? 'detected') {
      case 'accepted':
        await _markAccepted(parsed);
        return;
      case 'completed':
        await _markCompleted(parsed);
        return;
      default:
        await _recordOffer(parsed);
        return;
    }
  }

  Future<void> _recordOffer(RideOffer offer) async {
    final fingerprint =
        '${offer.platform.name}:${offer.fare}:${offer.pickupKm}:${offer.destinationKm}';
    final now = DateTime.now();
    if (_lastFingerprint == fingerprint &&
        _lastDetectedAt != null &&
        now.difference(_lastDetectedAt!).inSeconds < 12) {
      return;
    }
    _lastFingerprint = fingerprint;
    _lastDetectedAt = now;
    final inserted = await _database.insertOffer(offer);
    if (!inserted) return;
    newestOffer = offer;
    await _refreshHistory();
    notifyListeners();
  }

  Future<void> _markAccepted(RideOffer offer) async {
    if (!_containsOffer(offer)) {
      await _recordOffer(offer);
    }
    await _database.markAccepted(offer, DateTime.now());
    await _refreshHistory();
    message =
        '${offer.platformLabel} aceita. Trajeto iniciado automaticamente.';
    notifyListeners();
  }

  Future<void> _markCompleted(RideOffer offer) async {
    await _database.markCompleted(offer, DateTime.now());
    await _refreshHistory();
    message = '${offer.platformLabel} finalizada. Distancia salva.';
    notifyListeners();
  }

  bool _containsOffer(RideOffer candidate) => offers.any(
    (offer) =>
        offer.platform == candidate.platform &&
        offer.fare == candidate.fare &&
        offer.pickupKm == candidate.pickupKm &&
        offer.destinationKm == candidate.destinationKm,
  );

  Future<void> _refreshHistory() async {
    offers = await _database.loadOffers();
    sessions = await _database.loadSessions();
  }

  Future<void> saveSettings(DriverSettings updated) async {
    settings = updated;
    await _database.saveSettings(settings);
    await _monitor.updateSettings(settings);
    message = 'Parametros salvos.';
    notifyListeners();
  }

  Future<void> toggleAndroidScreenMonitor() async {
    if (screenMonitorRunning) {
      await _monitor.stop();
      screenMonitorRunning = false;
    } else {
      await _requestLocationPermissionForOverlay();
      screenMonitorRunning = await _monitor.start(settings);
      if (!screenMonitorRunning) {
        message = 'Autorize captura de tela e sobreposicao para iniciar.';
      }
    }
    notifyListeners();
  }

  Future<void> _requestLocationPermissionForOverlay() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      message =
          'Leitura funciona, mas o botao flutuante de trajeto precisa de localizacao.';
    }
  }

  Future<void> toggleTracking() async {
    if (tracking) {
      await _stopTracking();
    } else {
      await _startTracking();
    }
    notifyListeners();
  }

  Future<void> _startTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      message = 'Ative a localizacao do aparelho para monitorar distancia.';
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      message = 'Permissao de localizacao necessaria para medir trajeto.';
      return;
    }
    currentSession = await _database.startTrackingSession();
    tracking = true;
    _lastPosition = null;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_onPosition);
  }

  Future<void> _onPosition(Position position) async {
    if (!tracking || currentSession == null) return;
    var distance = currentSession!.distanceKm;
    if (_lastPosition != null) {
      distance +=
          Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          ) /
          1000;
    }
    _lastPosition = position;
    currentSession = currentSession!.copyWith(distanceKm: distance);
    await _database.updateTrackingSession(currentSession!);
    notifyListeners();
  }

  Future<void> _stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (currentSession != null) {
      currentSession = currentSession!.copyWith(finishedAt: DateTime.now());
      await _database.updateTrackingSession(currentSession!);
    }
    tracking = false;
    await _refreshHistory();
    notifyListeners();
  }

  void clearMessage() => message = null;

  void showMessage(String value) {
    message = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}

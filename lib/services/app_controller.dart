import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/driver_settings.dart';
import '../models/offer.dart';
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
  RideOffer? newestOffer;
  String? message;
  bool loading = true;
  bool screenMonitorRunning = false;

  StreamSubscription<Map<Object?, Object?>>? _offerSubscription;
  Future<void> _nativeOfferQueue = Future<void>.value();
  String? _lastFingerprint;
  DateTime? _lastDetectedAt;

  Future<void> initialise() async {
    settings = await _database.loadSettings();
    await _monitor.updateSettings(settings);
    await _refreshHistory();
    screenMonitorRunning = await _monitor.isRunning();
    _offerSubscription = _monitor.offers.listen(_queueNativeOffer);
    for (final map in await _monitor.pendingOffers()) {
      _queueNativeOffer(map);
    }
    await _nativeOfferQueue;
    loading = false;
    notifyListeners();
  }

  void _queueNativeOffer(Map<Object?, Object?> map) {
    _nativeOfferQueue = _nativeOfferQueue
        .then((_) => _onNativeOffer(map))
        .catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('Erro ao processar evento do monitor: $error');
          }
        });
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
    message = '${offer.platformLabel} aceita e salva.';
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
      screenMonitorRunning = await _monitor.start(settings);
      if (!screenMonitorRunning) {
        message = 'Autorize captura de tela e sobreposicao para iniciar.';
      }
    }
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
    super.dispose();
  }
}

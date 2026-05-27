import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/driver_settings.dart';

class AndroidMonitorBridge {
  static const _commands = MethodChannel('br.com.motocar/monitor_commands');
  static const _events = EventChannel('br.com.motocar/monitor_events');

  Stream<Map<Object?, Object?>> get offers {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .cast<Map<Object?, Object?>>();
  }

  Future<bool> start(DriverSettings settings) async {
    if (!Platform.isAndroid) return false;
    await updateSettings(settings);
    return await _commands.invokeMethod<bool>('startMonitoring') ?? false;
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      await _commands.invokeMethod<void>('stopMonitoring');
    }
  }

  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return await _commands.invokeMethod<bool>('isRunning') ?? false;
  }

  Future<void> updateSettings(DriverSettings settings) async {
    if (!Platform.isAndroid) return;
    await _commands.invokeMethod<void>('updateSettings', {
      'maxPickupKm': settings.maxPickupKm,
      'maxDestinationKm': settings.maxDestinationKm,
      'minimumFarePerKm': settings.minimumFarePerKm,
    });
  }

  Future<List<Map<Object?, Object?>>> pendingOffers() async {
    if (!Platform.isAndroid) return const [];
    final pending = await _commands.invokeListMethod<Object?>('pendingOffers');
    return (pending ?? const []).whereType<Map<Object?, Object?>>().toList();
  }
}

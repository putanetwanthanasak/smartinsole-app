import 'dart:async';

import 'package:flutter/foundation.dart';

import '../device/device_manager.dart';
import '../device/foot_sample.dart';
import 'daily_summary_repository.dart';
import 'temperature_repository.dart';

/// Writes every temperature reading from [DeviceManager.temps] as it
/// arrives, and keeps the day's max |ΔT| from the same ΔT the screens show
/// (null unless both feet are usable, rule 4).
class TemperatureRecorder {
  TemperatureRecorder({
    required this.manager,
    required this.temperatures,
    required this.summaries,
  });

  final DeviceManager manager;
  final TemperatureRepository temperatures;
  final DailySummaryRepository summaries;
  StreamSubscription<FootTemp>? _sub;

  /// Readings stored, and writes that failed (debug screen).
  int written = 0;
  int failed = 0;

  void start() => _sub ??= manager.temps.listen(_onTemp);

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onTemp(FootTemp t) async {
    // Taken before any await: the reading that just arrived is already in
    // the manager's state.
    final snapshot = manager.snapshot();
    final atMs = t.unixMs.round();
    try {
      await temperatures.add(
        side: t.side,
        atMs: atMs,
        celsius: t.packet.celsius,
        quality: t.packet.quality,
        timeFromArrival: t.fromArrival,
      );
      await summaries.recordDelta(atMs, snapshot.deltaC);
      written++;
    } catch (e) {
      // A storage error must never break the BLE path; count it.
      failed++;
      debugPrint('temperature write failed: $e');
    }
  }
}

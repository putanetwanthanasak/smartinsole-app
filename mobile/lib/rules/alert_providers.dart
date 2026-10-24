import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/capture_providers.dart';
import '../config/thresholds.dart';
import '../device/device_providers.dart';
import '../storage/storage_providers.dart';
import 'alert_engine.dart';
import 'gait_note.dart';

/// Model A's estimate per foot for the gait note (contract §8.3.1). S8A
/// overrides it; until then there is no estimate and no note.
final gaitEstimateProvider = Provider<GaitEstimateSource>(
  (ref) =>
      (_) => null,
);

/// The one alert engine, alive for the whole app (kept by `StorageHost`),
/// so a rule that starts to hold raises its alert whatever screen is open.
final alertEngineProvider = Provider<AlertEngine>((ref) {
  final engine = AlertEngine(
    manager: ref.watch(deviceManagerProvider),
    thresholds: ref.watch(thresholdsProvider),
    alerts: ref.watch(alertRepositoryProvider),
    captureStamp: () => ref.read(activeCaptureProvider),
    gait: ref.watch(gaitEstimateProvider),
  )..start();
  ref.onDispose(engine.stop);
  return engine;
});

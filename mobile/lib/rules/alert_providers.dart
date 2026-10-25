import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/packets.dart';
import '../capture/capture_providers.dart';
import '../config/thresholds.dart';
import '../device/device_providers.dart';
import '../storage/storage_providers.dart';
import 'alert_engine.dart';
import 'gait_note.dart';

/// Where the gait estimator (S8A, `lib/gait/`) plugs in. The estimator
/// listens to this engine's steps, so the engine cannot depend on it; the
/// estimator sets [source] instead when it starts.
class GaitEstimateHook {
  GaitEstimateSource? source;

  GaitEstimate? call(FootSide side) => source?.call(side);
}

final gaitEstimateHookProvider = Provider<GaitEstimateHook>(
  (ref) => GaitEstimateHook(),
);

/// Model A's estimate per foot for the gait note (contract §8.3.1): the
/// gait estimator's newest model result, fresh and at or above
/// `model.minConfidence`; rules never give a note (S8A, user decision
/// 2026-10-25). Null while no estimator runs.
final gaitEstimateProvider = Provider<GaitEstimateSource>(
  (ref) => ref.watch(gaitEstimateHookProvider).call,
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

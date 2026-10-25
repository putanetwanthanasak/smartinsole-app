import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/thresholds.dart';
import '../device/device_providers.dart';
import '../rules/alert_providers.dart';
import '../storage/storage_providers.dart';
import '../ui/clock.dart';
import 'demo_model_runner.dart';
import 'gait_estimator.dart';
import 'model_classifier.dart';
import 'model_spec.dart';
import 'step_counter.dart';
import 'tflite_classifier.dart';

/// `--dart-define=GAIT_MODEL=dummy` (the untrained dummy in
/// `assets/models_dummy/`) or `demo-toe` ([DemoModelRunner]); both are
/// ignored in release builds, which read only `assets/models/`.
const _gaitModelDefine = String.fromEnvironment('GAIT_MODEL');

/// Which model the app loads: a debug choice from [_gaitModelDefine], or
/// the release slot. Tests override it.
final gaitModelChoiceProvider = Provider<GaitModelChoice>(
  (ref) => gaitModelChoiceFor(_gaitModelDefine, releaseBuild: kReleaseMode),
);

enum GaitModelChoice { slot, dummy, demoToe }

GaitModelChoice gaitModelChoiceFor(
  String define, {
  required bool releaseBuild,
}) {
  if (releaseBuild || define.isEmpty) return GaitModelChoice.slot;
  return switch (define) {
    'dummy' => GaitModelChoice.dummy,
    'demo-toe' => GaitModelChoice.demoToe,
    _ => throw ArgumentError('unknown GAIT_MODEL "$define"'),
  };
}

/// Starts the real runner; tests override it (no LiteRT on the host).
final modelRunnerFactoryProvider = Provider<ModelRunnerFactory>(
  (ref) => TfliteModelRunner.start,
);

/// The model slot, loaded once.
final modelSlotProvider = FutureProvider<ModelSlot>((ref) async {
  final spec = ref.watch(modelInputSpecProvider);
  final slot = switch (ref.watch(gaitModelChoiceProvider)) {
    GaitModelChoice.demoToe => ModelReady(
      'demo-toe',
      ModelClassifier(
        runner: const DemoModelRunner(),
        normalization: demoNormalization(spec),
      ),
    ),
    final choice => await loadModelSlot(
      bundle: rootBundle,
      dir: choice == GaitModelChoice.dummy ? dummyModelDir : releaseModelDir,
      spec: spec,
      startRunner: ref.watch(modelRunnerFactoryProvider),
    ),
  };
  ref.onDispose(() {
    if (slot is ModelReady) slot.classifier.close();
  });
  return slot;
});

/// `check.json` run through the loaded model once (BLE debug screen's
/// "Gait model"); null when there is no model or no check file.
final modelCheckProvider = FutureProvider<ModelCheck?>((ref) async {
  final slot = await ref.watch(modelSlotProvider.future);
  if (slot is! ModelReady) return null;
  return runModelCheck(
    bundle: rootBundle,
    dir: slot.dir,
    classifier: slot.classifier,
  );
});

/// The one gait estimator, alive for the whole app (kept by
/// `StorageHost`).
final gaitEstimatorProvider = Provider<GaitEstimator>((ref) {
  final estimator = GaitEstimator(
    manager: ref.watch(deviceManagerProvider),
    engine: ref.watch(alertEngineProvider),
    thresholds: ref.watch(thresholdsProvider),
    spec: ref.watch(modelInputSpecProvider),
  )..start();
  ref.listen(
    modelSlotProvider,
    (_, next) => estimator.slot = next.value,
    fireImmediately: true,
  );
  // The alert engine's gait-note hook (contract §8.3.1).
  final hook = ref.watch(gaitEstimateHookProvider);
  final source = estimator.modelEstimateFor;
  hook.source = source;
  ref.onDispose(() {
    estimator.stop();
    if (hook.source == source) hook.source = null;
  });
  return estimator;
});

/// Today's steps, stored in `daily_summary.steps` (kept by `StorageHost`).
final stepCounterProvider = Provider<StepCounter>((ref) {
  final counter = StepCounter(
    steps: ref.watch(alertEngineProvider).steps,
    summaries: ref.watch(dailySummaryRepositoryProvider),
    dates: ref.watch(localDatesProvider),
    now: ref.watch(clockProvider),
  )..start();
  ref.onDispose(counter.stop);
  return counter;
});

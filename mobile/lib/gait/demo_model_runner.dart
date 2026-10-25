import 'dart:typed_data';

import 'gait_classifier.dart';
import 'gait_timing.dart';
import 'model_spec.dart';

/// DEBUG ONLY (`--dart-define=GAIT_MODEL=demo-toe`, never in release): a
/// stand-in for Model A that always answers toe walking at 78 %, so the
/// FeetDGaitToe board (model result, confidence, class probabilities) can
/// be shown on the emulator and the phone before a trained model exists.
/// Skipped by the no-literal test: these are demo outputs, not thresholds.
class DemoModelRunner implements ModelRunner {
  const DemoModelRunner();

  /// In `GaitClass` order: normal, antalgic, toe_walking, heel_walking,
  /// rotated_foot.
  static const probs = [0.06, 0.04, 0.78, 0.07, 0.05];

  @override
  Future<ModelOutput> run(Float32List window) async =>
      ModelOutput(probs: probs, embedding: List.filled(gaitEmbeddingSize, 0));

  @override
  Future<void> close() async {}
}

/// The identity z-score (mean 0, std 1) for [DemoModelRunner], which
/// ignores its input anyway.
Normalization demoNormalization(ModelInputSpec spec) => Normalization(
  channels: spec.channels,
  mean: List.filled(spec.channels.length, 0),
  std: List.filled(spec.channels.length, 1),
);

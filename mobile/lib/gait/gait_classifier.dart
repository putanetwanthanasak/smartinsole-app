import 'dart:typed_data';

import '../rules/step_detector.dart';
import 'gait_class.dart';

/// What a classifier gets every stride (DATA-CONTRACT §7.1: a 2 s window
/// each 1 s). Each implementation uses the part it needs.
class GaitInput {
  const GaitInput({
    required this.atMs,
    required this.leftSteps,
    required this.rightSteps,
    this.rows,
  });

  /// Unix ms of the newest sample both feet have.
  final double atMs;

  /// Each foot's walking steps of the current walk, oldest first
  /// (`StepDetector`, the same steps the alert rules count).
  final List<Step> leftSteps;
  final List<Step> rightSteps;

  /// The model window, raw 24-channel rows ([ModelWindowBuilder]); null
  /// when there is no complete window.
  final List<List<double>>? rows;
}

/// Classifies gait (contract §7.2's 5 classes). The Gait tab never knows
/// which implementation runs: the rules ([RuleBasedClassifier]) or Model A
/// ([ModelClassifier]); `GaitEstimator` picks.
abstract interface class GaitClassifier {
  /// The estimate for [input], or null when this classifier has none
  /// (too few steps, no complete window).
  Future<GaitResult?> classify(GaitInput input);
}

/// Model A's two outputs for one window (contract §7.2).
class ModelOutput {
  const ModelOutput({required this.probs, required this.embedding});

  /// `gait_probs` [5], softmax in [GaitClass] order.
  final List<double> probs;

  /// `gait_embedding` [32] (Model B's input; not used by the app yet).
  final List<double> embedding;
}

/// Runs Model A on one normalised window. The TFLite implementation runs
/// in its own isolate (`tflite_classifier.dart`); tests and the debug
/// `GAIT_MODEL=demo-toe` run use a fake.
abstract interface class ModelRunner {
  /// Runs one `[1, 100, 24]` float32 window. Callers never start a run
  /// before the previous one has completed.
  Future<ModelOutput> run(Float32List window);

  Future<void> close();
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gait_class.dart';
import 'gait_classifier.dart';
import 'gait_timing.dart';
import 'model_spec.dart';
import 'model_window.dart';

/// Model A (DATA-CONTRACT §7) as a [GaitClassifier]: z-scores the window
/// with the model's own `normalization.json`, runs it ([ModelRunner]) and
/// reads `gait_probs` (argmax = class, max = confidence, §7.2).
///
/// It returns the result whatever its confidence; `GaitEstimator` decides
/// whether it is shown (≥ `model.minConfidence`) or the rules take over.
class ModelClassifier implements GaitClassifier {
  ModelClassifier({required this.runner, required this.normalization});

  final ModelRunner runner;
  final Normalization normalization;

  /// Round-trip time of each run (window in → outputs back), for the BLE
  /// debug screen's "Gait model" section (contract §7.5: ≤ 100 ms).
  final stats = InferenceStats();

  bool _busy = false;
  Future<void> _last = Future.value();

  /// A run is in progress; a stride that comes now is skipped.
  bool get busy => _busy;

  @override
  Future<GaitResult?> classify(GaitInput input) async {
    final rows = input.rows;
    if (rows == null || _busy) return null;
    final out = await runRows(rows);
    return resultOf(out.probs, input.atMs);
  }

  /// Normalises and runs [rows] (raw 28-channel rows). Runs are queued,
  /// never overlapped: the runner answers one window at a time.
  Future<ModelOutput> runRows(List<List<double>> rows) {
    final window = normalizeWindow(rows, normalization);
    final run = _last.then((_) async {
      _busy = true;
      try {
        final sw = Stopwatch()..start();
        final out = await runner.run(window);
        stats.add(sw.elapsedMicroseconds);
        return out;
      } finally {
        _busy = false;
      }
    });
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// The §7.2 reading of [probs].
  static GaitResult resultOf(List<double> probs, double atMs) {
    var top = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[top]) top = i;
    }
    return GaitResult(
      gaitClass: GaitClass.values[top],
      source: GaitSource.model,
      atMs: atMs,
      confidence: probs[top],
      probs: List.unmodifiable(probs),
    );
  }

  Future<void> close() => runner.close();
}

/// Round-trip times of the newest runs.
class InferenceStats {
  final _us = <int>[];
  int _count = 0;

  void add(int us) {
    _count++;
    _us.add(us);
    if (_us.length > inferenceStatsKept) _us.removeAt(0);
  }

  /// Runs so far.
  int get count => _count;

  double? get lastMs => _us.isEmpty ? null : _ms(_us.last);

  double? get medianMs {
    if (_us.isEmpty) return null;
    final sorted = [..._us]..sort();
    return _ms(sorted[(sorted.length * 0.5).floor()]);
  }

  double? get maxMs =>
      _us.isEmpty ? null : _ms(_us.reduce((a, b) => a > b ? a : b));

  static double _ms(int us) => us / Duration.microsecondsPerMillisecond;
}

/// Where the model files are. Release builds read only [releaseModelDir]
/// (the slot for the model trained after data collection, late Nov);
/// debug and profile builds can be pointed at the dummy with
/// `--dart-define=GAIT_MODEL=dummy`.
const releaseModelDir = 'assets/models';
const dummyModelDir = 'assets/models_dummy';
const modelFileName = 'model_a.tflite';
const normalizationFileName = 'normalization.json';
const checkFileName = 'check.json';

/// The model slot's state.
sealed class ModelSlot {
  const ModelSlot(this.dir);

  /// The asset folder that was read.
  final String dir;
}

/// No `model_a.tflite`: the rules classify ("โมเดล AI ยังไม่พร้อม").
class ModelMissing extends ModelSlot {
  const ModelMissing(super.dir);
}

/// Files present but unusable; the rules classify, [reason] says why.
class ModelInvalid extends ModelSlot {
  const ModelInvalid(super.dir, this.reason);

  final String reason;
}

/// Loaded and checked against the contract's shapes.
class ModelReady extends ModelSlot {
  const ModelReady(super.dir, this.classifier);

  final ModelClassifier classifier;
}

/// Starts a runner for [model] bytes, or throws [FormatException] when its
/// tensors are not the contract's shapes.
typedef ModelRunnerFactory = Future<ModelRunner> Function(
  Uint8List model,
  ModelInputSpec spec,
);

/// Reads [dir]: `model_a.tflite` and `normalization.json` (checked against
/// [spec]), and starts the runner. Never throws: a problem is a
/// [ModelInvalid] with the reason, logged.
Future<ModelSlot> loadModelSlot({
  required AssetBundle bundle,
  required String dir,
  required ModelInputSpec spec,
  required ModelRunnerFactory startRunner,
}) async {
  final Uint8List model;
  try {
    model = (await bundle.load('$dir/$modelFileName')).buffer.asUint8List();
  } on Object {
    return ModelMissing(dir);
  }
  ModelSlot invalid(String reason) {
    debugPrint('Gait model in $dir not used: $reason');
    return ModelInvalid(dir, reason);
  }

  final String normJson;
  try {
    normJson = await bundle.loadString('$dir/$normalizationFileName');
  } on Object {
    return invalid('$normalizationFileName missing');
  }
  final Normalization norm;
  try {
    norm = Normalization.parse(normJson, spec);
  } on FormatException catch (e) {
    return invalid(e.message);
  } on Object catch (e) {
    return invalid('$normalizationFileName unreadable: $e');
  }
  try {
    final runner = await startRunner(model, spec);
    return ModelReady(
      dir,
      ModelClassifier(runner: runner, normalization: norm),
    );
  } on FormatException catch (e) {
    return invalid(e.message);
  } on Object catch (e) {
    return invalid('$modelFileName could not be loaded: $e');
  }
}

/// The result of running `check.json` (written by
/// `tools/model/make_dummy_model.py`) through the app's own code path:
/// normalisation, then the model on the device.
class ModelCheck {
  const ModelCheck({
    required this.windowMaxDiff,
    required this.probsMaxDiff,
    required this.embeddingMaxDiff,
  });

  /// Largest |app − Python| over the normalised window, the probabilities
  /// and the embedding.
  final double windowMaxDiff;
  final double probsMaxDiff;
  final double embeddingMaxDiff;

  /// Same input as Python (float32 rounding) and the same outputs.
  bool get passed =>
      windowMaxDiff <= checkWindowTolerance &&
      probsMaxDiff <= checkOutputTolerance &&
      embeddingMaxDiff <= checkOutputTolerance;
}

/// Runs `check.json` from [dir] through [classifier], or null when [dir]
/// has no check file (a real model ships without one).
Future<ModelCheck?> runModelCheck({
  required AssetBundle bundle,
  required String dir,
  required ModelClassifier classifier,
}) async {
  final String json;
  try {
    json = await bundle.loadString('$dir/$checkFileName');
  } on Object {
    return null;
  }
  final check = jsonDecode(json) as Map<String, dynamic>;
  List<double> floats(Object? list) => [
    for (final v in list! as List) (v as num).toDouble(),
  ];
  final rows = [for (final r in check['rows'] as List) floats(r)];
  final expectedWindow = [
    for (final r in check['window'] as List) ...floats(r),
  ];
  final window = normalizeWindow(rows, classifier.normalization);
  final out = await classifier.runRows(rows);
  return ModelCheck(
    windowMaxDiff: _maxDiff(window, expectedWindow),
    probsMaxDiff: _maxDiff(out.probs, floats(check['gait_probs'])),
    embeddingMaxDiff: _maxDiff(out.embedding, floats(check['gait_embedding'])),
  );
}

double _maxDiff(List<double> a, List<double> b) {
  if (a.length != b.length) return double.infinity;
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

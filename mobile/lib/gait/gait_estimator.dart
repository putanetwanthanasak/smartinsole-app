import 'dart:async';
import 'dart:ui';

import '../ble/packets.dart';
import '../config/thresholds.dart';
import '../device/device_manager.dart';
import '../device/foot_sample.dart' show FootBatch;
import '../device/rolling_peaks.dart';
import '../rules/alert_engine.dart';
import '../rules/gait_note.dart';
import '../rules/step_detector.dart';
import 'cop.dart';
import 'gait_class.dart';
import 'gait_classifier.dart';
import 'model_classifier.dart';
import 'model_spec.dart';
import 'model_window.dart';
import 'pti_asymmetry.dart';
import 'rule_based_classifier.dart';

/// Gait estimation for the whole app (kept alive by `StorageHost`, like
/// the alert engine): every stride (1 s of sample time) while both feet
/// walk, the model's result when it is loaded and confident, otherwise
/// the rules' result (DATA-CONTRACT §7.5).
///
/// - Inputs come from the 50 Hz path (rule 10): [DeviceManager.batches]
///   for the model window and the CoP, [AlertEngine.steps] for the rules,
///   the PTI asymmetry and the CoP's step boundaries.
/// - Strides and freshness are in sample time, never a timer (rule 2).
/// - The result is display only and the gait note's input; it never
///   changes a level (rule 11).
class GaitEstimator {
  GaitEstimator({
    required this.manager,
    required this.engine,
    required this.thresholds,
    required this.spec,
  }) : rules = RuleBasedClassifier(thresholds),
       _window = ModelWindowBuilder(spec),
       cop = CopTracker(keepMs: thresholds.maxStanceMs + spec.windowMs),
       ptiAsymmetry = PtiAsymmetry(windowMs: walkingPeakWindowMs);

  final DeviceManager manager;
  final AlertEngine engine;
  final Thresholds thresholds;
  final ModelInputSpec spec;
  final RuleBasedClassifier rules;
  final CopTracker cop;
  final PtiAsymmetry ptiAsymmetry;
  final ModelWindowBuilder _window;

  /// The model slot, once loaded (null while loading).
  ModelSlot? slot;
  final _walk = {for (final side in FootSide.values) side: <Step>[]};
  final _subs = <StreamSubscription<Object?>>[];
  final _newest = <FootSide, double>{};
  double? _lastStrideMs;
  GaitResult? _current;
  GaitResult? _last;
  GaitResult? _latestModel;

  ModelClassifier? get _model => switch (slot) {
    ModelReady(:final classifier) => classifier,
    _ => null,
  };

  void start() {
    _subs
      ..add(manager.batches.listen(_onBatch))
      ..add(engine.steps.listen(_onStep));
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Unix ms of the newest sample of either foot: the estimator's "now".
  /// Either foot, so a foot that stops cannot freeze it (its result then
  /// ages out, and the stride sees the foot is no longer usable).
  double? get newestMs {
    double? m;
    for (final t in _newest.values) {
      if (m == null || t > m) m = t;
    }
    return m;
  }

  /// The estimate to show now: the newest one, while it is no older than a
  /// window plus a stride; null when there is none (not walking, too few
  /// steps yet).
  GaitResult? get current {
    final c = _current;
    return c != null && _fresh(c) ? c : null;
  }

  /// The newest estimate ever shown, for "ผลล่าสุด" while not walking.
  /// Memory only.
  GaitResult? get last => _last;

  /// The gait note's input (contract §8.3.1): Model A's newest result,
  /// fresh and at or above `model.minConfidence`. Rules never give a note
  /// (user decision 2026-10-25). Model A classifies the whole gait, so
  /// both feet get the same estimate.
  GaitEstimate? modelEstimateFor(FootSide side) {
    final m = _latestModel;
    if (m == null || !_fresh(m)) return null;
    final confidence = m.confidence!;
    if (confidence < thresholds.minConfidence) return null;
    return GaitEstimate(gaitClass: m.gaitClass.id, confidence: confidence);
  }

  /// The newest step's centre-of-pressure path of [side].
  List<Offset>? copPathOf(FootSide side) => cop.pathOf(side);

  /// PTI asymmetry (percent) now; the caller shows it only while both feet
  /// are usable (rule 4).
  double? ptiAsymmetryPct() {
    final now = newestMs;
    return now == null ? null : ptiAsymmetry.pctAt(now);
  }

  bool _fresh(GaitResult r) {
    final now = newestMs;
    return now != null && now - r.atMs <= spec.windowMs + spec.strideMs;
  }

  void _onBatch(FootBatch b) {
    _window.add(b);
    cop.add(b);
    if (b.samples.isEmpty) return;
    _newest[b.side] = b.samples.last.unixMs;
    final now = newestMs!;
    final last = _lastStrideMs;
    if (last != null && now - last < spec.strideMs && now >= last) return;
    _lastStrideMs = now;
    _stride(now);
  }

  void _onStep(Step step) {
    cop.onStep(step);
    ptiAsymmetry.add(step);
    final walk = _walk[step.side]!;
    // A pause longer than a stance can last ends the walk: the rules judge
    // the current walk only.
    if (walk.isNotEmpty &&
        step.startMs - walk.last.endMs > thresholds.maxStanceMs) {
      walk.clear();
    }
    walk.add(step);
    if (walk.length > thresholds.gaitRuleSteps) walk.removeAt(0);
  }

  void _stride(double now) {
    final s = manager.snapshot();
    final walking =
        s.left.usable &&
        s.right.usable &&
        engine.walkingNow(FootSide.left) &&
        engine.walkingNow(FootSide.right);
    if (!walking) {
      _current = null;
      return;
    }
    final model = _model;
    final input = GaitInput(
      atMs: now,
      leftSteps: List.unmodifiable(_walk[FootSide.left]!),
      rightSteps: List.unmodifiable(_walk[FootSide.right]!),
      rows: model == null ? null : _window.latestRows(),
    );
    if (model == null) {
      _show(rules.classifyNow(input, because: RulesBecause.noModel));
      return;
    }
    if (input.rows == null || model.busy) return;
    model.classify(input).then((r) {
      if (r == null) return;
      _latestModel = r;
      if (r.confidence! >= thresholds.minConfidence) {
        _show(r);
      } else {
        _show(rules.classifyNow(input, because: RulesBecause.lowConfidence));
      }
      // A failed run shows nothing new; the previous result ages out.
    }, onError: (Object _) {});
  }

  void _show(GaitResult? r) {
    _current = r;
    if (r != null) _last = r;
  }

  /// Model or rules state for the debug screen.
  String describeSlot() => switch (slot) {
    null => 'loading',
    ModelMissing(:final dir) => 'no model in $dir (rules)',
    ModelInvalid(:final dir, :final reason) => 'invalid in $dir: $reason',
    ModelReady(:final dir) => 'ready ($dir)',
  };

  Future<void> close() async {
    stop();
    await _model?.close();
  }
}

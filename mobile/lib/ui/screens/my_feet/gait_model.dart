import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/thresholds.dart';
import '../../../device/device_providers.dart';
import '../../../device/display_snapshot.dart';
import '../../../device/rolling_load.dart';
import '../../../gait/gait_class.dart';
import '../../../gait/gait_estimator.dart';
import '../../../gait/gait_providers.dart';
import '../../../gait/step_counter.dart';
import '../../../rules/alert_engine.dart';
import '../../../rules/alert_providers.dart';
import '../../../rules/asymmetry.dart';
import '../home/home_model.dart' show balanceWindowMs;

/// "ตอนนี้" (§8.3): walking while either usable foot is walking (the
/// engine's walking gate), "—" while no foot is usable.
enum GaitActivity { walking, still, noData }

/// The estimate on screen, rounded to what is shown, so it changes at
/// most once per stride.
@immutable
class GaitEstimateView {
  const GaitEstimateView({
    required this.gaitClass,
    required this.source,
    this.because,
    this.confidencePct,
    this.high = false,
    this.probsPct,
  });

  factory GaitEstimateView.of(GaitResult r, Thresholds t) {
    final c = r.confidence;
    return GaitEstimateView(
      gaitClass: r.gaitClass,
      source: r.source,
      because: r.because,
      confidencePct: c == null ? null : (c * 100).round(),
      high: c != null && c >= t.highConfidence,
      probsPct: r.probs == null
          ? null
          : [for (final p in r.probs!) (p * 100).round()],
    );
  }

  final GaitClass gaitClass;
  final GaitSource source;
  final RulesBecause? because;

  /// Model only: the top class's probability, whole percent.
  final int? confidencePct;

  /// Model only: at or above `model.highConfidence` (3 segments, "สูง").
  final bool high;

  /// Model only: every class's probability, whole percent, [GaitClass]
  /// order.
  final List<int>? probsPct;

  bool get fromModel => source == GaitSource.model;

  @override
  bool operator ==(Object other) =>
      other is GaitEstimateView &&
      other.gaitClass == gaitClass &&
      other.source == source &&
      other.because == because &&
      other.confidencePct == confidencePct &&
      other.high == high &&
      listEquals(other.probsPct, probsPct);

  @override
  int get hashCode => Object.hash(
    gaitClass,
    source,
    because,
    confidencePct,
    high,
    probsPct == null ? null : Object.hashAll(probsPct!),
  );
}

/// "ผลล่าสุด HH:mm · {class}" while there is no estimate now.
@immutable
class GaitLastView {
  const GaitLastView({
    required this.at,
    required this.gaitClass,
    required this.fromRules,
  });

  /// Sample time of the estimate, to the minute.
  final DateTime at;
  final GaitClass gaitClass;
  final bool fromRules;

  @override
  bool operator ==(Object other) =>
      other is GaitLastView &&
      other.at == at &&
      other.gaitClass == gaitClass &&
      other.fromRules == fromRules;

  @override
  int get hashCode => Object.hash(at, gaitClass, fromRules);
}

/// Everything the Gait tab shows except the balance card, which reads
/// Home's view so the two screens always agree (§8.3, S8A default).
@immutable
class GaitView {
  const GaitView({
    required this.activity,
    required this.bothUsable,
    required this.stepsToday,
    this.estimate,
    this.last,
    this.walkingPaiPct,
    this.standingPaiPct,
    this.ptiAsymmetryPct,
    this.copLeft,
    this.copRight,
  });

  static const initial = GaitView(
    activity: GaitActivity.noData,
    bothUsable: false,
    stepsToday: 0,
  );

  final GaitActivity activity;
  final bool bothUsable;

  /// Both feet's walking steps today (`daily_summary.steps`).
  final int stepsToday;

  /// The estimate now; null when not walking or too few steps yet.
  final GaitEstimateView? estimate;

  /// The newest earlier estimate, only while [estimate] is null.
  final GaitLastView? last;

  /// The engine's latest step-pair PAI (what `ASYMMETRY_PEAK` compares),
  /// whole percent; null unless both feet are usable (rule 4).
  final int? walkingPaiPct;

  /// "ความไม่สมดุลของแรงกดขณะยืน": the PAI formula on the two feet's mean
  /// loads over Home's balance window, whole percent; null unless both
  /// feet are usable and loaded.
  final int? standingPaiPct;

  /// PTI asymmetry over the last 5 minutes, whole percent; display only,
  /// null unless both feet are usable.
  final int? ptiAsymmetryPct;

  /// Each foot's CoP path in its latest step (view-box units).
  final List<Offset>? copLeft;
  final List<Offset>? copRight;

  List<Offset>? cop(FootSide s) => s == FootSide.left ? copLeft : copRight;

  @override
  bool operator ==(Object other) =>
      other is GaitView &&
      other.activity == activity &&
      other.bothUsable == bothUsable &&
      other.stepsToday == stepsToday &&
      other.estimate == estimate &&
      other.last == last &&
      other.walkingPaiPct == walkingPaiPct &&
      other.standingPaiPct == standingPaiPct &&
      other.ptiAsymmetryPct == ptiAsymmetryPct &&
      listEquals(other.copLeft, copLeft) &&
      listEquals(other.copRight, copRight);

  @override
  int get hashCode => Object.hash(
    activity,
    bothUsable,
    stepsToday,
    estimate,
    last,
    walkingPaiPct,
    standingPaiPct,
    ptiAsymmetryPct,
    copLeft == null ? null : Object.hashAll(copLeft!),
    copRight == null ? null : Object.hashAll(copRight!),
  );
}

/// Builds [GaitView] on each 10 Hz snapshot from the gait estimator, the
/// step counter and the alert engine (all fed by the 50 Hz path, rule 10).
/// The state only changes when something shown changes.
class GaitController extends Notifier<GaitView> {
  final _loads = {
    for (final s in FootSide.values) s: RollingLoad(windowMs: balanceWindowMs),
  };

  @override
  GaitView build() {
    final manager = ref.watch(deviceManagerProvider);
    final thresholds = ref.watch(thresholdsProvider);
    final engine = ref.watch(alertEngineProvider);
    final estimator = ref.watch(gaitEstimatorProvider);
    final counter = ref.watch(stepCounterProvider);
    GaitView viewOf(DisplaySnapshot s) => gaitViewOf(
      s,
      thresholds: thresholds,
      engine: engine,
      estimator: estimator,
      counter: counter,
      meanLoads: {
        for (final side in FootSide.values) side: _loads[side]!.meanLoad(),
      },
    );
    final subs = <StreamSubscription<Object?>>[
      manager.batches.listen((b) => _loads[b.side]!.add(b)),
      manager.snapshots.listen((s) {
        final next = viewOf(s);
        if (next != state) state = next;
      }),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });
    return viewOf(manager.snapshot());
  }
}

final gaitViewProvider = NotifierProvider<GaitController, GaitView>(
  GaitController.new,
);

/// What the Gait tab shows for [s]. Two-foot values need both feet
/// usable (rule 4); nothing here sets a level (rule 11).
GaitView gaitViewOf(
  DisplaySnapshot s, {
  required Thresholds thresholds,
  required AlertEngine engine,
  required GaitEstimator estimator,
  required StepCounter counter,
  Map<FootSide, double?> meanLoads = const {},
}) {
  final feet = [s.left, s.right].where((f) => f.usable).toList();
  final both = feet.length == FootSide.values.length;
  final activity = feet.isEmpty
      ? GaitActivity.noData
      : feet.any((f) => engine.walkingNow(f.side))
      ? GaitActivity.walking
      : GaitActivity.still;
  final current = both ? estimator.current : null;
  final previous = current == null ? estimator.last : null;
  final pai = engine.latestPaiPct;
  final pti = estimator.ptiAsymmetryPct();
  final l = meanLoads[FootSide.left];
  final r = meanLoads[FootSide.right];
  final standing = both && l != null && r != null && l + r > 0
      ? paiPercent(l, r)
      : null;
  return GaitView(
    activity: activity,
    bothUsable: both,
    stepsToday: counter.todayAt(s.at.millisecondsSinceEpoch),
    estimate: current == null ? null : GaitEstimateView.of(current, thresholds),
    last: previous == null
        ? null
        : GaitLastView(
            at: _minuteOf(previous.atMs),
            gaitClass: previous.gaitClass,
            fromRules: previous.source == GaitSource.rules,
          ),
    walkingPaiPct: both && pai != null ? pai.round() : null,
    standingPaiPct: standing?.round(),
    ptiAsymmetryPct: both && pti != null ? pti.round() : null,
    copLeft: s.left.usable ? estimator.copPathOf(FootSide.left) : null,
    copRight: s.right.usable ? estimator.copPathOf(FootSide.right) : null,
  );
}

DateTime _minuteOf(double unixMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixMs.round());
  return DateTime(t.year, t.month, t.day, t.hour, t.minute);
}

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../ble/link_state.dart';
import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../device/device_manager.dart';
import '../device/display_snapshot.dart';
import '../device/foot_sample.dart';
import '../device/rolling_peaks.dart';
import '../storage/alert_repository.dart';
import '../storage/models.dart' show AlertKind, NewAlert;
import 'alert_code.dart';
import 'asymmetry.dart';
import 'gait_note.dart';
import 'patient_status.dart';
import 'pressure_level.dart';
import 'step_detector.dart';
import 'walking_gate.dart';

/// One rule that holds now: code + side + zone or site, with the value
/// that crossed the threshold.
@immutable
class AlertCondition {
  const AlertCondition({
    required this.code,
    required this.side,
    this.channel,
    this.site,
    required this.value,
    required this.threshold,
    this.details = const {},
  });

  final AlertCode code;

  /// The foot it is about; for `TEMP_DELTA` the warmer foot, for
  /// `ASYMMETRY_PEAK` the foot with the higher peak.
  final FootSide side;

  /// FSR channel for the pressure codes.
  final int? channel;

  /// Temperature site for `TEMP_DELTA`.
  final TempSite? site;

  /// In the code's unit: kPa, kPa·s, %, °C, minutes.
  final double value;
  final double threshold;

  /// The numbers for the detail rows (DESIGN-SPEC §7.3).
  final Map<String, Object?> details;

  String get key => alertKey(code, side, channel: channel, site: site);

  /// How far past its threshold, for picking between two of one code.
  double get ratio => value / threshold;

  StatusCause get cause => StatusCause(
    code: code,
    side: side,
    channel: channel,
    site: site,
    deltaC: code == AlertCode.tempDelta ? value : null,
  );

  @override
  bool operator ==(Object other) =>
      other is AlertCondition &&
      other.key == key &&
      other.value == value &&
      other.threshold == threshold;

  @override
  int get hashCode => Object.hash(key, value, threshold);
}

/// My feet's per-foot pressure numbers (DESIGN-SPEC §8.1 "ดูตัวเลขละเอียด"),
/// from the engine's own walking gate and step detector (user decision
/// 2026-10-25). Display only: none of them is compared with a threshold
/// here. Null when the foot has no such figure yet.
@immutable
class PressureFigures {
  const PressureFigures({
    this.walkingPeakKpa,
    this.ptiKpaS,
    this.ptiSteps = 0,
    this.concentrationPct,
  });

  static const none = PressureFigures();

  /// Highest zone kPa of the samples taken while walking (the gate on) in
  /// the last [walkingPeakWindowMs].
  final double? walkingPeakKpa;

  /// The highest zone's mean per-step PTI over the steps of the last
  /// `pressure.ptiWindowMin`: the number `PRESSURE_PTI` compares
  /// (decision 4: shown only in the details).
  final double? ptiKpaS;
  final int ptiSteps;

  /// The highest per-step top-zone share (`LOAD_CONCENTRATION`'s
  /// measure) among the walking steps of the last [walkingPeakWindowMs].
  final double? concentrationPct;

  @override
  bool operator ==(Object other) =>
      other is PressureFigures &&
      other.walkingPeakKpa == walkingPeakKpa &&
      other.ptiKpaS == ptiKpaS &&
      other.ptiSteps == ptiSteps &&
      other.concentrationPct == concentrationPct;

  @override
  int get hashCode =>
      Object.hash(walkingPeakKpa, ptiKpaS, ptiSteps, concentrationPct);
}

/// What the rules say about one snapshot.
@immutable
class RulesView {
  const RulesView({required this.status, required this.conditions});

  final PatientStatus status;
  final List<AlertCondition> conditions;

  /// `ASYMMETRY_PEAK` while it holds: Home's balance note turns orange and
  /// names its foot (BACKLOG 37).
  AlertCondition? get asymmetry {
    for (final c in conditions) {
      if (c.code == AlertCode.asymmetryPeak) return c;
    }
    return null;
  }

  /// The condition among [codes] that would name the status (the same
  /// ranking as Home: [AlertEngine.ranksAbove]), or null when none holds.
  AlertCondition? top(Set<AlertCode> codes) {
    AlertCondition? best;
    for (final c in conditions) {
      if (!codes.contains(c.code)) continue;
      if (best == null || AlertEngine.ranksAbove(c, best)) best = c;
    }
    return best;
  }
}

/// The 8 alert rules of DATA-CONTRACT v1.5 §8.3, the status they set
/// (FLUTTER-PLAN §7), and the alerts they raise.
///
/// - Per-sample work runs on the 50 Hz path ([DeviceManager.batches],
///   rule 10): the walking gate (§8.3.2), step detection, peaks and PTI.
/// - Whether a rule holds is derived from timestamps whenever it is asked
///   ([conditions]), never latched by a timer (rule 2). The rules are
///   checked on every packet and reading, and once per [checkEvery] for
///   the rules that need no data to change (`DEVICE_LOST`).
/// - A rule that starts to hold raises an alert, unless the same alert
///   (code + side + zone or site) was raised in the last `alerts.repeatMin`
///   (contract §8.5). That memory comes from the alerts table, so it holds
///   across an app restart.
/// - Every number comes from `thresholds.json` (rule 12; a test fails on a
///   numeric literal in `lib/rules/`).
///
/// Two-foot rules (`TEMP_DELTA`, `ASYMMETRY_PEAK`) hold only while both
/// feet are usable (rule 4).
class AlertEngine {
  AlertEngine({
    required this.manager,
    required this.thresholds,
    required this.alerts,
    this.captureStamp,
    this.gait,
    this.checkEvery = const Duration(seconds: 1),
    this.figuresWindowMs = walkingPeakWindowMs,
  });

  final DeviceManager manager;
  final Thresholds thresholds;
  final AlertRepository alerts;

  /// The research capture running now, as its stamp (BACKLOG 40).
  final String? Function()? captureStamp;

  /// Model A's estimate per foot (contract §8.3.1); null until S8A.
  final GaitEstimateSource? gait;
  final Duration checkEvery;

  /// The window of [pressureFigures]' walking peak and single-point share.
  final int figuresWindowMs;

  late final _feet = {
    for (final side in FootSide.values)
      side: _FootRules(side, thresholds, figuresWindowMs),
  };

  /// Home's foot-map window per foot, so a pressure alert stores the map
  /// the patient saw when it was raised (`details.map`).
  final _mapPeaks = {
    for (final side in FootSide.values)
      side: RollingPeaks(windowMs: mapPeakWindowMs),
  };
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;

  // TEMP_DELTA: consecutive reading pairs above deltaC, per site (rule 6).
  final _tempFresh = {FootSide.left: false, FootSide.right: false};
  final _overCount = {TempSite.forefoot: 0, TempSite.heel: 0};

  // ASYMMETRY_PEAK: consecutive steps above peakPct.
  int _asymSteps = 0;
  double _asymLeftKpa = 0;
  double _asymRightKpa = 0;

  // DEVICE_LOST: when each foot's newest packet arrived in this run, and
  // its battery then.
  final _lastArrival = <FootSide, DateTime>{};
  final _lastBattery = <FootSide, int>{};

  // Raising.
  Set<String> _active = {};
  final _lastRaisedMs = <String, int>{};
  bool _seeded = false;
  final _beforeSeed =
      <(AlertCondition, DisplaySnapshot, List<AlertCondition>)>[];
  final _writes = <Future<void>>{};

  /// Consecutive reading pairs above `deltaC` at [site] (for tests).
  int overCount(TempSite site) => _overCount[site]!;

  /// Consecutive steps above `asymmetry.peakPct` (for tests).
  int get asymmetrySteps => _asymSteps;

  /// Completes when every alert raised so far is stored.
  Future<void> flush() async {
    while (_writes.isNotEmpty) {
      await Future.wait(_writes.toList());
    }
  }

  /// Starts listening. The suppression memory is read from the alerts
  /// table first; anything that rises before then waits for it.
  void start() {
    _subs
      ..add(manager.batches.listen(_onBatch))
      ..add(manager.temps.listen(_onTemp));
    _timer = Timer.periodic(checkEvery, (_) => check());
    final seed = _seedSuppression();
    _writes.add(seed);
    seed.whenComplete(() => _writes.remove(seed));
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _timer?.cancel();
    _timer = null;
  }

  /// The rules and the status for [s] (a snapshot of [manager]).
  RulesView view(DisplaySnapshot s) {
    final conditions = this.conditions(s);
    return RulesView(status: _statusOf(s, conditions), conditions: conditions);
  }

  PatientStatus status(DisplaySnapshot s) => view(s).status;

  /// My feet's pressure numbers for [side] ([PressureFigures]). The caller
  /// shows them only while the foot is usable (rule 2).
  PressureFigures pressureFigures(FootSide side) => _feet[side]!.figures();

  /// Every rule that holds at [s].
  List<AlertCondition> conditions(DisplaySnapshot s) {
    final out = <AlertCondition>[];
    for (final side in FootSide.values) {
      final view = s.of(side);
      if (view.usable) {
        if (view.batteryPct != null) _lastBattery[side] = view.batteryPct!;
        out.addAll(_feet[side]!.conditions());
        final battery = view.batteryPct;
        if (battery != null && battery < thresholds.batteryLowPct) {
          out.add(
            AlertCondition(
              code: AlertCode.batteryLow,
              side: side,
              value: battery.toDouble(),
              threshold: thresholds.batteryLowPct,
            ),
          );
        }
      }
      final lost = _lost(s, side);
      if (lost != null) out.add(lost);
    }
    if (s.left.usable && s.right.usable) {
      out.addAll(_tempConditions(s));
      final asym = _asymmetryCondition();
      if (asym != null) out.add(asym);
    }
    return out;
  }

  /// Raises an alert for each rule that started to hold since the last
  /// check.
  void check() {
    final s = manager.snapshot();
    final conditions = this.conditions(s);
    final now = {for (final c in conditions) c.key};
    for (final c in conditions) {
      if (!_active.contains(c.key)) _rise(c, s, conditions);
    }
    _active = now;
  }

  // --- Inputs -------------------------------------------------------------

  void _onBatch(FootBatch b) {
    _lastArrival[b.side] = b.receivedAt;
    // Before the rules, so an alert this batch raises stores a map that
    // includes it.
    _mapPeaks[b.side]!.add(b);
    for (final step in _feet[b.side]!.add(b)) {
      _onStep(step);
    }
    check();
  }

  void _onStep(Step step) {
    final other =
        _feet[step.side == FootSide.left ? FootSide.right : FootSide.left]!
            .latestStep;
    final s = manager.snapshot();
    // Compare with the other foot's step of this stretch of walking.
    final recent =
        other != null && other.endMs > step.startMs - thresholds.maxStanceMs;
    final pai = s.left.usable && s.right.usable && recent
        ? PeakAsymmetry.of(step.maxPeakKpa, other.maxPeakKpa)
        : null;
    if (pai != null && pai.isUneven(thresholds)) {
      _asymSteps++;
      final left = step.side == FootSide.left;
      _asymLeftKpa = left ? step.maxPeakKpa : other!.maxPeakKpa;
      _asymRightKpa = left ? other!.maxPeakKpa : step.maxPeakKpa;
    } else {
      _asymSteps = 0;
    }
  }

  void _onTemp(FootTemp t) {
    _tempFresh[t.side] = true;
    if (_tempFresh.values.every((f) => f)) {
      _tempFresh.updateAll((_, _) => false);
      final s = manager.snapshot();
      for (final site in TempSite.values) {
        final d = _delta(s, site);
        // A pair without a ΔT (a foot unusable, poor contact, no reading)
        // breaks the run; one foot's missed reading does not, because a
        // pair always uses each foot's newest reading.
        _overCount[site] = d != null && deltaAbove(d, thresholds.deltaC)
            ? _overCount[site]! + 1
            : 0;
      }
    }
    check();
  }

  // --- Two-foot and link rules --------------------------------------------

  static double? _delta(DisplaySnapshot s, TempSite site) {
    if (!s.left.usable || !s.right.usable) return null;
    return site == TempSite.forefoot ? s.deltaForefootC : s.deltaHeelC;
  }

  List<AlertCondition> _tempConditions(DisplaySnapshot s) {
    final out = <AlertCondition>[];
    for (final site in TempSite.values) {
      final d = _delta(s, site);
      if (d == null) continue;
      final count = _overCount[site]!;
      if (count < thresholds.consecutiveReadings) continue;
      if (!deltaAbove(d, thresholds.deltaC)) continue;
      double? at(FootView f) =>
          site == TempSite.forefoot ? f.temp?.forefootC : f.temp?.heelC;
      final otherSite = site == TempSite.forefoot
          ? TempSite.heel
          : TempSite.forefoot;
      out.add(
        AlertCondition(
          code: AlertCode.tempDelta,
          // ΔT is left minus right: positive means the left foot is warmer.
          side: d > 0 ? FootSide.left : FootSide.right,
          site: site,
          value: d.abs(),
          threshold: thresholds.deltaC,
          details: {
            'leftC': at(s.left),
            'rightC': at(s.right),
            'consecutive': count,
            'otherSiteDeltaC': _delta(s, otherSite)?.abs(),
          },
        ),
      );
    }
    return out;
  }

  AlertCondition? _asymmetryCondition() {
    if (_asymSteps < thresholds.peakAsymmetrySteps) return null;
    if (!_feet.values.every((f) => f.walkingRecently)) return null;
    final pai = PeakAsymmetry.of(_asymLeftKpa, _asymRightKpa)!;
    return AlertCondition(
      code: AlertCode.asymmetryPeak,
      side: pai.leftHigher ?? true ? FootSide.left : FootSide.right,
      value: pai.paiPct,
      threshold: thresholds.peakAsymmetryPct,
      details: {
        'leftPeakKpa': _asymLeftKpa,
        'rightPeakKpa': _asymRightKpa,
        'steps': _asymSteps,
      },
    );
  }

  /// `DEVICE_LOST`: a foot that streamed in this run gives no data for
  /// longer than `device.lostAfterMin`, and the user did not disconnect it
  /// (Disconnect leaves the link idle, and forgets the foot here).
  AlertCondition? _lost(DisplaySnapshot s, FootSide side) {
    if (manager.source(side).state is LinkIdle) {
      _lastArrival.remove(side);
      return null;
    }
    final last = _lastArrival[side];
    if (last == null || s.of(side).usable) return null;
    final gone = s.at.difference(last);
    final after = Duration(minutes: thresholds.deviceLostAfterMin);
    if (gone <= after) return null;
    return AlertCondition(
      code: AlertCode.deviceLost,
      side: side,
      value: gone.inMilliseconds / Duration.millisecondsPerMinute,
      threshold: thresholds.deviceLostAfterMin.toDouble(),
      details: {
        'lastDataAtMs': last.millisecondsSinceEpoch,
        'lastBatteryPct': _lastBattery[side],
      },
    );
  }

  // --- Status -------------------------------------------------------------

  /// Which level-3+ rule names the status when several hold (user decision
  /// 2026-10-24, BACKLOG 37): the higher level first; within a level this
  /// order; then the one furthest past its threshold.
  static const _textOrder = [
    AlertCode.tempDelta,
    AlertCode.pressurePti,
    AlertCode.pressurePeak,
    AlertCode.loadConcentration,
  ];

  /// Whether [a] names the status rather than [b].
  static bool ranksAbove(AlertCondition a, AlertCondition b) {
    if (a.code.level != b.code.level) return a.code.level > b.code.level;
    final ia = _textOrder.indexOf(a.code);
    final ib = _textOrder.indexOf(b.code);
    if (ia != ib) return ia < ib;
    return a.ratio > b.ratio;
  }

  /// FLUTTER-PLAN §7. A level-3+ rule from a usable foot wins over a
  /// missing other foot (BACKLOG 38); levels 1–2 never set the card.
  PatientStatus _statusOf(DisplaySnapshot s, List<AlertCondition> all) {
    if (!s.left.usable && !s.right.usable) return PatientStatus.noData;
    AlertCondition? best;
    for (final c in all) {
      if (c.code.level < carefulLevel) continue;
      if (best == null || ranksAbove(c, best)) best = c;
    }
    if (best != null) return PatientStatus.from(best.cause);
    if (!s.left.usable) return const PatientStatus.missing(FootSide.left);
    if (!s.right.usable) return const PatientStatus.missing(FootSide.right);
    return PatientStatus.safe;
  }

  // --- Raising ------------------------------------------------------------

  Future<void> _seedSuppression() async {
    final now = manager.now().millisecondsSinceEpoch;
    try {
      final recent = await alerts.since(now - _repeatMs);
      for (final a in recent) {
        final code = a.kind.code;
        if (code == null) continue;
        final key = alertKey(
          code,
          a.side,
          channel: a.zone == null ? null : _channelOf(a.zone!),
          site: a.site,
        );
        final prev = _lastRaisedMs[key];
        if (prev == null || a.atMs > prev) _lastRaisedMs[key] = a.atMs;
      }
    } on Object catch (e) {
      debugPrint('alerts: suppression memory unreadable: $e');
    }
    _seeded = true;
    final waiting = List.of(_beforeSeed);
    _beforeSeed.clear();
    for (final (c, s, all) in waiting) {
      _rise(c, s, all);
    }
  }

  /// [c]'s detail numbers; a pressure code also gets both feet's foot
  /// map at [s] (`map`: `left` / `right` → `{kpa: [...], levels: [...]}`,
  /// null for a foot that is not usable), the same values Home's map
  /// shows ([mapPeaksOf], [pressureLevel]).
  Map<String, Object?>? _detailsOf(AlertCondition c, DisplaySnapshot s) {
    final out = {...c.details};
    if (pressureCodes.contains(c.code)) {
      out['map'] = {
        for (final side in FootSide.values) side.name: _mapOf(s.of(side)),
      };
    }
    return out.isEmpty ? null : out;
  }

  Map<String, Object?>? _mapOf(FootView f) {
    final kpa = mapPeaksOf(f, _mapPeaks[f.side]!.channelPeaks());
    if (kpa == null) return null;
    return {
      'kpa': List<double>.of(kpa),
      'levels': [for (final k in kpa) pressureLevel(k, thresholds).name],
    };
  }

  int get _repeatMs => Duration(minutes: thresholds.repeatMin).inMilliseconds;

  static int? _channelOf(String zoneId) {
    final i = footLayout.zones.indexWhere((z) => z.id == zoneId);
    return i < 0 ? null : i;
  }

  void _rise(AlertCondition c, DisplaySnapshot s, List<AlertCondition> all) {
    if (!_seeded) {
      _beforeSeed.add((c, s, all));
      return;
    }
    final atMs = s.at.millisecondsSinceEpoch;
    final last = _lastRaisedMs[c.key];
    if (last != null && atMs - last < _repeatMs) return;
    _lastRaisedMs[c.key] = atMs;
    final estimate = gaitNoteCodes.contains(c.code) ? gait?.call(c.side) : null;
    final alert = NewAlert(
      kind: AlertKind.values.firstWhere((k) => k.code == c.code),
      patientLevel: _statusOf(s, all).level,
      atMs: atMs,
      side: c.side,
      zone: c.channel == null ? null : footLayout.zones[c.channel!].id,
      site: c.site,
      measuredValue: c.value,
      threshold: c.threshold,
      gaitClass: estimate?.gaitClass,
      gaitConfidence: estimate?.confidence,
      details: _detailsOf(c, s),
      captureStamp: captureStamp?.call(),
    );
    final write = alerts
        .add(alert)
        .then<void>(
          (_) {},
          onError: (Object e) => debugPrint('alerts: not stored: $e'),
        );
    _writes.add(write);
    write.whenComplete(() => _writes.remove(write));
  }
}

/// The single-foot rules of one foot, fed from its 50 Hz samples.
class _FootRules {
  _FootRules(this.side, this.t, this.figuresWindowMs)
    : walkingPeaks = RollingPeaks(
        windowMs: figuresWindowMs,
        bucketMs: Duration.millisecondsPerSecond,
      ),
      gate = WalkingGate(windowMs: t.walkingWindowMs, accelG: t.walkingAccelG),
      steps = StepDetector(
        side: side,
        contactKpa: t.stepContactKpa,
        minStanceMs: t.minStanceMs,
        maxStanceMs: t.maxStanceMs,
      );

  final FootSide side;
  final Thresholds t;
  final WalkingGate gate;
  final StepDetector steps;

  // My feet's figures (display only): the walking samples' peaks and the
  // walking steps' top-zone shares of the last figuresWindowMs.
  final int figuresWindowMs;
  final RollingPeaks walkingPeaks;
  final _shares = Queue<(double, double)>();

  int? _session;

  /// Unix ms of this foot's newest sample: the clock the per-foot rules
  /// are read against.
  double? _newestMs;

  // PRESSURE_WATCH / PRESSURE_PEAK: per channel, the last sample above the
  // boundary and the highest value since the rule started to hold.
  final _watchLast = <int, double>{};
  final _watchMax = <int, double>{};
  final _peakLast = <int, double>{};
  final _peakMax = <int, double>{};

  // PRESSURE_PTI: the steps of the last ptiWindowMin, with their summed
  // per-step PTI in kPa·ms.
  final _ptiSteps = Queue<Step>();
  List<double> _ptiSum = const [];

  // LOAD_CONCENTRATION: the same top zone above concentrationPct on
  // consecutive steps.
  int _concSteps = 0;
  int? _concZone;
  double _concShare = 0;

  Step? latestStep;

  /// The newest walking step ended no longer ago than a stance can last:
  /// the step-based rules stop holding soon after the walk does.
  bool get walkingRecently {
    final step = latestStep;
    final newest = _newestMs;
    if (step == null || newest == null) return false;
    return newest - step.endMs <= t.maxStanceMs;
  }

  /// Adds one packet; returns the walking steps it completes.
  List<Step> add(FootBatch b) {
    if (b.session != _session) {
      _session = b.session;
      // A new connection: its clock is new and a run of steps is broken.
      gate.reset();
      steps.reset();
      _concSteps = 0;
      latestStep = null;
      walkingPeaks.clear();
      _shares.clear();
    } else if (b.missingBefore > 0) {
      gate.reset();
      steps.reset();
    }
    final out = <Step>[];
    for (final s in b.samples) {
      final walking = gate.add(s.unixMs, s.accelG);
      _newestMs = s.unixMs;
      if (walking) walkingPeaks.addSample(s.unixMs, s.fsrKpa);
      for (var c = 0; c < s.fsrKpa.length; c++) {
        final k = s.fsrKpa[c];
        if (k > t.watchKpa) _hit(_watchLast, _watchMax, c, s.unixMs, k);
        // Contract §8.3: PRESSURE_PEAK only while walking (rule 7); a high
        // value while not walking stays PRESSURE_WATCH (§8.3.2).
        if (walking && k > t.alertKpa) {
          _hit(_peakLast, _peakMax, c, s.unixMs, k);
        }
      }
      final step = steps.add(s.unixMs, s.fsrKpa, walking: walking);
      if (step != null) {
        _onStep(step);
        out.add(step);
      }
    }
    return out;
  }

  void _hit(
    Map<int, double> last,
    Map<int, double> max,
    int c,
    double atMs,
    double kpa,
  ) {
    final prev = last[c];
    // After a gap longer than the hold, this starts a new episode.
    final fresh = prev == null || atMs - prev > t.peakHoldMs;
    if (fresh || kpa > max[c]!) max[c] = kpa;
    last[c] = atMs;
  }

  void _onStep(Step step) {
    latestStep = step;
    _ptiSteps.add(step);
    if (_ptiSum.length != step.ptiKpaMs.length) {
      _ptiSum = List.filled(step.ptiKpaMs.length, 0);
    }
    for (var c = 0; c < _ptiSum.length; c++) {
      _ptiSum[c] += step.ptiKpaMs[c];
    }
    final (top, share) = step.topZoneShare;
    if (share != null) _shares.add((step.endMs, share));
    if (share != null && share > t.concentrationPct) {
      _concSteps = _concZone == top ? _concSteps + 1 : 1;
      _concZone = top;
      _concShare = share;
    } else {
      _concSteps = 0;
      _concZone = null;
    }
  }

  /// Drops steps older than the PTI window, read against the newest
  /// sample, so an hour without walking empties it.
  void _prunePti() {
    final newest = _newestMs;
    if (newest == null) return;
    final from = newest - Duration(minutes: t.ptiWindowMin).inMilliseconds;
    var pruned = false;
    while (_ptiSteps.isNotEmpty && _ptiSteps.first.endMs < from) {
      _ptiSteps.removeFirst();
      pruned = true;
    }
    if (!pruned) return;
    // Summed afresh after a removal, so no running total drifts.
    _ptiSum = List.filled(_ptiSum.length, 0);
    for (final s in _ptiSteps) {
      for (var c = 0; c < _ptiSum.length; c++) {
        _ptiSum[c] += s.ptiKpaMs[c];
      }
    }
  }

  PressureFigures figures() {
    final newest = _newestMs;
    if (newest == null) return PressureFigures.none;
    _prunePti();
    final n = _ptiSteps.length;
    double? pti;
    for (final sum in _ptiSum) {
      final mean = sum / n / Duration.millisecondsPerSecond;
      if (pti == null || mean > pti) pti = mean;
    }
    final from = newest - figuresWindowMs;
    while (_shares.isNotEmpty && _shares.first.$1 < from) {
      _shares.removeFirst();
    }
    double? share;
    for (final (_, v) in _shares) {
      if (share == null || v > share) share = v;
    }
    return PressureFigures(
      walkingPeakKpa: walkingPeaks.footPeak(asOfMs: newest),
      ptiKpaS: n == 0 ? null : pti,
      ptiSteps: n,
      concentrationPct: share,
    );
  }

  List<AlertCondition> conditions() {
    final newest = _newestMs;
    if (newest == null) return const [];
    final out = <AlertCondition>[];
    bool held(Map<int, double> last, int c) =>
        last[c] != null && newest - last[c]! <= t.peakHoldMs;
    for (final c in _watchLast.keys) {
      if (!held(_watchLast, c)) continue;
      out.add(
        AlertCondition(
          code: AlertCode.pressureWatch,
          side: side,
          channel: c,
          value: _watchMax[c]!,
          threshold: t.watchKpa,
        ),
      );
    }
    for (final c in _peakLast.keys) {
      if (!held(_peakLast, c)) continue;
      out.add(
        AlertCondition(
          code: AlertCode.pressurePeak,
          side: side,
          channel: c,
          value: _peakMax[c]!,
          threshold: t.alertKpa,
          details: const {'walking': true},
        ),
      );
    }
    if (!walkingRecently) return out;
    _prunePti();
    final n = _ptiSteps.length;
    if (n >= t.ptiMinSteps) {
      for (var c = 0; c < _ptiSum.length; c++) {
        // Compared in kPa·ms: whole-ms sums stay exact at the boundary.
        final meanKpaMs = _ptiSum[c] / n;
        if (meanKpaMs <= t.ptiKpaS * 1000) continue;
        out.add(
          AlertCondition(
            code: AlertCode.pressurePti,
            side: side,
            channel: c,
            value: meanKpaMs / 1000,
            threshold: t.ptiKpaS,
            details: {'steps': n, 'windowMin': t.ptiWindowMin},
          ),
        );
      }
    }
    if (_concSteps >= t.concentrationSteps) {
      out.add(
        AlertCondition(
          code: AlertCode.loadConcentration,
          side: side,
          channel: _concZone,
          value: _concShare,
          threshold: t.concentrationPct,
          details: {'steps': _concSteps},
        ),
      );
    }
    return out;
  }
}

/// |ΔT| strictly above [deltaC] (contract §8.3 "> 2.2 °C", Lavery et al.
/// 2004), compared at the sensor's 0.01 °C resolution so float noise
/// (33.20 − 31.00 = 2.2000000000000028) never crosses the boundary.
///
/// Proposal doc 03 counts a warm-compress event as qualifying at ≥ 2.2 °C
/// on the reference thermometer; the two differ only at exactly 2.20 °C,
/// and the study analysis uses doc 03's definition for qualifying events.
bool deltaAbove(double delta, double deltaC) =>
    (delta.abs() * 100).round() > (deltaC * 100).round();

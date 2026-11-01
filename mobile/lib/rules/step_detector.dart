import 'dart:math' as math;

import '../ble/packets.dart';

/// One walking step of one foot: a stance with its per-zone peak and
/// pressure–time integral.
class Step {
  const Step({
    required this.side,
    required this.startMs,
    required this.endMs,
    required this.peakKpa,
    required this.ptiKpaMs,
  });

  final FootSide side;

  /// Unix ms of the first loaded sample and of the first unloaded one.
  final double startMs;
  final double endMs;

  /// Highest kPa per zone (FSR channel order) during the stance.
  final List<double> peakKpa;

  /// ∫ kPa dt per zone over the stance, in kPa·ms (trapezoids between the
  /// samples' unix times; kept in ms so whole-ms sample times sum
  /// exactly). The per-step PTI of BACKLOG 31 (user decision 2026-10-24;
  /// Melai et al. 2011, Bus & Waaijman 2013).
  final List<double> ptiKpaMs;

  /// [ptiKpaMs] in the contract's kPa·s.
  List<double> get ptiKpaS => [for (final v in ptiKpaMs) v / 1000];

  double get durationMs => endMs - startMs;

  /// The foot's peak for PAI: its highest zone.
  double get maxPeakKpa => peakKpa.reduce(math.max);

  /// The zone with the highest peak, and its share of the summed zone
  /// peaks in percent (`LOAD_CONCENTRATION`, contract §8.2: "จุดที่สูงสุด /
  /// ผลรวม 6 จุด × 100"). Null share when nothing was loaded.
  (int, double?) get topZoneShare {
    var top = 0;
    var sum = 0.0;
    for (var c = 0; c < peakKpa.length; c++) {
      sum += peakKpa[c];
      if (peakKpa[c] > peakKpa[top]) top = c;
    }
    // Multiplied first, so 40 of 100 is exactly 40 %.
    return (top, sum == 0 ? null : peakKpa[top] * 100 / sum);
  }
}

/// Finds walking steps in one foot's 50 Hz samples. **PROVISIONAL** values
/// (`steps.*` in `thresholds.json`), to be checked against a manual count
/// with the real boards in SR:
/// - a stance starts when the summed zone kPa goes above [contactKpa] and
///   ends at the first sample at or below it, unless the sum goes above it
///   again less than [mergeGapMs] later: then the dip is part of the stance
///   (a short dip in the hand-off from heel to forefoot, BACKLOG 51). So a
///   step is returned [mergeGapMs] after its end (the first sample that
///   far past it), with the peak and PTI it had at its end;
/// - it is a step only when it lasts [minStanceMs] to [maxStanceMs] and
///   the walking gate ([WalkingGate]) was on at some sample of it, so
///   standing, shifting weight and sitting are not steps.
///
/// [add] returns the step a sample completes. [reset] drops a stance in
/// progress, or one waiting out [mergeGapMs]: after lost packets or on a
/// new connection its integral would be wrong.
class StepDetector {
  StepDetector({
    required this.side,
    required this.contactKpa,
    required this.minStanceMs,
    required this.maxStanceMs,
    required this.mergeGapMs,
  });

  final FootSide side;
  final double contactKpa;
  final int minStanceMs;
  final int maxStanceMs;
  final int mergeGapMs;

  bool _inStance = false;
  double _startMs = 0;
  double _prevMs = 0;
  List<double> _prevKpa = const [];
  List<double> _peaks = const [];
  List<double> _pti = const [];
  bool _walked = false;

  /// The stance's end while a dip may still turn out to be part of it:
  /// the first unloaded sample's time, and the figures up to it.
  double? _endMs;
  List<double> _endPeaks = const [];
  List<double> _endPti = const [];
  bool _endWalked = false;

  /// Adds one sample; [walking] is the gate at this sample.
  Step? add(double unixMs, List<double> kpa, {required bool walking}) {
    var sum = 0.0;
    for (final k in kpa) {
      sum += k;
    }
    final loaded = sum > contactKpa;
    Step? done;
    final end = _endMs;
    if (end != null && unixMs - end >= mergeGapMs) {
      // The dip lasted the whole merge window: the stance ended at [end].
      done = _finish();
    }
    if (!_inStance) {
      if (!loaded) return done;
      _inStance = true;
      _startMs = unixMs;
      _peaks = List.of(kpa);
      _pti = List.filled(kpa.length, 0);
      _walked = walking;
      _prevMs = unixMs;
      _prevKpa = kpa;
      return done;
    }
    final dtMs = unixMs - _prevMs;
    for (var c = 0; c < kpa.length && c < _pti.length; c++) {
      _pti[c] += (_prevKpa[c] + kpa[c]) * 0.5 * dtMs;
      if (kpa[c] > _peaks[c]) _peaks[c] = kpa[c];
    }
    _walked |= walking;
    _prevMs = unixMs;
    _prevKpa = kpa;
    if (loaded) {
      // Back above contactKpa within the window: the dip was part of it.
      _endMs = null;
      return done;
    }
    if (_endMs != null) return done;
    _endMs = unixMs;
    _endPeaks = List.of(_peaks);
    _endPti = List.of(_pti);
    _endWalked = _walked;
    return mergeGapMs <= 0 ? _finish() : done;
  }

  Step? _finish() {
    final end = _endMs!;
    _endMs = null;
    _inStance = false;
    final duration = end - _startMs;
    if (!_endWalked || duration < minStanceMs || duration > maxStanceMs) {
      return null;
    }
    return Step(
      side: side,
      startMs: _startMs,
      endMs: end,
      peakKpa: _endPeaks,
      ptiKpaMs: _endPti,
    );
  }

  void reset() {
    _inStance = false;
    _endMs = null;
  }
}

import 'dart:collection';

import '../ble/packets.dart';
import '../rules/asymmetry.dart';
import '../rules/step_detector.dart';

/// PTI Asymmetry Index for the Gait tab's details ("ความไม่สมดุลของแรงกด
/// สะสม"). Contract §8.2 only says "compare left and right cumulative
/// pressure"; the reading here is a user decision (2026-10-25, written
/// into the §8 local addendum):
///
///     |L − R| / ((L + R) / 2) × 100   ([paiPercent])
///
/// where L and R are each foot's mean whole-foot per-step PTI (the sum of
/// the zones' ∫ kPa dt, kPa·s) over its walking steps in the last
/// [windowMs] (5 min, the same window as My feet's "peak while walking").
///
/// Display only: no rule raises an alert on it (`asymmetry.ptiPct` is
/// shown as a reference value). The caller shows it only while both feet
/// are usable (rule 4).
class PtiAsymmetry {
  PtiAsymmetry({required this.windowMs});

  final int windowMs;

  final _steps = {
    for (final side in FootSide.values) side: Queue<(double, double)>(),
  };

  /// Adds one walking step.
  void add(Step step) {
    final q = _steps[step.side]!;
    final whole = step.ptiKpaS.fold<double>(0, (a, v) => a + v);
    q.add((step.endMs, whole));
    while (q.isNotEmpty && q.first.$1 <= step.endMs - windowMs) {
      q.removeFirst();
    }
  }

  /// The index at [nowMs] (unix ms, sample time), or null when either foot
  /// has no step in the window or neither carried any load.
  double? pctAt(double nowMs) {
    double? meanOf(FootSide side) {
      var sum = 0.0;
      var n = 0;
      for (final (endMs, pti) in _steps[side]!) {
        if (endMs <= nowMs - windowMs) continue;
        sum += pti;
        n++;
      }
      return n == 0 ? null : sum / n;
    }

    final l = meanOf(FootSide.left);
    final r = meanOf(FootSide.right);
    if (l == null || r == null || l + r <= 0) return null;
    return paiPercent(l, r);
  }

  void clear() {
    for (final q in _steps.values) {
      q.clear();
    }
  }
}

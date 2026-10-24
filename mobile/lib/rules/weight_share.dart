import '../config/thresholds.dart';
import 'asymmetry.dart';

/// How the weight is shared between the feet: Home's balance card
/// "{L} : {R}" and its note.
///
/// User decision 2026-10-23 (BACKLOG 37). The numbers are each foot's
/// share of the summed kPa over all zones, averaged over a rolling window
/// (`RollingLoad`, Home's `balanceWindowMs`). The note says the heavier
/// foot when the two mean loads differ by more than `asymmetry.peakPct`,
/// computed with the PAI formula ([paiPercent]); otherwise "พอ ๆ กัน".
///
/// This is not `ASYMMETRY_PEAK`: that rule uses per-step peaks
/// ([PeakAsymmetry]). The note is `ink` with no icon, and turns orange
/// (naming the rule's foot) only while `ASYMMETRY_PEAK` is active.
class WeightShare {
  const WeightShare._(this.leftLoad, this.rightLoad);

  /// Null when neither foot carries any load: the ratio is undefined.
  static WeightShare? of(double leftLoad, double rightLoad) {
    if (leftLoad < 0 || rightLoad < 0) {
      throw ArgumentError('loads must not be negative');
    }
    if (leftLoad + rightLoad == 0) return null;
    return WeightShare._(leftLoad, rightLoad);
  }

  final double leftLoad;
  final double rightLoad;

  /// Left foot's share, percent (0–100); the right is 100 − it.
  double get leftSharePct => leftLoad / (leftLoad + rightLoad) * 100;

  /// The two loads differ by more than `asymmetry.peakPct`.
  bool isUneven(Thresholds t) =>
      paiPercent(leftLoad, rightLoad) > t.peakAsymmetryPct;

  /// The foot carrying more, or null when they are equal.
  bool? get leftHeavier => leftLoad == rightLoad ? null : leftLoad > rightLoad;
}

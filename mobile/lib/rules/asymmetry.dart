import '../config/thresholds.dart';

/// Peak Asymmetry Index, DATA-CONTRACT §8.2:
///
///     PAI = |L − R| / ((L + R) / 2) × 100
///
/// where L and R are each foot's **peak** pressure (kPa). `ASYMMETRY_PEAK`
/// (§8.3) is "PAI > `asymmetry.peakPct` sustained for ≥ `asymmetry.peakSteps`
/// steps".
///
/// `ASYMMETRY_PEAK` (`alert_engine.dart`, BACKLOG 37 settled in S7): L and
/// R are each foot's highest zone peak over one walking step
/// (`StepDetector`); each completed step of either foot compares the two
/// feet's latest steps, and the rule is active after `asymmetry.peakSteps`
/// such steps in a row above `asymmetry.peakPct`.
///
/// Home's balance card does not show PAI: it shows weight share
/// ([WeightShare], user decision 2026-10-23), and its note turns orange
/// only while `ASYMMETRY_PEAK` is active.
class PeakAsymmetry {
  const PeakAsymmetry._(this.leftPeakKpa, this.rightPeakKpa);

  /// Null when both peaks are zero: the ratio is undefined, not 0 %.
  static PeakAsymmetry? of(double leftPeakKpa, double rightPeakKpa) {
    if (leftPeakKpa < 0 || rightPeakKpa < 0) {
      throw ArgumentError('peaks must not be negative');
    }
    if (leftPeakKpa + rightPeakKpa == 0) return null;
    return PeakAsymmetry._(leftPeakKpa, rightPeakKpa);
  }

  final double leftPeakKpa;
  final double rightPeakKpa;

  /// PAI in percent, 0–200.
  double get paiPct => paiPercent(leftPeakKpa, rightPeakKpa);

  /// Above `asymmetry.peakPct` (the `ASYMMETRY_PEAK` boundary).
  bool isUneven(Thresholds t) => paiPct > t.peakAsymmetryPct;

  /// The foot with the higher peak, or null when they are equal.
  bool? get leftHigher =>
      leftPeakKpa == rightPeakKpa ? null : leftPeakKpa > rightPeakKpa;
}

/// |L − R| / ((L + R) / 2) × 100, in percent (0–200). The contract's PAI
/// formula (§8.2), shared by [PeakAsymmetry] and `WeightShare`. Not
/// defined when both are 0.
///
/// Multiplied before dividing, so a ratio that is exact in decimals stays
/// exact (|107.5 − 92.5| → 15 %, not 15.000000000000002).
double paiPercent(double left, double right) =>
    (left - right).abs() * 100 / ((left + right) * 0.5);

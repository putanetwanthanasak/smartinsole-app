import '../config/thresholds.dart';

/// Peak Asymmetry Index, DATA-CONTRACT §8.2:
///
///     PAI = |L − R| / ((L + R) / 2) × 100
///
/// where L and R are each foot's **peak** pressure (kPa). `ASYMMETRY_PEAK`
/// (§8.3) is "PAI > `asymmetry.peakPct` sustained for ≥ 20 steps".
///
/// This is the definition S7's `ASYMMETRY_PEAK` rule starts from. Home
/// does not use it: the balance card shows weight share ([WeightShare],
/// user decision 2026-10-23), and its note turns orange only once S7
/// reports `ASYMMETRY_PEAK` active.
///
/// **INTERIM (S5), BACKLOG 37.** The contract gives the formula and that it
/// uses peaks, but not what a peak is taken over. Until S7 settles it:
/// - a foot's peak is its highest channel over [peakWindowMs] of samples
///   (the same 2 s window as the web app's PAI, report 003), not per step;
/// - it is computed while walking and while standing alike;
/// - "sustained ≥ 20 steps" is not checked: the note turns orange as soon
///   as one window's PAI is above `peakPct`.
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

  /// Interim window length (see the class comment). Not a clinical
  /// threshold; S7 replaces it with the contract's step-based window.
  static const peakWindowMs = 2000;

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
double paiPercent(double left, double right) =>
    (left - right).abs() / ((left + right) / 2) * 100;

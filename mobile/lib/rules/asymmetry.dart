import '../config/thresholds.dart';

/// Peak Asymmetry Index, DATA-CONTRACT §8.2:
///
///     PAI = |L − R| / ((L + R) / 2) × 100
///
/// where L and R are each foot's **peak** pressure (kPa). `ASYMMETRY_PEAK`
/// (§8.3) is "PAI > `asymmetry.peakPct` sustained for ≥ 20 steps".
///
/// This is the one definition of left/right asymmetry in the app. Home's
/// balance numbers and its orange note use it, and S7's `ASYMMETRY_PEAK`
/// rule must reuse it.
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
  double get paiPct =>
      (leftPeakKpa - rightPeakKpa).abs() /
      ((leftPeakKpa + rightPeakKpa) / 2) *
      100;

  /// Left foot's share of the two peaks, percent (0–100). The balance
  /// numbers "{L} : {R}" are [leftSharePct] and 100 − it, so the same two
  /// peaks give both the numbers and the PAI.
  double get leftSharePct => leftPeakKpa / (leftPeakKpa + rightPeakKpa) * 100;

  /// Above `asymmetry.peakPct` (the `ASYMMETRY_PEAK` boundary).
  bool isUneven(Thresholds t) => paiPct > t.peakAsymmetryPct;

  /// The foot with the higher peak, or null when they are equal.
  bool? get leftHigher =>
      leftPeakKpa == rightPeakKpa ? null : leftPeakKpa > rightPeakKpa;
}

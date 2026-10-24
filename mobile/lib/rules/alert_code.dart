/// The 8 alert codes of DATA-CONTRACT v1.5 §8.3, with their internal level
/// (1–5). S7 implements the rules that raise them; S5 only needs the names
/// and levels for the patient status seam.
enum AlertCode {
  tempDelta(4),
  pressureWatch(2),
  pressurePeak(3),
  pressurePti(3),
  asymmetryPeak(2),
  loadConcentration(3),
  deviceLost(1),
  batteryLow(1);

  const AlertCode(this.level);

  /// Internal level 1–5 (stored for reporting and expert review).
  final int level;
}

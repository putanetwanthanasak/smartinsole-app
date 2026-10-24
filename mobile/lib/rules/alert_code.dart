/// The 8 alert codes of DATA-CONTRACT v1.5 §8.3, with their internal level
/// (1–5). `alert_engine.dart` holds the rules that raise them.
///
/// This file and the FLUTTER-PLAN §7 boundaries below are the contract's
/// level column, not thresholds: the threshold-literal test
/// (`test/rules/no_threshold_literals_test.dart`) skips this file only.
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

/// FLUTTER-PLAN §7: the lowest internal level shown as Be careful, and the
/// lowest shown as Rest your feet. Lower levels never set the status card.
const carefulLevel = 3;
const restLevel = 4;

/// The highest internal level (the contract's 1–5 scale), for "4 จาก 5".
const maxLevel = 5;

/// The codes about one pressure zone: the alert engine stores the foot
/// map with them (`details.map`), and the alert detail draws that map.
const pressureCodes = {
  AlertCode.pressureWatch,
  AlertCode.pressurePeak,
  AlertCode.pressurePti,
  AlertCode.loadConcentration,
};

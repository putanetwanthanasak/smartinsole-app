import '../config/thresholds.dart';

/// Foot-map dot level of one zone (DESIGN-SPEC §1): "น้อย", "ปานกลาง",
/// "มาก".
enum PressureLevel {
  low('น้อย'),
  medium('ปานกลาง'),
  high('มาก');

  const PressureLevel(this.th);
  final String th;
}

/// Medium above `watchKpa` (`PRESSURE_WATCH`), high above `alertKpa`
/// (`PRESSURE_PEAK`'s boundary). Strictly above, as DATA-CONTRACT §8.3
/// words both rules ("> 75 kPa", "> 200 kPa").
PressureLevel pressureLevel(double kpa, Thresholds t) {
  if (kpa > t.alertKpa) return PressureLevel.high;
  if (kpa > t.watchKpa) return PressureLevel.medium;
  return PressureLevel.low;
}

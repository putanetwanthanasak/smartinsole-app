import 'dart:math' as math;

import 'ble_protocol.dart';
import 'calibration.dart';
import 'packets.dart';

/// Unit conversion, Data Contract §5 / `docs/BLE-INTERFACE.md`. Same
/// arithmetic, in the same order, as the web app's `adcToKpa()` (including
/// the `offset_adc` and Pa→kPa fixes from reports 006 and 008), so results
/// match the TS parser to well within 3 decimal places.

/// `max(0, adc − offset_adc)`: a reading below the channel's zero point is
/// drift or noise, not negative pressure.
double correctAdc(int rawAdc, double offsetAdc) =>
    math.max(0, rawAdc - offsetAdc);

/// ```
/// adc_corrected = max(0, adc − offset_adc)
/// V_out = (adc_corrected / 4095) × 3.3
/// R_fsr = R_pulldown × (3.3 − V_out) / V_out
/// F_newton = a × R_fsr^b
/// P_kPa = F_newton / A_sensor / 1000
/// ```
/// The clamps on `adc` and `R_fsr` are numeric safety only, as in TS:
/// `adc_corrected = 0` would divide by zero, and `adc = 4095` makes
/// `R_fsr = 0`, which a negative `b` turns into infinity. Because of the
/// first clamp, a zero-load reading gives a small positive kPa (about
/// 0.01), not exactly 0.
double adcToKpa(int rawAdc, CalibrationChannel channel, Calibration cal) {
  final corrected = correctAdc(rawAdc, channel.offsetAdc);
  final adc = math.min<double>(
    Scaling.adcMax.toDouble(),
    math.max(1, corrected),
  );
  final vOut = (adc / Scaling.adcMax) * Scaling.supplyVoltage;
  final rFsr = math.max(
    1e-6,
    (cal.rPulldownOhm * (Scaling.supplyVoltage - vOut)) / vOut,
  );
  final fNewton = channel.a * math.pow(rFsr, channel.b);
  return fNewton / cal.sensorAreaM2 / 1000;
}

/// kPa for every FSR channel of [sample], in channel index order. The
/// sample must come from a packet parsed with `fsrCount: cal.fsrCount`.
List<double> sampleKpa(RawSensorSample sample, Calibration cal) {
  assert(sample.fsrAdc.length == cal.fsrCount);
  return [
    for (var ch = 0; ch < cal.fsrCount; ch++)
      adcToKpa(sample.fsrAdc[ch], cal.channels[ch], cal),
  ];
}

double accelRawToG(int raw) => raw / Scaling.accelLsbPerG;

double gyroRawToDps(int raw) => raw / Scaling.gyroLsbPerDps;

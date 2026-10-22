import '../ble/packets.dart';
import 'foot_sample.dart';

/// Model A input channels, DATA-CONTRACT §7.1, in units decided for S4C /
/// S8A (2026-10-22): FSR in kPa, accel in g, gyro in °/s. The same list is
/// in `shared/model_input.json` for the training scripts; a test keeps the
/// two identical. Never reorder: a model trained on one order silently
/// gives garbage on another.
///
/// ```
///  0– 5 : FSR left  index 0–5     12–17 : FSR right index 0–5
///  6– 8 : accel left x,y,z        18–20 : accel right x,y,z
///  9–11 : gyro left  x,y,z        21–23 : gyro right  x,y,z
/// ```

/// FSR channels the model was specified for. A foot with another count
/// (the hardware may change, FLUTTER-PLAN §2) has no model input.
const modelFsrCount = 6;
const modelChannelsPerFoot = modelFsrCount + 6;
const modelChannelCount = 2 * modelChannelsPerFoot;

/// Column names, also the S4C CSV header for these values.
final List<String> modelChannelNames = List.unmodifiable([
  for (final side in const ['L', 'R']) ...[
    for (var i = 0; i < modelFsrCount; i++) '${side}_fsr${i}_kpa',
    for (final a in const ['x', 'y', 'z']) '${side}_accel_${a}_g',
    for (final a in const ['x', 'y', 'z']) '${side}_gyro_${a}_dps',
  ],
]);

/// The 12 values of one foot in §7.1 order, or null when the foot does not
/// have exactly [modelFsrCount] FSR channels.
List<double>? footModelChannels(FootSample s) {
  if (s.fsrKpa.length != modelFsrCount) return null;
  return [...s.fsrKpa, ...s.accelG, ...s.gyroDps];
}

/// One 24-channel timestep: [left] then [right]. Pair the two feet's
/// samples in time with [pairFeet] first.
List<double>? modelRow(FootSample left, FootSample right) {
  final l = footModelChannels(left);
  final r = footModelChannels(right);
  if (l == null || r == null) return null;
  return [...l, ...r];
}

/// Where a foot's block starts in the 24 channels.
int modelChannelOffset(FootSide side) =>
    side == FootSide.left ? 0 : modelChannelsPerFoot;

/// How far apart (unix ms) a left and a right sample may be and still form
/// one 24-channel row: half a 20 ms sample period. The same value is
/// `pairing.toleranceMs` in `shared/model_input.json` (a test checks).
const pairToleranceMs = 10.0;

/// Pairs the two feet's samples in time for [modelRow], by the rule in
/// `shared/model_input.json` (`pairing`), which the Python loader
/// (`tools/capture/load_capture.py`) implements too, so the app and the
/// training data line the feet up the same way:
/// - [left] is the time base, [right] the other foot; both ascending in
///   `unixMs`;
/// - each left sample takes the right sample nearest in time, within
///   ±[pairToleranceMs] inclusive; on a tie, the earlier one;
/// - each right sample is used at most once, in order; a left sample with
///   no right sample in reach gives no row.
List<(FootSample, FootSample)> pairFeet(
  List<FootSample> left,
  List<FootSample> right,
) {
  final out = <(FootSample, FootSample)>[];
  var j = 0;
  for (final l in left) {
    while (j < right.length && right[j].unixMs < l.unixMs - pairToleranceMs) {
      j++;
    }
    int? best;
    var bestD = double.infinity;
    for (var k = j; k < right.length; k++) {
      if (right[k].unixMs > l.unixMs + pairToleranceMs) break;
      final d = (right[k].unixMs - l.unixMs).abs();
      if (d < bestD) {
        best = k;
        bestD = d;
      }
    }
    if (best != null) {
      out.add((l, right[best]));
      j = best + 1;
    }
  }
  return out;
}

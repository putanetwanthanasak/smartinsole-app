import '../ble/packets.dart';
import '../config/thresholds.dart';
import 'alert_code.dart';

/// Model A's newest estimate for one foot (S8A provides it).
class GaitEstimate {
  const GaitEstimate({required this.gaitClass, required this.confidence});

  /// The class id as the model names it (`normal`, `toe_walking`, …,
  /// contract §7.2).
  final String gaitClass;

  /// 0–1.
  final double confidence;
}

/// The gait hook of contract §8.3.1: the estimate for a foot at the time
/// an alert is raised, or null. It returns null until S8A.
typedef GaitEstimateSource = GaitEstimate? Function(FootSide side);

/// Pressure codes a gait note may explain (contract §8.3.1).
const gaitNoteCodes = {
  AlertCode.pressureWatch,
  AlertCode.pressurePeak,
  AlertCode.pressurePti,
  AlertCode.loadConcentration,
};

/// The contract §8.3.1 text that follows a pressure alert at [zoneId] when
/// Model A's [gaitClass] matches that zone with [confidence] at or above
/// `model.minConfidence`; otherwise null.
///
/// A note only explains an alert that a measured value already raised: it
/// never changes the level and never raises an alert by itself (rule 11).
///
/// `rotated_foot` gets no note: the contract's two texts depend on in- or
/// out-toeing, and Model A's class does not say which (BACKLOG 41).
String? gaitNoteTh({
  required AlertCode code,
  required String? zoneId,
  required String? gaitClass,
  required double? confidence,
  required Thresholds thresholds,
}) {
  if (!gaitNoteCodes.contains(code) || zoneId == null) return null;
  if (gaitClass == null || confidence == null) return null;
  if (confidence < thresholds.minConfidence) return null;
  final note = _notes[gaitClass];
  if (note == null) return null;
  final (zones, text) = note;
  if (zones != null && !zones.contains(zoneId)) return null;
  return text;
}

/// Class → (zones it explains, or null for any zone; Thai text).
const _notes = <String, (Set<String>?, String)>{
  'heel_walking': (
    {'heel'},
    'ตรวจพบรูปแบบเดินลงส้น ซึ่งอาจเพิ่มแรงกดบริเวณส้นเท้า',
  ),
  'toe_walking': (
    {'hallux', 'meta1'},
    'ตรวจพบรูปแบบเดินเขย่งปลายเท้า ซึ่งอาจเพิ่มแรงกดบริเวณปลายเท้า',
  ),
  'antalgic': (
    null,
    'ตรวจพบรูปแบบเดินไม่สมมาตร ควรตรวจสอบแรงกดทั้งสองข้างเทียบกัน',
  ),
};

/// Model A's class names in plain Thai (DESIGN-SPEC §8.3): the alert
/// detail's "รูปแบบการเดิน" row, and the Gait tab (S8A).
const gaitClassTh = {
  'normal': 'เดินปกติ',
  'toe_walking': 'เดินเขย่งปลายเท้า',
  'antalgic': 'เดินกะเผลก',
  'heel_walking': 'เดินลงส้นเท้า',
  'rotated_foot': 'เดินบิดปลายเท้า',
};

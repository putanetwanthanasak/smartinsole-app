import 'dart:math' as math;

import '../ble/packets.dart';

/// The study protocol as the capture flow runs it. The IRB-approved
/// procedure is proposal doc 03; where `docs/SmartInsole_TestProtocol_v1.md`
/// differs, doc 03 wins (S4C plan approval, 2026-10-22):
/// - subject data: sex, an age range (never an exact age), foot length and
///   room temperature, under a subject code; no names;
/// - each gait is demonstrated, the volunteer practises 30 s, then 3 min
///   are recorded; rest between gaits is as long as the volunteer wants.
///
/// These are protocol constants, not clinical thresholds (rule 12 covers
/// `shared/thresholds.json`); every trial's sidecar records the values used.

/// Model A's output classes (DATA-CONTRACT §7.2). [id] is the contract name
/// and the label written to every file; [modelIndex] is the model output
/// index (declared, not taken from the enum order).
enum GaitClass {
  normal(
    0,
    'normal',
    'เดินปกติ',
    'Normal',
    'เดินตามธรรมชาติด้วยความเร็วสบายๆ',
    'Natural walking at a comfortable speed',
  ),
  antalgic(
    1,
    'antalgic',
    'เดินกะเผลก',
    'Antalgic',
    'ลงน้ำหนักข้างที่กำหนดให้สั้นลง เหมือนเจ็บเท้าข้างนั้น',
    'Shorter loading on the assigned side, as if that foot hurts',
  ),
  toeWalking(
    2,
    'toe_walking',
    'เดินเขย่งปลายเท้า',
    'Toe walking',
    'ส้นเท้าไม่แตะพื้นหรือแตะน้อยที่สุด',
    'Heels off the ground, or touching as little as possible',
  ),
  heelWalking(
    3,
    'heel_walking',
    'เดินลงส้น',
    'Heel walking',
    'ลงส้นหนัก ปลายเท้าแตะพื้นน้อย',
    'Heavy heel strike, little forefoot contact',
  ),
  rotatedFoot(
    4,
    'rotated_foot',
    'เดินบิดเท้า',
    'Rotated foot',
    'ปลายเท้าบิดเข้าใน หรือบิดออกนอก',
    'Toes turned in (in-toeing) or out (out-toeing)',
  );

  const GaitClass(
    this.modelIndex,
    this.id,
    this.th,
    this.en,
    this.instructionTh,
    this.instructionEn,
  );

  final int modelIndex;
  final String id;
  final String th;
  final String en;
  final String instructionTh;
  final String instructionEn;
}

/// Rotated foot is one class; which way is a note (protocol).
enum Rotation {
  inToeing('in_toeing', 'บิดเข้าใน', 'In-toeing'),
  outToeing('out_toeing', 'บิดออกนอก', 'Out-toeing');

  const Rotation(this.id, this.th, this.en);
  final String id;
  final String th;
  final String en;
}

/// A subject code: `SI-001`…`SI-999` for the study, `TEST-001`… for a
/// rehearsal. Nothing else is accepted, so a name can't be typed in.
class SubjectCode {
  const SubjectCode._(this.code, this.number, {required this.rehearsal});

  static final _pattern = RegExp(r'^(SI|TEST)-(\d{3})$');

  /// Null unless [text] (trimmed, upper-cased) is a valid code.
  static SubjectCode? parse(String text) {
    final t = text.trim().toUpperCase();
    final m = _pattern.firstMatch(t);
    if (m == null) return null;
    final number = int.parse(m.group(2)!);
    if (number == 0) return null;
    return SubjectCode._(t, number, rehearsal: m.group(1) == 'TEST');
  }

  final String code;
  final int number;

  /// `TEST-` codes: short timers, files kept apart from study data.
  final bool rehearsal;

  /// The simulated-pain side for antalgic: odd subject numbers the left
  /// foot, even the right (protocol: alternate between subjects).
  FootSide get painSide => number.isOdd ? FootSide.left : FootSide.right;

  @override
  String toString() => code;
}

enum Sex {
  male('male', 'ชาย', 'Male'),
  female('female', 'หญิง', 'Female');

  const Sex(this.id, this.th, this.en);
  final String id;
  final String th;
  final String en;
}

/// Age is recorded as a range only. Doc 03 admits volunteers aged 21–30.
const ageRanges = ['21-25', '26-30'];

/// Doc 03 inclusion: foot length 25.5–27.5 cm (shoe size 42), inclusive.
const footLengthInclusionCm = (min: 25.5, max: 27.5);

/// Whether [cm] may be entered for [code]. Study codes must meet the
/// inclusion range; `TEST-` codes take any value. Before the code is valid
/// the study rule applies, so typing order can't hide the error.
bool footLengthEligible(SubjectCode? code, double cm) =>
    (code?.rehearsal ?? false) ||
    (cm >= footLengthInclusionCm.min && cm <= footLengthInclusionCm.max);

/// The session's trial plan: the 30 s standing calibration, then normal
/// gait, then the 4 abnormal gaits in a random order per subject (normal
/// first, before fatigue; the rest shuffled so fatigue doesn't fall on one
/// gait systematically).
List<GaitClass> trialOrder(int seed) {
  final rest = GaitClass.values.where((g) => g != GaitClass.normal).toList()
    ..shuffle(math.Random(seed));
  return [GaitClass.normal, ...rest];
}

/// A fresh, recorded seed for [trialOrder].
int newOrderSeed([math.Random? random]) =>
    (random ?? math.Random.secure()).nextInt(1 << 32);

/// Durations and limits of the flow.
class CaptureTimings {
  const CaptureTimings({
    required this.calibration,
    required this.trial,
    required this.practice,
  });

  /// The study (doc 03): 30 s standing calibration, 30 s practice, 3 min
  /// recorded per gait.
  static const study = CaptureTimings(
    calibration: Duration(seconds: 30),
    trial: Duration(minutes: 3),
    practice: Duration(seconds: 30),
  );

  /// `TEST-` codes only: the same flow, short enough to rehearse.
  static const rehearsal = CaptureTimings(
    calibration: Duration(seconds: 10),
    trial: Duration(seconds: 30),
    practice: Duration(seconds: 5),
  );

  static CaptureTimings of(SubjectCode code) =>
      code.rehearsal ? rehearsal : study;

  final Duration calibration;
  final Duration trial;
  final Duration practice;

  /// The warning cue before a recording ends.
  static const endWarning = Duration(seconds: 10);

  /// How long a control on the recording screen must be held. Long enough
  /// that a touch through a pocket can't trigger it.
  static const holdToAct = Duration(seconds: 2);

  /// Pre-check: each insole's battery at least this (protocol: enough for
  /// the whole session).
  static const minBatteryPct = 80;

  /// While a foot's link is down, the cue repeats this often.
  static const linkLostRepeat = Duration(seconds: 5);

  Map<String, Object> toJson() => {
    'calibrationS': calibration.inMilliseconds / 1000,
    'trialS': trial.inMilliseconds / 1000,
    'practiceS': practice.inMilliseconds / 1000,
    'endWarningS': endWarning.inSeconds,
    'holdToActS': holdToAct.inSeconds,
    'minBatteryPct': minBatteryPct,
  };
}

import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../rules/alert_code.dart';
import '../rules/patient_status.dart';

/// How long rows are kept (S6A; the Alerts footer "แสดงย้อนหลัง 30 วัน").
/// A storage policy, not a clinical threshold, so not in `thresholds.json`.
const retentionPeriod = Duration(days: 30);

/// What an alert row is about: the 8 contract codes (DATA-CONTRACT v1.5
/// §8.3) plus the daily foot check's finding, which is not a contract code
/// (DESIGN-SPEC §7.1).
///
/// [wireName] is what the database stores; renaming it breaks stored rows.
enum AlertKind {
  tempDelta('TEMP_DELTA', AlertCode.tempDelta),
  pressureWatch('PRESSURE_WATCH', AlertCode.pressureWatch),
  pressurePeak('PRESSURE_PEAK', AlertCode.pressurePeak),
  pressurePti('PRESSURE_PTI', AlertCode.pressurePti),
  asymmetryPeak('ASYMMETRY_PEAK', AlertCode.asymmetryPeak),
  loadConcentration('LOAD_CONCENTRATION', AlertCode.loadConcentration),
  deviceLost('DEVICE_LOST', AlertCode.deviceLost),
  batteryLow('BATTERY_LOW', AlertCode.batteryLow),
  footCheckFinding('FOOT_CHECK_FINDING', null);

  const AlertKind(this.wireName, this.code);

  final String wireName;

  /// The contract code, or null for the foot-check finding.
  final AlertCode? code;

  /// Internal level 1–5. A foot-check finding is "ควรระวัง" (DESIGN-SPEC
  /// §7.1), so level 3.
  int get level => code?.level ?? 3;

  /// Whether the patient ever sees this alert in the Alerts list (and so in
  /// the unread badge). Level-2 events are stored for reporting but never
  /// listed (DESIGN-SPEC §7.1); they show only as orange dots and notes.
  ///
  /// The one place this rule lives: the list query and the unread count
  /// both derive from it (`AlertRepository`).
  bool get patientVisible => level != 2;

  static AlertKind fromWire(String name) =>
      values.firstWhere((k) => k.wireName == name);
}

/// An alert to store. The level is not passed: it follows from [kind].
class NewAlert {
  const NewAlert({
    required this.kind,
    required this.patientLevel,
    required this.atMs,
    this.side,
    this.zone,
    this.site,
    this.measuredValue,
    this.threshold,
    this.gaitClass,
    this.gaitConfidence,
    this.details,
    this.captureStamp,
  });

  final AlertKind kind;

  /// What the patient saw when it was raised (FLUTTER-PLAN §7).
  final PatientLevel patientLevel;

  /// Wall-clock time, UTC ms.
  final int atMs;

  /// The foot it is about; for `TEMP_DELTA`, the warmer foot.
  final FootSide? side;

  /// Pressure zone id (`FootZone.id`, e.g. `hallux`).
  final String? zone;

  /// Temperature site for `TEMP_DELTA`.
  final TempSite? site;

  /// The measured value and the threshold it crossed, in the code's unit
  /// (kPa, kPa·s, %, °C, minutes).
  final double? measuredValue;
  final double? threshold;

  /// Model A's class and confidence at that time (contract §8.3.1).
  final String? gaitClass;
  final double? gaitConfidence;

  /// Extra numbers for the detail rows (DESIGN-SPEC §7.3), e.g. both feet's
  /// °C, the consecutive count, the last battery level. JSON-encodable.
  final Map<String, Object?>? details;

  /// The research capture running when it was raised, as its time stamp
  /// only (`20261110-093000`, see [captureStampOf]); never the subject
  /// code.
  final String? captureStamp;
}

class StoredAlert {
  const StoredAlert({
    required this.id,
    required this.kind,
    required this.level,
    required this.patientLevel,
    required this.atMs,
    required this.localDate,
    this.side,
    this.zone,
    this.site,
    this.measuredValue,
    this.threshold,
    this.gaitClass,
    this.gaitConfidence,
    this.details,
    this.readAtMs,
    this.captureStamp,
    this.footCheckId,
  });

  final int id;
  final AlertKind kind;
  final int level;
  final PatientLevel patientLevel;
  final int atMs;

  /// `YYYY-MM-DD` on the phone's calendar when it was raised.
  final String localDate;
  final FootSide? side;
  final String? zone;
  final TempSite? site;
  final double? measuredValue;
  final double? threshold;
  final String? gaitClass;
  final double? gaitConfidence;
  final Map<String, Object?>? details;

  /// When the user first opened it (decision 7); null while unread.
  final int? readAtMs;
  final String? captureStamp;

  /// The foot check behind a `FOOT_CHECK_FINDING`.
  final int? footCheckId;

  bool get isRead => readAtMs != null;
}

/// One foot's 30 s temperature reading. Stored whatever its quality, so the
/// details can say how good the signal was; only `normal` readings are
/// temperatures (web report 011).
class TemperatureReading {
  const TemperatureReading({
    required this.atMs,
    required this.localDate,
    required this.side,
    required this.forefootC,
    required this.heelC,
    required this.quality,
    required this.timeFromArrival,
  });

  final int atMs;
  final String localDate;
  final FootSide side;

  /// null = the sensor could not read (wire `-32768`).
  final double? forefootC;
  final double? heelC;
  final TempQuality quality;

  /// True when [atMs] is the phone's arrival time, not the device time
  /// mapped onto the session clock (`FootTemp.fromArrival`).
  final bool timeFromArrival;
}

class DailySummary {
  const DailySummary({
    required this.localDate,
    required this.alertsByLevel,
    required this.footCheckDone,
    this.steps,
    this.walkingMin,
    this.wornMin,
    this.maxDeltaForefootC,
    this.maxDeltaHeelC,
  });

  final String localDate;

  /// Filled from S8A; null until then.
  final int? steps;
  final int? walkingMin;
  final int? wornMin;

  /// Largest |ΔT| of the day, from two-foot readings only (rule 4).
  final double? maxDeltaForefootC;
  final double? maxDeltaHeelC;

  /// Alerts raised that day, index 0 = level 1 … index 4 = level 5. All
  /// levels, including the ones the patient never sees.
  final List<int> alertsByLevel;
  final bool footCheckDone;
}

/// A foot-check answer. Unanswered is null (decision 9).
enum FootCheckAnswer { none, yesOrUnsure }

enum FootCheckResult { saved, found }

/// The 4 photo views (FLUTTER-PLAN §9, DESIGN-SPEC §11.2), in capture order.
enum FootView { soleLeft, soleRight, topLeft, topRight }

/// What the foot check screen hands over on "บันทึก".
class FootCheckDraft {
  const FootCheckDraft({
    required this.atMs,
    required this.redness,
    required this.wound,
    required this.swelling,
    required this.answerOnly,
    this.photos = const {},
  });

  final int atMs;

  /// "เห็นรอยแดง หรือผิวเปลี่ยนสีไหม"
  final FootCheckAnswer? redness;

  /// "เห็นแผล รอยถลอก หรือตุ่มพองไหม"
  final FootCheckAnswer? wound;

  /// "เท้าบวม หรือผิดรูปไปจากเดิมไหม"
  final FootCheckAnswer? swelling;
  final bool answerOnly;

  /// Photo paths relative to the foot-photo folder; a missing view was
  /// skipped.
  final Map<FootView, String> photos;
}

class FootCheck {
  const FootCheck({
    required this.id,
    required this.atMs,
    required this.localDate,
    required this.redness,
    required this.wound,
    required this.swelling,
    required this.result,
    required this.photos,
    required this.answerOnly,
  });

  final int id;
  final int atMs;
  final String localDate;
  final FootCheckAnswer? redness;
  final FootCheckAnswer? wound;
  final FootCheckAnswer? swelling;
  final FootCheckResult result;
  final Map<FootView, String> photos;
  final bool answerOnly;
}

/// The research capture's time stamp from its session id
/// (`SI-001_20261110-093000` → `20261110-093000`). The database keeps only
/// this part: no subject codes in it (IRB).
String captureStampOf(String sessionId) {
  final i = sessionId.lastIndexOf('_');
  return i < 0 ? sessionId : sessionId.substring(i + 1);
}

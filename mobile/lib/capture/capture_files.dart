import 'dart:convert';
import 'dart:io';

import '../ble/ble_protocol.dart';
import '../ble/calibration.dart';
import '../ble/packets.dart';
import '../device/foot_sample.dart';
import 'capture_protocol.dart';

/// File formats of research capture. One CSV per trial attempt, long format
/// (one row per sample per foot), plus a JSON sidecar per attempt and one
/// `session.json`. The Python loader (`tools/capture/load_capture.py`)
/// reads exactly these names; bump [captureSchema] on any change.
///
/// Schema 2 (S8D, DATA-CONTRACT v1.6): 8 FSR channels per foot and 8
/// temperature sites (`temp0_c`…`temp7_c`, `temp0_q`…`temp7_q`) in place
/// of schema 1's `temp_forefoot_c` / `temp_heel_c` / `temp_quality`.
const captureSchema = 2;

/// Root of all capture data in the app's private storage.
const researchDirName = 'research';

/// The columns of one foot's values: the `shared/model_input.json` names
/// without their `L_`/`R_` prefix (a test checks), so a model channel is
/// `<side>_<column>`.
List<String> footValueColumns(int fsrCount) => [
  for (var i = 0; i < fsrCount; i++) 'fsr${i}_adc',
  for (var i = 0; i < fsrCount; i++) 'fsr${i}_kpa',
  for (final a in const ['x', 'y', 'z']) 'accel_${a}_g',
  for (final a in const ['x', 'y', 'z']) 'gyro_${a}_dps',
];

/// Model channel name of a per-foot column, e.g. `L_fsr0_kpa`.
String modelChannelOf(FootSide side, String column) =>
    '${sideCode(side)}_$column';

/// The CSV header for [fsrCount] FSR channels per foot.
List<String> csvColumns(int fsrCount) => [
  'unix_ms', // DeviceClock (S4): sample time on the phone's unix clock
  'device_ms', // t0 + 20 i on the board's clock (rule 1)
  'side', // L / R
  'conn_session', // streaming session of that foot; changes on reconnect
  'seq', // packet seq (restarts at 0 per session)
  'i', // sample index in the packet
  'missing_before', // packets lost just before this row's packet (on the
  //                   packet's first row written; 0 elsewhere)
  'saturated', // packet flags bit0
  'calibrating', // packet flags bit1
  'valid', // 0 inside a segment the researcher marked invalid
  ...footValueColumns(fsrCount),
  'temp_unix_ms', // set on the first row written after a reading arrives
  ...tempColumns,
];

/// One reading's columns: °C per site (empty = could not read), then each
/// site's quality (`normal` / `poorContact` / `sensorFault`). Site i is
/// the NTC next to FSR i.
final tempColumns = [
  for (var i = 0; i < TempLayout.siteCount; i++) 'temp${i}_c',
  for (var i = 0; i < TempLayout.siteCount; i++) 'temp${i}_q',
];

String sideCode(FootSide side) => side == FootSide.left ? 'L' : 'R';

/// Number formats: enough digits for each unit, no exponent notation.
String _f(double v, int digits) => v.toStringAsFixed(digits);

/// One CSV row (no newline).
String csvRow({
  required FootSide side,
  required FootBatch batch,
  required int i,
  required bool valid,
  int missingBefore = 0,
  FootTemp? temp,
}) {
  final s = batch.samples[i];
  return [
    _f(s.unixMs, 3),
    '${s.deviceMs}',
    sideCode(side),
    '${batch.session}',
    '${batch.seq}',
    '$i',
    '$missingBefore',
    batch.saturated ? '1' : '0',
    batch.calibrating ? '1' : '0',
    valid ? '1' : '0',
    for (final a in s.fsrAdc) '$a',
    for (final k in s.fsrKpa) _f(k, 3),
    for (final g in s.accelG) _f(g, 6),
    for (final d in s.gyroDps) _f(d, 4),
    temp == null ? '' : _f(temp.unixMs, 3),
    for (var c = 0; c < TempLayout.siteCount; c++)
      switch (temp?.packet.celsius[c]) {
        final v? => _f(v, 2),
        null => '',
      },
    for (var c = 0; c < TempLayout.siteCount; c++)
      temp == null ? '' : temp.packet.quality[c].name,
  ].join(',');
}

/// `SI-001_20261110-093000`.
String sessionIdOf(SubjectCode code, DateTime at) =>
    '${code.code}_${_stamp(at)}';

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// What a trial records: the standing calibration or one gait.
class TrialPlan {
  const TrialPlan.calibration() : number = 0, gait = null;
  const TrialPlan.gait(this.number, GaitClass this.gait);

  /// 0 = calibration, 1–5 = gaits in the subject's order.
  final int number;
  final GaitClass? gait;

  bool get isCalibration => gait == null;

  /// The label in file names and sidecars.
  String get label => gait?.id ?? 'calibration';
}

/// `SI-001_01_normal_a1` (no extension).
String attemptBaseName(SubjectCode code, TrialPlan plan, int attempt) =>
    '${code.code}_${plan.number.toString().padLeft(2, '0')}_'
    '${plan.label}_a$attempt';

Map<String, Object?> calibrationJson(Calibration? c) => c == null
    ? {'deviceId': null}
    : {
        'deviceId': c.deviceId,
        'rPulldownOhm': c.rPulldownOhm,
        'sensorAreaM2': c.sensorAreaM2,
        'channels': [
          for (final ch in c.channels)
            {
              'index': ch.index,
              'a': ch.a,
              'b': ch.b,
              'offsetAdc': ch.offsetAdc,
            },
        ],
      };

/// Writes JSON atomically (temp file, then rename), so a crash never
/// leaves half a sidecar.
void writeJsonAtomic(File file, Map<String, Object?> json) {
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    flush: true,
  );
  tmp.renameSync(file.path);
}

Map<String, Object?> readJson(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

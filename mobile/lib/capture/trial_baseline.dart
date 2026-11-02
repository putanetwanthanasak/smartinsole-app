import 'dart:io';

import '../ble/packets.dart';
import '../config/thresholds.dart';
import '../device/model_channels.dart';
import '../gait/baseline_window.dart';
import '../gait/preprocess.dart';
import 'capture_files.dart';

/// One foot's baseline from a capture trial: the window's values, or the
/// failure that ended it.
class FootTrialBaseline {
  const FootTrialBaseline({
    required this.failure,
    required this.sampleCount,
    required this.values,
  });

  /// Null when the foot passed.
  final BaselineFailure? failure;

  /// Rows kept (the whole window when it passed).
  final int sampleCount;

  /// The 14 per-channel medians in model order, when it passed.
  final List<double>? values;
}

/// Capture trial 00's baseline per foot (BACKLOG 74): the trial's CSV rows
/// through the same [FootBaselineWindow] as the Researcher recording, as
/// `tools/model/preprocess.py trial_baseline` does in training. Read only
/// after the trial's file is closed; it never touches the recording.
class TrialBaseline {
  const TrialBaseline(this.feet);

  final Map<FootSide, FootTrialBaseline> feet;

  /// Both feet passed: training gets a baseline from this attempt.
  bool get ok => feet.values.every((f) => f.failure == null);
}

/// [lines] of a capture trial CSV (header first) through the baseline
/// window, per foot in file order.
TrialBaseline trialBaselineOf(
  Iterable<String> lines, {
  required PreprocessSpec spec,
  required Thresholds thresholds,
}) {
  final it = lines.iterator;
  if (!it.moveNext()) throw const FormatException('empty trial CSV');
  final col = {for (final (i, c) in it.current.split(',').indexed) c: i};
  int at(String name) =>
      col[name] ?? (throw FormatException('trial CSV has no $name'));
  final unix = at('unix_ms'), side = at('side'), session = at('conn_session');
  final missing = at('missing_before'), calibrating = at('calibrating');
  final valid = at('valid');
  // Not 8 FSR (a schema-1 trial): no model row, so wrongInsole.
  final kpa = [
    for (var i = 0; col.containsKey('fsr${i}_kpa'); i++) col['fsr${i}_kpa']!,
  ];
  final accel = [
    for (final a in const ['x', 'y', 'z']) at('accel_${a}_g'),
  ];
  final gyro = [
    for (final a in const ['x', 'y', 'z']) at('gyro_${a}_dps'),
  ];

  final windows = {
    for (final s in FootSide.values) s: FootBaselineWindow.of(spec, thresholds),
  };
  while (it.moveNext()) {
    final line = it.current;
    if (line.isEmpty) continue;
    final v = line.split(',');
    double d(int i) => double.parse(v[i]);
    final fsr = [for (final i in kpa) d(i)];
    final a = [for (final i in accel) d(i)];
    windows[v[side] == sideCode(FootSide.left)
            ? FootSide.left
            : FootSide.right]!
        .add(
          BaselineRow(
            unixMs: d(unix),
            session: int.parse(v[session]),
            missingBefore: int.parse(v[missing]),
            calibrating: v[calibrating] == '1',
            valid: v[valid] == '1',
            fsrKpa: fsr,
            accelG: a,
            model: fsr.length == modelFsrCount
                ? [...fsr, ...a, for (final i in gyro) d(i)]
                : null,
          ),
        );
  }
  return TrialBaseline({
    for (final MapEntry(key: s, value: w) in windows.entries)
      s: FootTrialBaseline(
        failure: w.end(),
        sampleCount: w.rows.length,
        values: w.values,
      ),
  });
}

/// [csv] (a closed capture trial file) through [trialBaselineOf].
Future<TrialBaseline> checkTrialBaseline(
  File csv, {
  required PreprocessSpec spec,
  required Thresholds thresholds,
}) async => trialBaselineOf(
  await csv.readAsLines(),
  spec: spec,
  thresholds: thresholds,
);

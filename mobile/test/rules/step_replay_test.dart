import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/fsr_conversion.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/thresholds.dart';
import 'package:smartinsole/rules/asymmetry.dart';
import 'package:smartinsole/rules/step_detector.dart';
import 'package:smartinsole/rules/walking_gate.dart';

import '../helpers/pump_app.dart';

/// BACKLOG 51 (S9): the simulator walk from before 2e2a326 (midfoot
/// {0.40, 0.40, 860}, about 18 kPa), whose summed kPa dips below
/// `steps.contactKpa` for one sample in the hand-off from heel to
/// forefoot. Raw samples from that commit's `synth.cpp`, dumped by
/// `firmware/simulator/tools/presplit_walk/dump_presplit_walk.sh`; read
/// here with each board's TARE offset (S8A boards: left 18–19, right 12).
void main() {
  final t = testThresholds;
  final rows = File('test/fixtures/steps/presplit_walk.csv')
      .readAsLinesSync()
      .skip(1)
      .map((l) => [for (final v in l.split(',')) int.parse(v)])
      .toList();

  // The calibration that simulator served (contract §5.1 example).
  Calibration servedWith(int offsetAdc) => Calibration(
    deviceId: 'replay',
    rPulldownOhm: 10000,
    sensorAreaM2: 0.000113,
    channels: [
      for (var c = 0; c < 6; c++)
        CalibrationChannel(
          index: c,
          a: 123000,
          b: -1.05,
          offsetAdc: offsetAdc.toDouble(),
        ),
    ],
  );

  /// One foot's walk ([side] 0 left, 1 right) read at [offsetAdc].
  List<Step> replay(int side, int offsetAdc, Thresholds th) {
    final cal = servedWith(offsetAdc);
    final gate = WalkingGate(
      windowMs: th.walkingWindowMs,
      accelG: th.walkingAccelG,
    );
    final d = StepDetector(
      side: side == 0 ? FootSide.left : FootSide.right,
      contactKpa: th.stepContactKpa,
      minStanceMs: th.minStanceMs,
      maxStanceMs: th.maxStanceMs,
      mergeGapMs: th.stepMergeGapMs,
    );
    final out = <Step>[];
    for (final r in rows.where((r) => r[1] == side)) {
      final ms = r[0].toDouble();
      final kpa = [
        for (var c = 0; c < 6; c++) adcToKpa(r[2 + c], cal.channels[c], cal),
      ];
      final walking = gate.add(ms, [
        for (var i = 0; i < 3; i++) accelRawToG(r[8 + i]),
      ]);
      final step = d.add(ms, kpa, walking: walking);
      if (step != null) out.add(step);
    }
    return out;
  }

  double meanStance(List<Step> steps) =>
      steps.map((s) => s.durationMs).reduce((a, b) => a + b) / steps.length;

  // The simulator's stride (synth.h kGaitCycleMs): one stance each.
  const strideMs = 1100;
  final durationMs = rows.last[0] + 20;

  for (final offset in [12, 19]) {
    for (final side in [0, 1]) {
      test('offset $offset, ${side == 0 ? 'left' : 'right'}: '
          'one step per stance, each within the stance limits', () {
        final steps = replay(side, offset, t);
        // Every complete stance in the walk: one per stride.
        expect(steps.length, greaterThanOrEqualTo(durationMs ~/ strideMs - 1));
        for (var i = 1; i < steps.length; i++) {
          expect(
            steps[i].startMs - steps[i - 1].startMs,
            strideMs,
            reason: 'step $i starts one stride after the one before',
          );
        }
        for (final s in steps) {
          expect(s.durationMs, inInclusiveRange(t.minStanceMs, t.maxStanceMs));
        }
      });
    }
  }

  test('the two boards\' offsets give stance times that read normal '
      '(PAI below gait.stanceAsymmetryPct / 2)', () {
    // S8A: left TARE'd 18–19, right 12; both pairings.
    for (final (l, r) in [(19, 12), (12, 19)]) {
      final pai = paiPercent(
        meanStance(replay(0, l, t)),
        meanStance(replay(1, r, t)),
      );
      expect(
        pai,
        lessThan(t.stanceAsymmetryPct / 2),
        reason: 'left offset $l, right offset $r',
      );
    }
  });

  test('without the merge the same walk splits (the BACKLOG 51 bug)', () {
    final noMerge = Thresholds.parse(
      File(Thresholds.assetPath)
          .readAsStringSync()
          .replaceFirst('"mergeGapMs": ${t.stepMergeGapMs}', '"mergeGapMs": 0'),
    );
    final steps = replay(0, 19, noMerge);
    // The heel blip is rejected as too short; the step left is shorter.
    expect(meanStance(steps), lessThan(meanStance(replay(0, 19, t)) - 100));
  });
}

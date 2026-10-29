import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/model_channels.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/gait/gait_class.dart';
import 'package:smartinsole/gait/gait_estimator.dart';
import 'package:smartinsole/gait/model_classifier.dart';
import 'package:smartinsole/gait/model_spec.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/gait_note.dart';

import '../helpers/pump_app.dart';
import '../rules/rules_rig.dart';
import 'gait_rig.dart';

/// GaitEstimator on the rules rig: strides in sample time, model or rules
/// (contract §7.5), the gait-note source (§8.3.1), and rule 11.
void main() {
  final normJson = utf8.decode(dummyFile(normalizationFileName));

  (RulesRig, GaitEstimator) makeRig({FakeRunner? model}) {
    final rig = RulesRig()..stream();
    final estimator = GaitEstimator(
      manager: rig.manager,
      engine: rig.engine,
      thresholds: testThresholds,
      spec: testModelInput,
    )..start();
    addTearDown(estimator.stop);
    if (model != null) {
      estimator.slot = ModelReady(
        'test',
        ModelClassifier(
          runner: model,
          normalization: Normalization.parse(normJson, testModelInput),
        ),
      );
    } else {
      estimator.slot = const ModelMissing(releaseModelDir);
    }
    rig.gait = estimator.modelEstimateFor;
    return (rig, estimator);
  }

  const walk = Gait();
  // No load at either heel site (heel centre 5, lateral heel 7).
  const toe = Gait(kpa: [10, 10, 10, 10, 10, 0, 10, 0]);

  test('no model: the rules classify while both feet walk', () async {
    final (rig, est) = makeRig();
    rig.walkBoth(const Duration(seconds: 2), walk);
    expect(est.current, isNull, reason: 'fewer than gait.ruleSteps steps');
    rig.walkBoth(const Duration(seconds: 6), walk);
    final r = est.current!;
    expect(r.gaitClass, GaitClass.normal);
    expect(r.source, GaitSource.rules);
    expect(r.because, RulesBecause.noModel);
    rig.walkBoth(const Duration(seconds: 6), toe);
    expect(est.current!.gaitClass, GaitClass.toeWalking);
  });

  test('stopping: no current result, the last one stays', () async {
    final (rig, est) = makeRig();
    rig.walkBoth(const Duration(seconds: 8), walk);
    final last = est.current!;
    rig.walkBoth(
      const Duration(seconds: 5),
      const Gait.standing([10, 10, 10, 10, 10, 10, 10, 10]),
    );
    expect(est.current, isNull);
    // The newest result shown, from the last strides of the walk.
    expect(est.last!.gaitClass, last.gaitClass);
    expect(est.last!.atMs, greaterThanOrEqualTo(last.atMs));
  });

  test('one foot missing: no result (rule 4)', () async {
    final (rig, est) = makeRig();
    rig.walkBoth(const Duration(seconds: 8), walk);
    rig.run(const Duration(seconds: 8), left: walk);
    expect(est.current, isNull);
  });

  test(
    'a confident model is shown; below minConfidence the rules are',
    () async {
      final runner = FakeRunner([0.05, 0.05, 0.8, 0.05, 0.05]);
      final (rig, est) = makeRig(model: runner);
      rig.walkBoth(const Duration(seconds: 8), walk);
      await pumpEventQueue();
      expect(runner.windows, isNotEmpty);
      expect(runner.windows.first, hasLength(100 * modelChannelCount));
      var r = est.current!;
      expect(r.source, GaitSource.model);
      expect(r.gaitClass, GaitClass.toeWalking);
      expect(r.confidence, 0.8);

      // Just below the boundary: the rules' result, saying why.
      final min = testThresholds.minConfidence;
      runner.probs = [min - 0.01, 0.1, 0.1, 0.1, 0.1];
      rig.walkBoth(const Duration(seconds: 2), walk);
      await pumpEventQueue();
      r = est.current!;
      expect(r.source, GaitSource.rules);
      expect(r.because, RulesBecause.lowConfidence);
      expect(r.gaitClass, GaitClass.normal);

      // Exactly at the boundary: the model.
      runner.probs = [min, 0.1, 0.1, 0.1, 1 - min - 0.3];
      rig.walkBoth(const Duration(seconds: 2), walk);
      await pumpEventQueue();
      expect(est.current!.source, GaitSource.model);
    },
  );

  test('model ready but no result: the rules (contract §7.5)', () async {
    final runner = FakeRunner([0.05, 0.05, 0.8, 0.05, 0.05])..fail = true;
    final (rig, est) = makeRig(model: runner);
    rig.walkBoth(const Duration(seconds: 8), toe);
    await pumpEventQueue();
    expect(runner.windows, isNotEmpty, reason: 'the model was asked');
    var r = est.current!;
    expect(r.source, GaitSource.rules);
    expect(r.because, RulesBecause.noModel);
    expect(r.gaitClass, GaitClass.toeWalking);

    // The model answers again: its result replaces the rules'.
    runner.fail = false;
    rig.walkBoth(const Duration(seconds: 2), toe);
    await pumpEventQueue();
    r = est.current!;
    expect(r.source, GaitSource.model);

    // 320 ms of the right foot's packets lost (its board clock runs on):
    // no gap-free window for the next 2 s, so the rules again.
    rig.run(const Duration(milliseconds: 320), left: toe);
    rig.right.t0 += 320;
    rig.walkBoth(const Duration(milliseconds: 1200), toe);
    await pumpEventQueue();
    r = est.current!;
    expect(r.source, GaitSource.rules);
    expect(r.because, RulesBecause.noModel);
  });

  test('one estimate per stride of sample time', () async {
    final runner = FakeRunner([1, 0, 0, 0, 0]);
    final (rig, _) = makeRig(model: runner);
    rig.walkBoth(const Duration(seconds: 4), walk);
    await pumpEventQueue();
    final before = runner.windows.length;
    rig.walkBoth(const Duration(seconds: 10), walk);
    await pumpEventQueue();
    // 10 s of walking at a 1 s stride (packets every 160 ms).
    expect(runner.windows.length - before, inInclusiveRange(9, 11));
  });

  group('gait note source (contract §8.3.1)', () {
    test('rules give no estimate', () async {
      final (rig, est) = makeRig();
      rig.walkBoth(const Duration(seconds: 8), toe);
      expect(est.current!.gaitClass, GaitClass.toeWalking);
      expect(est.modelEstimateFor(FootSide.left), isNull);
    });

    test(
      'a fresh confident model result does; stale or low ones do not',
      () async {
        final runner = FakeRunner([0.05, 0.05, 0.8, 0.05, 0.05]);
        final (rig, est) = makeRig(model: runner);
        rig.walkBoth(const Duration(seconds: 8), walk);
        await pumpEventQueue();
        final e = est.modelEstimateFor(FootSide.right)!;
        expect(e.gaitClass, 'toe_walking');
        expect(e.confidence, 0.8);

        // Standing: no new estimate; after a window + stride it is stale.
        rig.walkBoth(
          const Duration(seconds: 4),
          const Gait.standing([10, 10, 10, 10, 10, 10, 10, 10]),
        );
        expect(est.modelEstimateFor(FootSide.right), isNull);

        runner.probs = [0.5, 0.2, 0.1, 0.1, 0.1];
        rig.walkBoth(const Duration(seconds: 8), walk);
        await pumpEventQueue();
        expect(est.modelEstimateFor(FootSide.right), isNull);
      },
    );

    test(
      'rule 11: the note never changes a level; rotated_foot gets none',
      () async {
        // A walk with a 240 kPa meta1 peak raises PRESSURE_PEAK (level 3).
        const peak = Gait(kpa: [0, 240, 0, 0, 0, 0, 0, 0]);
        final stored = <int>{};
        final shown = <Object>{};
        for (final probs in [
          null,
          [0.02, 0.02, 0.9, 0.03, 0.03],
          [0.02, 0.02, 0.03, 0.03, 0.9],
        ]) {
          final (rig, _) = makeRig(
            model: probs == null ? null : FakeRunner(probs),
          );
          // An estimate first, then the high peak.
          rig.walkBoth(const Duration(seconds: 8), walk);
          await pumpEventQueue();
          rig.walkBoth(const Duration(seconds: 2), peak);
          await pumpEventQueue();
          final a = (await rig.stored()).firstWhere(
            (a) => a.kind.code == AlertCode.pressurePeak,
          );
          stored.add(a.level);
          shown.add(rig.view().status.level);
          final note = gaitNoteTh(
            code: AlertCode.pressurePeak,
            zoneId: a.zone,
            gaitClass: a.gaitClass,
            confidence: a.gaitConfidence,
            thresholds: testThresholds,
          );
          switch (probs) {
            case null:
              expect(a.gaitClass, isNull, reason: 'rules give no note');
            case [_, _, 0.9, ...]:
              expect(a.gaitClass, 'toe_walking');
              expect(note, contains('เขย่งปลายเท้า'));
            default:
              // BACKLOG 41: stored, but no in/out-toeing note.
              expect(a.gaitClass, 'rotated_foot');
              expect(a.gaitConfidence, 0.9);
              expect(note, isNull);
          }
        }
        expect(stored, {AlertCode.pressurePeak.level});
        expect(shown, hasLength(1), reason: 'the same status every time');
      },
    );
  });

  test('PTI asymmetry and CoP from the engine\'s steps', () async {
    final (rig, est) = makeRig();
    expect(est.ptiAsymmetryPct(), isNull);
    expect(est.copPathOf(FootSide.left), isNull);
    rig.walkBoth(
      const Duration(seconds: 6),
      walk,
      right: const Gait(kpa: [5, 5, 5, 5, 5, 5, 5, 5], phaseMs: 500),
    );
    // Mean whole-foot PTI 80 vs 40 per step: |80 − 40| / 60 × 100.
    expect(est.ptiAsymmetryPct(), closeTo(66.7, 0.5));
    final path = est.copPathOf(FootSide.left)!;
    expect(path, isNotEmpty);
  });
}

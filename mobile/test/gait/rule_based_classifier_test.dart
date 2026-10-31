import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/gait/gait_class.dart';
import 'package:smartinsole/gait/gait_classifier.dart';
import 'package:smartinsole/gait/rule_based_classifier.dart';
import 'package:smartinsole/rules/step_detector.dart';

import '../helpers/pump_app.dart';
import 'gait_rig.dart';

/// The provisional rule-based classifier (contract §7.5), every boundary
/// from `gait.*` in thresholds.json.
void main() {
  final t = testThresholds;
  final rules = RuleBasedClassifier(testThresholds);
  final n = t.gaitRuleSteps;

  // Zone order: hallux, meta1, meta3, meta5, midfoot, heel, medialArch,
  // lateralHeel. Heel = {5, 7}, forefoot = {0–3} (shared/sensor_layout.json).
  List<Step> steps(
    FootSide side, {
    List<double> pti = const [10, 10, 10, 10, 10, 10, 10, 10],
    double durationMs = 600,
    int count = 4,
  }) => [
    for (var i = 0; i < count; i++)
      step(side, endMs: 1000.0 * (i + 1), durationMs: durationMs, ptiKpaS: pti),
  ];

  GaitResult? classify(List<Step> left, List<Step> right) => rules.classifyNow(
    GaitInput(atMs: 9000, leftSteps: left, rightSteps: right),
  );

  test('too few steps on either foot: no result', () {
    expect(
      classify(steps(FootSide.left, count: n - 1), steps(FootSide.right)),
      isNull,
    );
    expect(
      classify(steps(FootSide.left), steps(FootSide.right, count: n - 1)),
      isNull,
    );
  });

  test('even load on every zone: normal, from the rules', () {
    final r = classify(steps(FootSide.left), steps(FootSide.right))!;
    expect(r.gaitClass, GaitClass.normal);
    expect(r.source, GaitSource.rules);
    expect(r.confidence, isNull);
    expect(r.probs, isNull);
  });

  test('toe walking: heel share below gait.toeHeelPtiPct', () {
    // Heel share = h / (60 + h), h split over both heel sites; just below
    // and at the boundary.
    double heelFor(double pct) => 60 * pct / (100 - pct);
    final below = heelFor(t.toeHeelPtiPct - 0.5);
    final at = heelFor(t.toeHeelPtiPct);
    List<double> pti(double heel) => [
      10,
      10,
      10,
      10,
      10,
      heel / 2,
      10,
      heel / 2,
    ];
    expect(
      classify(
        steps(FootSide.left, pti: pti(below)),
        steps(FootSide.right, pti: pti(below)),
      )!.gaitClass,
      GaitClass.toeWalking,
    );
    expect(
      classify(
        steps(FootSide.left, pti: pti(at)),
        steps(FootSide.right, pti: pti(at)),
      )!.gaitClass,
      GaitClass.normal,
    );
  });

  test('the heel is both heel sites: a loaded lateral heel alone is not '
      'toe walking (user decision 2026-10-29)', () {
    final lateral = 60 * (t.toeHeelPtiPct + 5) / (100 - t.toeHeelPtiPct - 5);
    List<Step> on(FootSide side, List<double> pti) => steps(side, pti: pti);
    final only7 = <double>[10, 10, 10, 10, 10, 0, 10, lateral];
    expect(
      classify(on(FootSide.left, only7), on(FootSide.right, only7))!.gaitClass,
      GaitClass.normal,
    );
    const none = <double>[10, 10, 10, 10, 10, 0, 10, 0];
    expect(
      classify(on(FootSide.left, none), on(FootSide.right, none))!.gaitClass,
      GaitClass.toeWalking,
    );
  });

  test('heel walking: forefoot share below gait.heelForefootPtiPct', () {
    // Forefoot (4 zones of f) share = 4f / (4f + 60); the medial arch is
    // in the whole only.
    double foreFor(double pct) => 60 * pct / (100 - pct) / 4;
    List<double> pti(double f) => [f, f, f, f, 10, 25, 0, 25];
    final below = foreFor(t.heelForefootPtiPct - 0.5);
    final at = foreFor(t.heelForefootPtiPct);
    expect(
      classify(
        steps(FootSide.left, pti: pti(below)),
        steps(FootSide.right, pti: pti(below)),
      )!.gaitClass,
      GaitClass.heelWalking,
    );
    expect(
      classify(
        steps(FootSide.left, pti: pti(at)),
        steps(FootSide.right, pti: pti(at)),
      )!.gaitClass,
      GaitClass.normal,
    );
  });

  test('antalgic: stance-time PAI above gait.stanceAsymmetryPct', () {
    // PAI(600, s) = (600 − s) / ((600 + s) / 2) × 100.
    double shortFor(double pct) => 600 * (200 - pct) / (200 + pct);
    final over = shortFor(t.stanceAsymmetryPct + 1);
    // Just below: exactly at it is not testable through float division.
    final at = shortFor(t.stanceAsymmetryPct - 0.1);
    expect(
      classify(
        steps(FootSide.left),
        steps(FootSide.right, durationMs: over),
      )!.gaitClass,
      GaitClass.antalgic,
    );
    expect(
      classify(
        steps(FootSide.left),
        steps(FootSide.right, durationMs: at),
      )!.gaitClass,
      GaitClass.normal,
    );
  });

  test('only the newest gait.ruleSteps steps count', () {
    final left = [
      ...steps(FootSide.left, pti: [10, 10, 10, 10, 10, 0, 10, 0]),
      ...steps(FootSide.left),
    ];
    expect(classify(left, steps(FootSide.right))!.gaitClass, GaitClass.normal);
  });

  test('never rotated_foot: only the model can say that', () {
    for (final pti in const [
      <double>[30, 5, 5, 30, 20, 10, 5, 10],
      <double>[5, 30, 30, 5, 20, 10, 15, 5],
    ]) {
      expect(
        classify(
          steps(FootSide.left, pti: pti),
          steps(FootSide.right, pti: pti),
        )!.gaitClass,
        isNot(GaitClass.rotatedFoot),
      );
    }
  });

  test('carries why the rules were used', () {
    final r = rules.classifyNow(
      GaitInput(
        atMs: 1,
        leftSteps: steps(FootSide.left),
        rightSteps: steps(FootSide.right),
      ),
      because: RulesBecause.lowConfidence,
    )!;
    expect(r.because, RulesBecause.lowConfidence);
  });
}

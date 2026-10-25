import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/config/thresholds.dart';
import 'package:smartinsole/storage/models.dart';

void main() {
  test('the bundled copy is byte-identical to shared/thresholds.json', () {
    // Flutter cannot bundle files outside mobile/, so the app carries a
    // copy. Fix: cp ../shared/thresholds.json assets/config/
    expect(
      File(Thresholds.assetPath).readAsBytesSync(),
      File('../shared/thresholds.json').readAsBytesSync(),
    );
  });

  test('parses every value the app reads', () {
    final t = Thresholds.parse(
      File('../shared/thresholds.json').readAsStringSync(),
    );
    expect(t.watchKpa, 75);
    expect(t.alertKpa, 200);
    expect(t.deltaC, 2.2);
    expect(t.consecutiveReadings, 2);
    expect(t.peakAsymmetryPct, 15);
    expect(t.minConfidence, 0.60);
    expect(t.walkingWindowMs, 800);
    // Added in S5 (BACKLOG 30), contract §8.3 BATTERY_LOW.
    expect(t.batteryLowPct, 15);
    // Added in S7: contract §8.3 numbers not in the file before, plus the
    // provisional step detection (BACKLOG 31).
    expect(t.ptiKpaS, 80);
    expect(t.ptiWindowMin, 60);
    expect(t.ptiMinSteps, 20);
    expect(t.peakHoldMs, 2500);
    expect(t.peakAsymmetrySteps, 20);
    expect(t.concentrationPct, 40);
    expect(t.concentrationSteps, 20);
    expect(t.deviceLostAfterMin, 5);
    expect(t.repeatMin, 30);
    expect(t.stepContactKpa, 10);
    expect(t.minStanceMs, 250);
    expect(t.maxStanceMs, 2500);
    // Added in S8A: the confidence meter's top segment and the provisional
    // rule-based gait classifier.
    expect(t.highConfidence, 0.85);
    expect(t.gaitRuleSteps, 4);
    expect(t.toeHeelPtiPct, 10);
    expect(t.heelForefootPtiPct, 15);
    expect(t.stanceAsymmetryPct, 15);
  });

  test('sources: one per alert code, from DATA-CONTRACT §8.3', () {
    final t = Thresholds.parse(
      File('../shared/thresholds.json').readAsStringSync(),
    );
    expect(t.sources.keys.toSet(), {
      for (final k in AlertKind.values)
        if (k.code != null) k.wireName,
    });
    expect(t.sourceOf('TEMP_DELTA'), 'Lavery et al. (2004)');
    expect(t.sourceOf('PRESSURE_PEAK'), 'Owings et al. (2009)');
    expect(t.sourceOf('PRESSURE_PTI'), 'Waaijman et al. (2014)');
    expect(t.sourceOf('LOAD_CONCENTRATION'), 'ตัวชี้วัดของโครงงาน');
    // "—" in the contract: no row on the detail screen.
    expect(t.sourceOf('DEVICE_LOST'), isNull);
    expect(t.sourceOf('BATTERY_LOW'), isNull);
  });
}

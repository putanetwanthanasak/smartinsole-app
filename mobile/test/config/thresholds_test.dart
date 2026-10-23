import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/config/thresholds.dart';

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
  });
}

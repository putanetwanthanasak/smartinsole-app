import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/walking_gate.dart';

import '../helpers/pump_app.dart';

void main() {
  final t = testThresholds;
  WalkingGate gate() =>
      WalkingGate(windowMs: t.walkingWindowMs, accelG: t.walkingAccelG);

  /// One window of samples, each with |‖a‖ − 1 g| = [dev].
  bool fill(WalkingGate g, double dev, {double from = 0}) {
    var on = false;
    for (var ms = 0; ms < t.walkingWindowMs; ms += 20) {
      on = g.add(from + ms, [0, 0, 1 + dev]);
    }
    return on;
  }

  test('walking at exactly walkingAccelG, not 1 mg below (§8.3.2)', () {
    expect(fill(gate(), t.walkingAccelG), isTrue);
    expect(fill(gate(), t.walkingAccelG - 0.001), isFalse);
    expect(fill(gate(), 0), isFalse, reason: 'standing still');
  });

  test('the magnitude, so a still foot at any angle is not walking', () {
    final g = gate();
    for (var ms = 0; ms < t.walkingWindowMs; ms += 20) {
      // 1 g along a tilted axis.
      expect(g.add(ms.toDouble(), const [0.6, 0, 0.8]), isFalse);
    }
  });

  test('the window ends at the newest sample and is walkingWindowMs '
      'long', () {
    final g = gate();
    expect(fill(g, 0.3), isTrue);
    // A still foot: the walking samples leave the window one by one.
    var ms = t.walkingWindowMs.toDouble();
    var on = true;
    var stillFor = 0.0;
    while (on) {
      on = g.add(ms, const [0, 0, 1]);
      ms += 20;
      stillFor += 20;
    }
    // Half the window still (mean 0.15 g) is the last "walking" one.
    expect(stillFor, t.walkingWindowMs / 2 + 20);
    g.reset();
    expect(g.walking, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/weight_share.dart';

import '../helpers/pump_app.dart';

void main() {
  test('shares are each foot\'s part of the summed load', () {
    final w = WeightShare.of(300, 200)!;
    expect(w.leftSharePct, closeTo(60, 1e-9));
    expect(w.leftHeavier, isTrue);
    expect(WeightShare.of(200, 300)!.leftHeavier, isFalse);
    expect(WeightShare.of(250, 250)!.leftHeavier, isNull);
  });

  test('no load on either foot is undefined, not 50 : 50', () {
    expect(WeightShare.of(0, 0), isNull);
    expect(() => WeightShare.of(-1, 2), throwsArgumentError);
  });

  test('uneven only above asymmetry.peakPct (from thresholds.json)', () {
    final t = testThresholds;
    // L = R × (200 + p) / (200 − p) gives a PAI of exactly p.
    const r = 100.0;
    final l = r * (200 + t.peakAsymmetryPct) / (200 - t.peakAsymmetryPct);
    expect(WeightShare.of(l * 0.999, r)!.isUneven(t), isFalse);
    expect(WeightShare.of(l * 1.01, r)!.isUneven(t), isTrue);
    expect(WeightShare.of(r, l * 1.01)!.isUneven(t), isTrue);
  });
}

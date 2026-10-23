import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/asymmetry.dart';

import '../helpers/pump_app.dart';

void main() {
  test('PAI is |L − R| / ((L + R) / 2) × 100 (contract §8.2)', () {
    final a = PeakAsymmetry.of(150, 60)!;
    expect(a.paiPct, closeTo(90 / 105 * 100, 1e-9));
    expect(PeakAsymmetry.of(60, 60)!.paiPct, 0);
    expect(PeakAsymmetry.of(100, 0)!.paiPct, 200);
  });

  test('balance shares come from the same two peaks', () {
    final a = PeakAsymmetry.of(55, 45)!;
    expect(a.leftSharePct, closeTo(55, 1e-9));
    // 55 : 45 is PAI 20 %.
    expect(a.paiPct, closeTo(20, 1e-9));
    expect(a.leftHigher, isTrue);
    expect(PeakAsymmetry.of(45, 55)!.leftHigher, isFalse);
    expect(PeakAsymmetry.of(50, 50)!.leftHigher, isNull);
  });

  test('no load on either foot is undefined, not 0 %', () {
    expect(PeakAsymmetry.of(0, 0), isNull);
  });

  test('uneven only above asymmetry.peakPct (from thresholds.json)', () {
    final t = testThresholds;
    // L = R × (200 + p) / (200 − p) gives PAI = p.
    const r = 100.0;
    final l = r * (200 + t.peakAsymmetryPct) / (200 - t.peakAsymmetryPct);
    expect(PeakAsymmetry.of(l, r)!.paiPct, closeTo(t.peakAsymmetryPct, 1e-9));
    expect(PeakAsymmetry.of(l * 0.999, r)!.isUneven(t), isFalse);
    expect(PeakAsymmetry.of(l * 1.01, r)!.isUneven(t), isTrue);
  });

  test('negative peaks are a bug', () {
    expect(() => PeakAsymmetry.of(-1, 2), throwsArgumentError);
  });
}

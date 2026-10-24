import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/step_detector.dart';

import '../helpers/pump_app.dart';

void main() {
  final t = testThresholds;
  StepDetector detector() => StepDetector(
    side: FootSide.left,
    contactKpa: t.stepContactKpa,
    minStanceMs: t.minStanceMs,
    maxStanceMs: t.maxStanceMs,
  );

  /// [n] loaded samples of [kpa] every 20 ms from [from], then one
  /// unloaded sample; returns what the detector made of it.
  Step? stance(
    StepDetector d,
    int n,
    List<double> kpa, {
    bool walking = true,
    double from = 0,
  }) {
    Step? out;
    for (var i = 0; i <= n; i++) {
      final step = d.add(
        from + i * 20,
        i < n ? kpa : List.filled(kpa.length, 0),
        walking: walking,
      );
      if (step != null) out = step;
    }
    return out;
  }

  test('a walking stance is a step with per-zone peak and PTI', () {
    // 63 samples of 64 kPa: 62 trapezoids of 20 ms at 64, plus the last
    // one down to 0: 64 × (62 × 20 + 10) = 80 000 kPa·ms = 80 kPa·s.
    final s = stance(detector(), 63, const [0, 64, 0, 0, 0, 32])!;
    expect(s.side, FootSide.left);
    expect(s.durationMs, 1260);
    expect(s.peakKpa, [0, 64, 0, 0, 0, 32]);
    expect(s.ptiKpaMs[1], 80000);
    expect(s.ptiKpaS[1], 80);
    expect(s.ptiKpaMs[5], 40000);
    expect(s.maxPeakKpa, 64);
    expect(s.topZoneShare, (1, 64 * 100 / 96));
  });

  test('standing, shifting weight or sitting are not steps', () {
    expect(
      stance(detector(), 63, const [0, 64, 0, 0, 0, 0], walking: false),
      isNull,
    );
  });

  test('the gate needs to be on at one sample of the stance only', () {
    final d = detector();
    Step? out;
    for (var i = 0; i <= 30; i++) {
      out ??= d.add(
        i * 20.0,
        i < 30 ? const [50, 0, 0, 0, 0, 0] : const [0, 0, 0, 0, 0, 0],
        walking: i == 0, // the heel-strike jolt
      );
    }
    expect(out, isNotNull);
  });

  test('stance length limits (steps.minStanceMs / maxStanceMs)', () {
    const kpa = <double>[0, 0, 0, 0, 0, 60];
    // 13 samples → 260 ms; 12 → 240 ms (minStanceMs 250).
    expect(stance(detector(), 13, kpa), isNotNull);
    expect(stance(detector(), 12, kpa), isNull);
    // 125 samples → 2500 ms (maxStanceMs) is a step; 126 → 2520 ms not.
    expect(stance(detector(), 125, kpa), isNotNull);
    expect(stance(detector(), 126, kpa), isNull);
  });

  test('contact is above contactKpa: at it is unloaded', () {
    final at = t.stepContactKpa;
    expect(stance(detector(), 30, [at, 0, 0, 0, 0, 0]), isNull);
    expect(stance(detector(), 30, [at + 0.5, 0, 0, 0, 0, 0]), isNotNull);
  });

  test('reset drops a stance in progress (lost packets, reconnect)', () {
    final d = detector();
    for (var i = 0; i < 20; i++) {
      d.add(i * 20.0, const [0, 0, 0, 0, 0, 60], walking: true);
    }
    d.reset();
    expect(d.add(400, const [0, 0, 0, 0, 0, 0], walking: true), isNull);
  });

  test('concentration share is exact at 40 of 100', () {
    final s = stance(detector(), 20, const [40, 10, 10, 10, 10, 20])!;
    expect(s.topZoneShare, (0, 40.0));
  });
}

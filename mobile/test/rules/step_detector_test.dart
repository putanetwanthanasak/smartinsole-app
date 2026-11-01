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
    mergeGapMs: t.stepMergeGapMs,
  );

  /// Unloaded samples after a stance until its step is due: the stance
  /// may still go on through a dip shorter than `steps.mergeGapMs`
  /// (BACKLOG 51), so the step comes that long after its end.
  final pad = t.stepMergeGapMs ~/ 20;

  /// [n] loaded samples of [kpa] every 20 ms from [from], then unloaded
  /// samples for `steps.mergeGapMs`; returns what the detector made of it.
  Step? stance(
    StepDetector d,
    int n,
    List<double> kpa, {
    bool walking = true,
    double from = 0,
  }) {
    Step? out;
    for (var i = 0; i <= n + pad; i++) {
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
    for (var i = 0; i <= 30 + pad; i++) {
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

  group('a short dip does not end a stance (BACKLOG 51, steps.mergeGapMs)', () {
    const heel = <double>[0, 0, 0, 0, 0, 60];

    /// Feeds [loaded] (true = [heel], false = nothing) every 20 ms from 0;
    /// returns each step with the time of the sample that returned it.
    List<(Step, double)> feed(StepDetector d, List<bool> loaded) {
      final out = <(Step, double)>[];
      for (var i = 0; i < loaded.length; i++) {
        final ms = i * 20.0;
        final s = d.add(
          ms,
          loaded[i] ? heel : const [0, 0, 0, 0, 0, 0],
          walking: true,
        );
        if (s != null) out.add((s, ms));
      }
      return out;
    }

    List<bool> run(List<(bool, int)> parts) => [
      for (final (on, n) in parts) ...List.filled(n, on),
    ];

    test('a dip shorter than mergeGapMs is part of the stance', () {
      final dipSamples = t.stepMergeGapMs ~/ 20 - 1;
      final steps = feed(
        detector(),
        run([(true, 8), (false, dipSamples), (true, 15), (false, pad + 1)]),
      );
      expect(steps, hasLength(1));
      expect(steps.single.$1.startMs, 0);
      expect(steps.single.$1.durationMs, (8 + dipSamples + 15) * 20);
    });

    test('a gap of mergeGapMs or more is a swing: two steps', () {
      final steps = feed(
        detector(),
        run([(true, 15), (false, pad), (true, 15), (false, pad + 1)]),
      );
      expect(steps, hasLength(2));
      expect(steps[0].$1.durationMs, 300);
      expect(steps[1].$1.startMs, (15 + pad) * 20);
    });

    test('the step comes no later than mergeGapMs after the stance ends', () {
      final steps = feed(detector(), run([(true, 30), (false, pad * 3)]));
      final (step, returnedAt) = steps.single;
      expect(step.endMs, 600);
      expect(returnedAt - step.endMs, lessThanOrEqualTo(t.stepMergeGapMs));
      // With samples every 20 ms it is exactly the first sample that far.
      expect(returnedAt - step.endMs, t.stepMergeGapMs);
    });

    test('a step that waits out the window has its figures at its end', () {
      // The same stance with and without the wait: identical step.
      final now = StepDetector(
        side: FootSide.left,
        contactKpa: t.stepContactKpa,
        minStanceMs: t.minStanceMs,
        maxStanceMs: t.maxStanceMs,
        mergeGapMs: 0,
      );
      final a = feed(now, run([(true, 30), (false, 1)])).single.$1;
      final b = feed(detector(), run([(true, 30), (false, pad + 1)])).single.$1;
      expect(b.startMs, a.startMs);
      expect(b.endMs, a.endMs);
      expect(b.peakKpa, a.peakKpa);
      expect(b.ptiKpaMs, a.ptiKpaMs);
    });

    test('reset also drops a stance waiting out the window', () {
      final d = detector();
      feed(d, run([(true, 30), (false, 1)]));
      d.reset();
      expect(d.add(2000, const [0, 0, 0, 0, 0, 0], walking: true), isNull);
    });
  });
}

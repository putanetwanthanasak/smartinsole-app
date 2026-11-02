import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/gait/baseline_window.dart';

import '../helpers/pump_app.dart';

/// The one baseline function (S9, BACKLOG 74): the first
/// `baselineSeconds` × 50 Hz rows that pass, one named failure otherwise.
/// The shared trial-00 fixture is checked in trial_baseline_test.dart.
void main() {
  final t = testThresholds;
  final n = FootBaselineWindow.windowSamples(testPreprocess);

  BaselineRow row(
    int i, {
    int session = 1,
    int missingBefore = 0,
    bool calibrating = false,
    bool valid = true,
    double kpa = 25,
    List<double> accel = const [0, 0, 1],
    bool eightFsr = true,
  }) => BaselineRow(
    unixMs: 1000.0 + i * 20,
    session: session,
    missingBefore: missingBefore,
    calibrating: calibrating,
    valid: valid,
    fsrKpa: List.filled(8, kpa),
    accelG: accel,
    model: eightFsr
        ? [...List.filled(8, kpa + i % 3), ...accel, 0, 0, 0]
        : null,
  );

  FootBaselineWindow make() => FootBaselineWindow.of(testPreprocess, t);

  test('the window is baselineSeconds at 50 Hz', () {
    expect(n, testPreprocess.baselineSeconds * 50);
  });

  test('complete at exactly the Nth row; later rows are ignored', () {
    final w = make();
    for (var i = 0; i < n - 1; i++) {
      expect(w.add(row(i)), isNull);
    }
    expect(w.complete, isFalse);
    expect(w.values, isNull);
    w.add(row(n - 1));
    expect(w.complete, isTrue);
    expect(w.progress, 1);
    // A later row breaking every rule changes nothing.
    expect(w.add(row(n, session: 9, calibrating: true, valid: false)), isNull);
    expect(w.rows, hasLength(n));
    expect(w.end(), isNull);
    expect(w.values!.sublist(0, 8), List.filled(8, 26.0));
  });

  test('the first row\'s lost packets and session are not a failure', () {
    final w = make();
    expect(w.add(row(0, missingBefore: 3, session: 7)), isNull);
    expect(w.add(row(1, session: 7)), isNull);
    expect(w.add(row(2, session: 8)), BaselineFailure.reconnected);
  });

  test('each rule names its failure', () {
    BaselineFailure? second(BaselineRow r) => (make()..add(row(0))).add(r);
    expect(second(row(1, missingBefore: 1)), BaselineFailure.lostPackets);
    expect(second(row(1, calibrating: true)), BaselineFailure.calibrating);
    expect(second(row(1, valid: false)), BaselineFailure.markedInvalid);
    expect(second(row(1, eightFsr: false)), BaselineFailure.wrongInsole);
    expect(
      second(row(1, kpa: t.stepContactKpa / 8)),
      BaselineFailure.notLoaded,
    );
    final shake = t.walkingAccelG * 2;
    expect(second(row(1, accel: [0, 0, 1 + shake])), BaselineFailure.moved);
  });

  test('the first failure stays', () {
    final w = make()..add(row(0, calibrating: true));
    expect(w.add(row(1, valid: false)), isNull);
    expect(w.failure, BaselineFailure.calibrating);
    expect(w.end(), BaselineFailure.calibrating);
  });

  test('rows ending before the window is full: tooShort', () {
    final w = make();
    for (var i = 0; i < n ~/ 3; i++) {
      w.add(row(i));
    }
    expect(w.progress, closeTo(1 / 3, 0.01));
    expect(w.end(), BaselineFailure.tooShort);
    expect(w.values, isNull);
  });

  // User decision 2026-11-02: a board clock a little slow against the
  // phone puts 1499 samples in a 30 s trial 00.
  test('rows ending at most baselineToleranceSamples short still give a '
      'baseline; one fewer is tooShort', () {
    final lo = n - testPreprocess.baselineToleranceSamples;
    expect(lo, lessThan(n));
    FootBaselineWindow fed(int k) {
      final w = make();
      for (var i = 0; i < k; i++) {
        w.add(row(i));
      }
      return w;
    }

    final short = fed(lo);
    expect(short.complete, isFalse);
    expect(short.values, isNull, reason: 'not before the rows end');
    expect(short.end(), isNull);
    expect(short.rows, hasLength(lo));
    expect(short.values, hasLength(14));
    final tooShort = fed(lo - 1);
    expect(tooShort.end(), BaselineFailure.tooShort);
    expect(tooShort.values, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/gait/baseline_recorder.dart';
import 'package:smartinsole/gait/preprocess.dart';

import '../helpers/pump_app.dart';

/// The researcher's quiet-standing recording (S9): 30 s of sample time per
/// foot from the 50 Hz path, the per-channel median, and a named reason
/// for anything that would make it describe something else.
void main() {
  const period = 20.0;
  const perPacket = 8;
  final t = testThresholds;
  final duration = testPreprocess.baselineSeconds * 1000;
  // Standing: 25 kPa under each site (well above steps.contactKpa), still.
  final standKpa = List<double>.filled(8, 25);
  const still = [0.0, 0.0, 1.0];

  BaselineRecorder make() => BaselineRecorder(
    spec: testPreprocess,
    thresholds: t,
    insoleIds: const {FootSide.left: 'L-1', FootSide.right: 'R-1'},
  );

  /// Feeds both feet [ms] of packets from [fromMs]; [kpa] / [accel] per
  /// sample index, and per packet [missing] / [session].
  void feed(
    BaselineRecorder r, {
    double fromMs = 0,
    required double ms,
    List<double> Function(FootSide, int)? kpa,
    List<double> Function(int)? accel,
    int Function(int)? missing,
    int session = 1,
    bool calibrating = false,
    Set<FootSide> sides = const {FootSide.left, FootSide.right},
  }) {
    final n = (ms / period).round();
    for (var p = 0; p * perPacket < n; p++) {
      for (final side in sides) {
        r.add(
          FootBatch(
            side: side,
            session: session,
            seq: p,
            missingBefore: missing?.call(p) ?? 0,
            receivedAt: DateTime(2026, 11, 1),
            saturated: false,
            calibrating: calibrating,
            samples: [
              for (var k = 0; k < perPacket; k++)
                FootSample(
                  unixMs: fromMs + (p * perPacket + k) * period,
                  deviceMs: 0,
                  fsrAdc: List.filled(8, 0),
                  fsrKpa:
                      kpa?.call(side, p * perPacket + k) ??
                      [
                        for (var c = 0; c < 8; c++)
                          standKpa[c] + (p * perPacket + k) % 3,
                      ],
                  accelG: accel?.call(p * perPacket + k) ?? still,
                  gyroDps: [0, (p * perPacket + k) % 2 * 0.5, 0],
                ),
            ],
          ),
        );
      }
    }
  }

  test('30 s of sample time per foot, then the per-channel median', () {
    final r = make();
    feed(r, ms: duration - 1000);
    expect(r.done, isFalse);
    // Whole packets: the last of 182 ends at 29.1 s.
    expect(r.progress(FootSide.left), closeTo(0.97, 0.001));
    feed(r, fromMs: 182 * perPacket * period, ms: 2000);
    expect(r.done, isTrue);
    expect(r.failure, isNull);
    final out = r.result(1234)!;
    expect(out.map((b) => b.side), FootSide.values);
    expect(out.map((b) => b.insoleId), ['L-1', 'R-1']);
    final left = out.first;
    expect(left.sampleCount, duration ~/ period);
    expect(left.recordedAtMs, 1234);
    expect(left.values, hasLength(14));
    // kPa cycle 25, 26, 27: median 26; accel as given; gyro y 0/0.5 → the
    // mean of the two middle values of an even count.
    expect(left.values.sublist(0, 8), List.filled(8, 26.0));
    expect(left.values.sublist(8, 11), still);
    expect(left.values[12], 0.25);
  });

  test('a lost packet fails it, naming the foot', () {
    final r = make();
    feed(r, ms: 2000, missing: (p) => p == 5 ? 1 : 0);
    expect(r.failure, BaselineFailure.lostPackets);
    expect(r.failedSide, FootSide.left);
    feed(r, fromMs: 2000, ms: duration.toDouble());
    expect(r.done, isFalse);
    expect(r.result(0), isNull);
  });

  test('a reconnect (new session) fails it', () {
    final r = make();
    feed(r, ms: 2000);
    feed(r, fromMs: 2000, ms: 2000, session: 2);
    expect(r.failure, BaselineFailure.reconnected);
  });

  test('a TARE running fails it', () {
    final r = make();
    feed(r, ms: 1000, calibrating: true);
    expect(r.failure, BaselineFailure.calibrating);
  });

  test('moving (the walking gate turns on) fails it', () {
    final r = make();
    final shake = t.walkingAccelG * 2;
    feed(r, ms: 5000, accel: (i) => [0, 0, 1 + (i.isEven ? shake : -shake)]);
    expect(r.failure, BaselineFailure.moved);
  });

  test('a foot not loaded above steps.contactKpa fails it', () {
    final r = make();
    final light = t.stepContactKpa / 8;
    feed(
      r,
      ms: 1000,
      kpa: (side, i) =>
          side == FootSide.right && i > 20 ? List.filled(8, light) : standKpa,
    );
    expect(r.failure, BaselineFailure.notLoaded);
    expect(r.failedSide, FootSide.right);
  });

  test('only one foot streaming: never done', () {
    final r = make();
    feed(r, ms: duration * 2.0, sides: {FootSide.left});
    expect(r.progress(FootSide.left), 1);
    expect(r.progress(FootSide.right), 0);
    expect(r.done, isFalse);
  });

  test('the first failure is kept', () {
    final r = make()
      ..fail(BaselineFailure.stopped)
      ..fail(BaselineFailure.moved, FootSide.left);
    expect(r.failure, BaselineFailure.stopped);
    expect(r.failedSide, isNull);
  });

  test('the median is the training script\'s (preprocess vectors)', () {
    expect(
      footBaseline([
        [1, 5],
        [3, -1],
      ]),
      [2.0, 2.0],
    );
  });
}

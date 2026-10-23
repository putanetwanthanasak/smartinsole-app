import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/device/rolling_peaks.dart';

FootBatch batch(int session, List<(double, List<double>)> samples) => FootBatch(
  side: FootSide.left,
  session: session,
  seq: 0,
  missingBefore: 0,
  receivedAt: DateTime(2026),
  saturated: false,
  calibrating: false,
  samples: [
    for (final (t, kpa) in samples)
      FootSample(
        unixMs: t,
        deviceMs: t.toInt(),
        fsrAdc: List.filled(kpa.length, 0),
        fsrKpa: kpa,
        accelG: const [0, 0, 1],
        gyroDps: const [0, 0, 0],
      ),
  ],
);

void main() {
  test('peak per channel over the window, ending at the newest sample', () {
    final p = RollingPeaks(windowMs: 2000);
    expect(p.channelPeaks(), isNull);
    p.add(
      batch(1, [
        (0, [10, 90]),
        (20, [50, 5]),
      ]),
    );
    expect(p.channelPeaks(), [50, 90]);
    expect(p.footPeak(), 90);
    // 2.5 s later the first bucket has left the window.
    p.add(
      batch(1, [
        (2500, [20, 30]),
      ]),
    );
    expect(p.channelPeaks(), [20, 30]);
  });

  test('a new session starts an empty window', () {
    final p = RollingPeaks(windowMs: 2000)
      ..add(
        batch(1, [
          (0, [99, 99]),
        ]),
      );
    p.add(
      batch(2, [
        (100, [1, 2]),
      ]),
    );
    expect(p.channelPeaks(), [1, 2]);
  });

  test('every sample of a 50 Hz stream counts, not one in five', () {
    final p = RollingPeaks(windowMs: 2000);
    // One 20 ms spike between the 100 ms display ticks.
    p.add(
      batch(1, [
        for (var i = 0; i < 50; i++) (i * 20.0, [i == 7 ? 180.0 : 10.0]),
      ]),
    );
    expect(p.footPeak(), 180);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/rolling_load.dart';

import 'rolling_peaks_test.dart' show batch;

void main() {
  test('mean summed load per sample over the window', () {
    final r = RollingLoad(windowMs: 10000);
    expect(r.meanLoad(), isNull);
    r.add(
      batch(1, [
        (0, [10, 20]),
        (20, [30, 40]),
      ]),
    );
    expect(r.meanLoad(), 50); // (30 + 70) / 2
    // 10.5 s later the first samples have left the window.
    r.add(
      batch(1, [
        (10500, [5, 5]),
      ]),
    );
    expect(r.meanLoad(), 10);
  });

  test('lost samples do not lower a foot\'s load', () {
    final full = RollingLoad(windowMs: 10000);
    final lossy = RollingLoad(windowMs: 10000);
    final samples = [
      for (var i = 0; i < 100; i++) (i * 20.0, [40.0, 60.0]),
    ];
    full.add(batch(1, samples));
    lossy.add(batch(1, [for (var i = 0; i < 100; i += 3) samples[i]]));
    expect(lossy.meanLoad(), full.meanLoad());
  });

  test('a new session starts an empty window', () {
    final r = RollingLoad(windowMs: 10000)
      ..add(
        batch(1, [
          (0, [100, 100]),
        ]),
      )
      ..add(
        batch(2, [
          (20, [1, 1]),
        ]),
      );
    expect(r.meanLoad(), 2);
  });
}

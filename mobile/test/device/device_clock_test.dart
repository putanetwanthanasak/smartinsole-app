import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_clock.dart';

/// A board streaming 8-sample packets at 6.25 Hz to a phone. Phone unix
/// time `p` and device time `d` are related by `d = (p − bootUnix)·(1 +
/// ppm·1e-6)`, wrapped to uint32. Each packet arrives `latency()` ms after
/// its last sample is taken.
class Link {
  Link({
    required this.bootUnix,
    this.ppm = 0,
    this.firstDeviceMs = 100000,
    required this.latency,
  });

  final double bootUnix;
  final double ppm;
  final int firstDeviceMs;
  final double Function() latency;

  int packet = 0;

  /// Added to every arrival from now on (a wall-clock step on the phone).
  double wallStep = 0;

  int deviceMsOf(int k) => firstDeviceMs + k * 20;

  /// True phone time when device time [ext] (unwrapped) was sampled.
  double truthOf(int ext) => bootUnix + ext / (1 + ppm * 1e-6);

  /// The next packet: wrapped device times, and its arrival.
  (List<int>, DateTime, List<double>) next() {
    final ext = [for (var i = 0; i < 8; i++) deviceMsOf(packet * 8 + i)];
    packet++;
    final arrive = truthOf(ext.last) + latency() + wallStep;
    return (
      [for (final e in ext) e & 0xFFFFFFFF],
      DateTime.fromMicrosecondsSinceEpoch((arrive * 1000).round()),
      [for (final e in ext) truthOf(e)],
    );
  }
}

const bootUnix = 1792605700000.0;

/// Android-like latency: at least 2 ms, up to one 11.25 ms connection
/// interval, and now and then a packet held back for 40–200 ms.
double Function() androidLatency(int seed) {
  final r = math.Random(seed);
  return () {
    var l = 2 + r.nextDouble() * 11.25;
    if (r.nextInt(50) == 0) l += 40 + r.nextDouble() * 160;
    return l;
  };
}

/// Runs [packets] packets; returns per-sample (unix, truth).
List<(double, double)> run(DeviceClock clock, Link link, int packets) {
  final out = <(double, double)>[];
  for (var k = 0; k < packets; k++) {
    final (dev, at, truth) = link.next();
    final unix = clock.mapPacket(dev, at);
    for (var i = 0; i < unix.length; i++) {
      out.add((unix[i], truth[i]));
    }
  }
  return out;
}

void expectSpacing(List<(double, double)> s, {double slew = 0.25}) {
  for (var i = 1; i < s.length; i++) {
    final step = s[i].$1 - s[i - 1].$1;
    expect(
      step,
      inInclusiveRange(20 - slew - 1e-9, 20 + slew + 1e-9),
      reason: 'step $i',
    );
  }
}

void main() {
  const tenMinutes = 3750; // packets

  test('converges to the least latency and stays there', () {
    final clock = DeviceClock();
    final link = Link(bootUnix: bootUnix, latency: androidLatency(1));
    final s = run(clock, link, tenMinutes);
    // After 10 s every sample's error is between 0 and a few ms: the least
    // latency (2 ms) plus how close to it the window's best packet came.
    for (final (unix, truth) in s.skip(500)) {
      expect(unix - truth, inInclusiveRange(1.5, 4));
    }
    expect(clock.clamps, 0);
  });

  test('never goes backwards and never steps (10 min, random jitter)', () {
    for (final seed in [2, 3, 4, 5]) {
      final clock = DeviceClock();
      final s = run(
        clock,
        Link(bootUnix: bootUnix, latency: androidLatency(seed)),
        tenMinutes,
      );
      expectSpacing(s);
      expect(clock.clamps, 0);
    }
  });

  test('a late first packet is corrected by slewing, not by a step', () {
    var first = true;
    final clock = DeviceClock();
    final link = Link(
      bootUnix: bootUnix,
      latency: () {
        if (first) {
          first = false;
          return 120; // the first notification was held back
        }
        return 5;
      },
    );
    final s = run(clock, link, 100);
    expectSpacing(s);
    expect(s.first.$1 - s.first.$2, closeTo(120, 1e-6));
    // 115 ms at 0.25 ms per sample: settled after 460 samples.
    expect(s.last.$1 - s.last.$2, closeTo(5, 1e-6));
  });

  test('tracks 40 ppm crystal drift', () {
    for (final ppm in [40.0, -40.0]) {
      final clock = DeviceClock();
      final link = Link(
        bootUnix: bootUnix,
        ppm: ppm,
        latency: androidLatency(6),
      );
      final s = run(clock, link, tenMinutes * 3); // 30 minutes
      for (final (unix, truth) in s.skip(500)) {
        // Least latency (2 ms) ± drift across the 30 s window (1.2 ms).
        expect(unix - truth, inInclusiveRange(0.5, 5), reason: 'ppm $ppm');
      }
      expectSpacing(s);
    }
  });

  test('deviceMs uint32 wrap is forward, not a jump', () {
    final clock = DeviceClock();
    final link = Link(
      bootUnix: bootUnix,
      firstDeviceMs: 0xFFFFFFFF - 5000,
      latency: androidLatency(7),
    );
    final s = run(clock, link, 200); // crosses the wrap after ~31 packets
    expectSpacing(s);
    for (final (unix, truth) in s.skip(100)) {
      expect(unix - truth, inInclusiveRange(0, 15));
    }
  });

  test('a phone wall-clock step of ±500 ms is absorbed without a step', () {
    for (final step in [-500.0, 500.0]) {
      final clock = DeviceClock();
      final link = Link(bootUnix: bootUnix, latency: androidLatency(8));
      final before = run(clock, link, 300);
      link.wallStep = step;
      final after = run(clock, link, 3000);
      expectSpacing([...before, ...after]);
      expect(clock.clamps, 0);
      // It ends up following the phone's new clock.
      expect(after.last.$1 - after.last.$2 - step, inInclusiveRange(1, 5));
    }
  });

  test('BACKLOG 28: packets arriving in bursts give no 160 ms steps', () {
    // Every 10th packet is held back one packet period and delivered with
    // the next one: the pattern that shifts the web app's resync by 160 ms.
    var n = 0;
    final clock = DeviceClock();
    final link = Link(
      bootUnix: bootUnix,
      latency: () => n++ % 10 == 0 ? 165 : 5,
    );
    final s = run(clock, link, tenMinutes);
    expectSpacing(s);
    for (final (unix, truth) in s.skip(800)) {
      expect(unix - truth, closeTo(5, 0.01));
    }
  });

  test('unixOf maps another device time on the same clock', () {
    final clock = DeviceClock();
    expect(clock.unixOf(5000), isNull);
    final link = Link(bootUnix: bootUnix, latency: () => 5);
    run(clock, link, 10);
    final lastDevice = link.deviceMsOf(79);
    expect(
      clock.unixOf(lastDevice - 30000),
      closeTo(link.truthOf(lastDevice - 30000) + 5, 1e-6),
    );
  });
}

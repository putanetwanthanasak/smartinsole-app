import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/device/model_channels.dart';

FootSample sample(double base, {int n = 8, double unixMs = 0}) => FootSample(
  unixMs: unixMs,
  deviceMs: 0,
  fsrAdc: List.filled(n, 0),
  fsrKpa: [for (var i = 0; i < n; i++) base + i],
  accelG: [base + 10, base + 11, base + 12],
  gyroDps: [base + 20, base + 21, base + 22],
);

void main() {
  test('channel names match shared/model_input.json exactly', () {
    final json = jsonDecode(
      File('../shared/model_input.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(modelChannelNames, json['channels']);
    expect(json['version'], 2, reason: 'v2: 8 FSR per foot (contract v1.6)');
    expect(json['fsrChannelsPerFoot'], modelFsrCount);
    expect(modelFsrCount, 8);
    expect(modelChannelCount, 28);
    expect(json['windowSamples'], 100);
    expect(json['strideSamples'], 50);
    expect(json['sampleRateHz'], 50);
    expect(json['units'], {'fsr': 'kPa', 'accel': 'g', 'gyro': 'deg/s'});
    final pairing = json['pairing']! as Map<String, Object?>;
    expect(pairing['timeBase'], 'L');
    expect((pairing['toleranceMs']! as num).toDouble(), pairToleranceMs);
  });

  test('a row is FSR 0-7, accel xyz, gyro xyz; left then right (§7.1)', () {
    final row = modelRow(sample(100), sample(200))!;
    expect(row, hasLength(modelChannelCount));
    expect(row.sublist(0, 8), [100, 101, 102, 103, 104, 105, 106, 107]);
    expect(row.sublist(8, 11), [110, 111, 112]);
    expect(row.sublist(11, 14), [120, 121, 122]);
    expect(row.sublist(14, 22), [200, 201, 202, 203, 204, 205, 206, 207]);
    expect(row.sublist(22, 25), [210, 211, 212]);
    expect(row.sublist(25, 28), [220, 221, 222]);
    expect(modelChannelNames[modelChannelOffset(FootSide.right)], 'R_fsr0_kpa');
    expect(modelChannelNames[11], 'L_gyro_x_dps');
  });

  test('a foot without exactly 8 FSR channels has no model input (a '
      '6-FSR foot is never padded)', () {
    expect(footModelChannels(sample(0, n: 6)), isNull);
    expect(footModelChannels(sample(0, n: 9)), isNull);
    expect(modelRow(sample(0), sample(0, n: 6)), isNull);
  });

  group('pairFeet', () {
    List<FootSample> at(List<double> t) => [
      for (final u in t) sample(u, unixMs: u),
    ];
    List<(double, double)> times(List<(FootSample, FootSample)> p) => [
      for (final (l, r) in p) (l.unixMs, r.unixMs),
    ];

    test('nearest right sample within 10 ms, left as the time base', () {
      final p = pairFeet(at([0, 20, 40, 60]), at([7, 26, 52, 75]));
      // 40 has nothing within 10 ms (26 and 52 are 14 and 12 away); 60
      // takes 52 (8 ms), not 75 (15 ms).
      expect(times(p), [(0.0, 7.0), (20.0, 26.0), (60.0, 52.0)]);
    });

    test('±10 ms is inclusive; a tie goes to the earlier sample', () {
      expect(times(pairFeet(at([100]), at([90, 110]))), [(100.0, 90.0)]);
      expect(times(pairFeet(at([100]), at([110.5]))), isEmpty);
    });

    test('each right sample is used once, in order', () {
      // 10 and 30 are both 10 ms from 20; 10 takes it first.
      expect(times(pairFeet(at([10, 30]), at([20]))), [(10.0, 20.0)]);
    });

    test('a gap in either foot gives no row there', () {
      final p = pairFeet(at([0, 20, 40, 60, 80]), at([3, 23, 83]));
      expect(times(p), [(0.0, 3.0), (20.0, 23.0), (80.0, 83.0)]);
    });
  });
}

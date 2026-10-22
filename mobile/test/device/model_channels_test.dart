import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/device/model_channels.dart';

FootSample sample(double base, {int n = 6}) => FootSample(
  unixMs: 0,
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
    expect(json['fsrChannelsPerFoot'], modelFsrCount);
    expect(json['windowSamples'], 100);
    expect(json['strideSamples'], 50);
    expect(json['sampleRateHz'], 50);
    expect(json['units'], {'fsr': 'kPa', 'accel': 'g', 'gyro': 'deg/s'});
  });

  test('a row is FSR 0-5, accel xyz, gyro xyz; left then right (§7.1)', () {
    final row = modelRow(sample(100), sample(200))!;
    expect(row, hasLength(modelChannelCount));
    expect(row.sublist(0, 6), [100, 101, 102, 103, 104, 105]);
    expect(row.sublist(6, 9), [110, 111, 112]);
    expect(row.sublist(9, 12), [120, 121, 122]);
    expect(row.sublist(12, 18), [200, 201, 202, 203, 204, 205]);
    expect(row.sublist(18, 21), [210, 211, 212]);
    expect(row.sublist(21, 24), [220, 221, 222]);
    expect(modelChannelNames[modelChannelOffset(FootSide.right)], 'R_fsr0_kpa');
    expect(modelChannelNames[9], 'L_gyro_x_dps');
  });

  test('a foot without exactly 6 FSR channels has no model input', () {
    expect(footModelChannels(sample(0, n: 8)), isNull);
    expect(modelRow(sample(0), sample(0, n: 4)), isNull);
  });
}

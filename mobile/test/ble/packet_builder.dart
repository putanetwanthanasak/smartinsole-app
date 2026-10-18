import 'dart:typed_data';

import 'package:smartinsole/ble/ble_protocol.dart';

/// One sample to encode: N FSR values, accel x/y/z, gyro x/y/z.
typedef SampleSpec = ({List<int> fsr, List<int> accel, List<int> gyro});

/// Builds a Sensor Stream packet with `fsr.length` channels per sample.
/// [count] defaults to the number of samples.
Uint8List buildSensorPacket({
  required int seq,
  required int t0Ms,
  required List<SampleSpec> samples,
  int flags = 0,
  int? count,
}) {
  final n = samples.isEmpty ? 0 : samples.first.fsr.length;
  final block = SensorLayout.sampleBytes(n);
  final data = ByteData(SensorLayout.headerBytes + samples.length * block)
    ..setUint16(0, seq, Endian.little)
    ..setUint32(2, t0Ms, Endian.little)
    ..setUint8(6, count ?? samples.length)
    ..setUint8(7, flags);
  for (var i = 0; i < samples.length; i++) {
    final base = SensorLayout.headerBytes + i * block;
    final s = samples[i];
    for (var ch = 0; ch < n; ch++) {
      data.setUint16(base + ch * 2, s.fsr[ch], Endian.little);
    }
    for (var k = 0; k < 3; k++) {
      data.setInt16(base + 2 * n + k * 2, s.accel[k], Endian.little);
      data.setInt16(base + 2 * n + 6 + k * 2, s.gyro[k], Endian.little);
    }
  }
  return data.buffer.asUint8List();
}

/// [count] distinct samples with [n] channels each.
List<SampleSpec> sampleSpecs(int n, int count) => [
  for (var i = 0; i < count; i++)
    (
      fsr: [for (var ch = 0; ch < n; ch++) (i * 409 + ch * 97 + 5) % 4096],
      accel: [i * 10 - 40, -i * 7, 4096 - i],
      gyro: [i, -i * 3, i * 1000 - 3000],
    ),
];

/// A calibration blob with [n] channels, as JSON-ready map.
Map<String, Object?> calibrationBlob(int n) => {
  'device_id': 'TEST-N$n',
  'r_pulldown_ohm': 10000,
  'sensor_area_m2': 0.000113,
  'channels': [
    for (var i = 0; i < n; i++)
      {'index': i, 'a': 1.23e5, 'b': -1.05, 'offset_adc': 12},
  ],
};

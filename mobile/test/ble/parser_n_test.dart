import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/fsr_conversion.dart';
import 'package:smartinsole/ble/packet_parser.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

import 'packet_builder.dart';

void main() {
  test('N = 6 with 8 samples is the contract 200-byte packet', () {
    final bytes = buildSensorPacket(
      seq: 1,
      t0Ms: 0,
      samples: sampleSpecs(6, 8),
    );
    expect(bytes.length, 200);
  });

  for (final n in [4, 6, 8]) {
    group('N = $n', () {
      final cal = (parseCalibration(
        jsonEncode(calibrationBlob(n)),
      ) as Parsed<Calibration>).value;

      test('sample block is 2N + 12 bytes', () {
        expect(SensorLayout.sampleBytes(n), 2 * n + 12);
        final bytes = buildSensorPacket(
          seq: 1,
          t0Ms: 0,
          samples: sampleSpecs(n, 8),
        );
        expect(bytes.length, 8 + 8 * (2 * n + 12));
      });

      test('round trip: every value comes back', () {
        final specs = sampleSpecs(n, 8);
        final bytes = buildSensorPacket(
          seq: 4242,
          t0Ms: 123456,
          samples: specs,
          flags: SensorLayout.flagSaturated,
        );
        final result = parseSensorPacket(bytes, fsrCount: cal.fsrCount);
        final p = (result as Parsed<SensorPacket>).value;
        expect(p.header.seq, 4242);
        expect(p.header.saturated, isTrue);
        expect(p.header.calibrating, isFalse);
        expect(p.samples.length, 8);
        for (var i = 0; i < 8; i++) {
          expect(p.samples[i].deviceMs, 123456 + i * 20);
          expect(p.samples[i].fsrAdc, specs[i].fsr);
          expect(p.samples[i].accelRaw, specs[i].accel);
          expect(p.samples[i].gyroRaw, specs[i].gyro);
          expect(sampleKpa(p.samples[i], cal), hasLength(n));
        }
      });

      test('MTU fallback: 4 samples', () {
        final bytes = buildSensorPacket(
          seq: 2,
          t0Ms: 0,
          samples: sampleSpecs(n, 4),
        );
        final p = (parseSensorPacket(
          bytes,
          fsrCount: n,
        ) as Parsed<SensorPacket>).value;
        expect(p.samples.length, 4);
      });
    });
  }

  group('wrong FSR count is never parsed silently', () {
    for (final (built, parsedAs) in [(6, 8), (4, 6), (8, 6), (6, 4), (8, 4)]) {
      test('N = $built packet parsed as N = $parsedAs', () {
        final bytes = buildSensorPacket(
          seq: 3,
          t0Ms: 0,
          samples: sampleSpecs(built, 8),
        );
        final result = parseSensorPacket(bytes, fsrCount: parsedAs);
        expect(result, isA<Rejected<SensorPacket>>());
        final reason = (result as Rejected<SensorPacket>).reason;
        expect(
          reason,
          parsedAs > built
              ? RejectReason.truncated
              : RejectReason.lengthMismatch,
        );
        expect(result.expectedBytes, 8 + 8 * (2 * parsedAs + 12));
        expect(result.actualBytes, bytes.length);
      });
    }
  });
}

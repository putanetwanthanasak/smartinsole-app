import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/packet_parser.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

import 'packet_builder.dart';

/// Every [RejectReason] has a test here, so S3A/S4 can rely on the reason
/// they count and log.
void main() {
  final tested = <RejectReason>{};

  void expectReason<T>(ParseResult<T> result, RejectReason reason) {
    expect(result, isA<Rejected<T>>(), reason: '$result');
    final rejected = result as Rejected<T>;
    expect(rejected.reason, reason);
    expect(rejected.detail, isNotEmpty);
    tested.add(reason);
  }

  Uint8List status({int side = 0, int state = 1}) =>
      Uint8List.fromList([87, 0x93, 0x0f, side, 1, 4, state, 0]);
  Uint8List temp({int quality = 0}) => Uint8List.fromList([
    1,
    0,
    0x30,
    0x75,
    0,
    0,
    0x6c,
    0x0c,
    0xd2,
    0x0b,
    quality,
    0,
  ]);
  String blob(void Function(Map<String, dynamic> b) edit) {
    final b =
        jsonDecode(jsonEncode(calibrationBlob(6))) as Map<String, dynamic>;
    edit(b);
    return jsonEncode(b);
  }

  List<Map<String, dynamic>> channels(Map<String, dynamic> b) =>
      (b['channels'] as List).cast<Map<String, dynamic>>();

  group('sensor', () {
    test('tooShort: fewer bytes than the header', () {
      final r = parseSensorPacket(Uint8List(7), fsrCount: 6);
      expectReason(r, RejectReason.tooShort);
      final rejected = r as Rejected;
      expect(rejected.expectedBytes, 8);
      expect(rejected.actualBytes, 7);
    });

    test('truncated: count needs more bytes than arrived', () {
      final bytes = buildSensorPacket(
        seq: 1,
        t0Ms: 0,
        samples: sampleSpecs(6, 8),
      );
      final r = parseSensorPacket(bytes.sublist(0, 104), fsrCount: 6);
      expectReason(r, RejectReason.truncated);
      final rejected = r as Rejected;
      expect(rejected.expectedBytes, 200);
      expect(rejected.actualBytes, 104);
    });

    test('lengthMismatch: more bytes than count accounts for', () {
      final bytes = buildSensorPacket(
        seq: 1,
        t0Ms: 0,
        samples: sampleSpecs(6, 8),
      );
      final longer = Uint8List(bytes.length + 2)..setAll(0, bytes);
      expectReason(
        parseSensorPacket(longer, fsrCount: 6),
        RejectReason.lengthMismatch,
      );
    });
  });

  group('status', () {
    test('valid bytes parse', () {
      final p =
          (parseStatusPacket(status(side: 1)) as Parsed<StatusPacket>).value;
      expect(p.footSide, FootSide.right);
      expect(p.batteryMv, 0x0f93);
    });

    test('tooShort', () {
      expectReason(
        parseStatusPacket(status().sublist(0, 7)),
        RejectReason.tooShort,
      );
    });

    for (final side in [2, 3, 255]) {
      test('invalidFootSide: foot_side $side is not masked to a foot', () {
        expectReason(
          parseStatusPacket(status(side: side)),
          RejectReason.invalidFootSide,
        );
      });
    }

    for (final state in [3, 4, 255]) {
      test('invalidState: state $state', () {
        expectReason(
          parseStatusPacket(status(state: state)),
          RejectReason.invalidState,
        );
      });
    }
  });

  group('temperature', () {
    test('tooShort', () {
      expectReason(
        parseTempPacket(temp().sublist(0, 11)),
        RejectReason.tooShort,
      );
    });

    for (final quality in [3, 4, 255]) {
      test('invalidQuality: quality $quality', () {
        expectReason(
          parseTempPacket(temp(quality: quality)),
          RejectReason.invalidQuality,
        );
      });
    }
  });

  group('calibration', () {
    test('calibrationNotJson', () {
      expectReason(parseCalibration('{'), RejectReason.calibrationNotJson);
    });

    test('calibrationNotObject: a JSON array', () {
      expectReason(parseCalibration('[]'), RejectReason.calibrationNotObject);
    });

    test('calibrationMissingField', () {
      expectReason(
        parseCalibration(blob((b) => b.remove('sensor_area_m2'))),
        RejectReason.calibrationMissingField,
      );
    });

    test('calibrationNoChannels', () {
      expectReason(
        parseCalibration(blob((b) => b['channels'] = [])),
        RejectReason.calibrationNoChannels,
      );
    });

    test('calibrationInvalidValue: zero area', () {
      expectReason(
        parseCalibration(blob((b) => b['sensor_area_m2'] = 0)),
        RejectReason.calibrationInvalidValue,
      );
    });

    test('calibrationInvalidValue: negative pull-down', () {
      expectReason(
        parseCalibration(blob((b) => b['r_pulldown_ohm'] = -10000)),
        RejectReason.calibrationInvalidValue,
      );
    });

    test('calibrationBadChannelIndex: gap', () {
      expectReason(
        parseCalibration(blob((b) => channels(b)[5]['index'] = 6)),
        RejectReason.calibrationBadChannelIndex,
      );
    });

    test('calibrationBadChannelIndex: duplicate', () {
      expectReason(
        parseCalibration(blob((b) => channels(b)[5]['index'] = 4)),
        RejectReason.calibrationBadChannelIndex,
      );
    });

    test('calibrationBadChannelIndex: not an integer', () {
      expectReason(
        parseCalibration(blob((b) => channels(b)[2]['index'] = 2.5)),
        RejectReason.calibrationBadChannelIndex,
      );
    });

    test('channels out of order are stored sorted by index', () {
      final text = blob((b) {
        final list = channels(b);
        for (var i = 0; i < list.length; i++) {
          list[i]['offset_adc'] = i * 10;
        }
        b['channels'] = list.reversed.toList();
      });
      final cal = (parseCalibration(text) as Parsed<Calibration>).value;
      expect([for (final c in cal.channels) c.index], [0, 1, 2, 3, 4, 5]);
      expect(
        [for (final c in cal.channels) c.offsetAdc],
        [0, 10, 20, 30, 40, 50],
      );
    });

    test('N comes from the blob, not a fixed 6', () {
      for (final n in [1, 4, 8]) {
        final cal = (parseCalibration(
          jsonEncode(calibrationBlob(n)),
        ) as Parsed<Calibration>).value;
        expect(cal.fsrCount, n);
      }
    });
  });

  // Runs last (tests run in declaration order).
  test('every RejectReason has a test above', () {
    expect(tested, RejectReason.values.toSet());
  });
}

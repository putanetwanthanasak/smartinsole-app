import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/fsr_conversion.dart';
import 'package:smartinsole/ble/packet_parser.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

/// Checks the Dart parser against `shared/test_vectors/`, which hold the web
/// app's TS parser output (see that folder's README). Integers must match
/// exactly; doubles to 3 decimal places.
const _tolerance = 0.0005;

final _vectorDir = Directory('../shared/test_vectors');

/// Largest |Dart − TS| seen per quantity, printed at the end for the report.
final _maxDiff = <String, double>{};

typedef _Json = Map<String, dynamic>;

void main() {
  final files = _vectorDir.existsSync()
      ? (_vectorDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  final handlers = <String, void Function(_Json file, _Json c)>{
    'sensor.json': _checkSensor,
    'sensor_n4.json': _checkSensor,
    'sensor_n8.json': _checkSensor,
    'temperature.json': _checkTempV1,
    'temperature_v2.json': _checkTemp,
    'status.json': _checkStatus,
    'calibration.json': _checkCalibration,
  };

  test('every vector file is known and has cases', () {
    expect(files, isNotEmpty, reason: 'no vectors in ${_vectorDir.path}');
    final names = files.map((f) => f.uri.pathSegments.last).toSet();
    expect(names, handlers.keys.toSet());
    for (final f in files) {
      final cases = (jsonDecode(f.readAsStringSync()) as _Json)['cases'];
      expect(
        cases,
        isA<List<dynamic>>().having((l) => l.length, 'length', greaterThan(0)),
      );
    }
  });

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final handler = handlers[name];
    if (handler == null) continue;
    final file = jsonDecode(f.readAsStringSync()) as _Json;
    group(name, () {
      for (final c in (file['cases'] as List).cast<_Json>()) {
        test(c['name'] as String, () => handler(file, c));
      }
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('max |Dart − TS|: $_maxDiff');
  });
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void _close(String quantity, double actual, num expected, String where) {
  final diff = (actual - expected).abs();
  _maxDiff[quantity] = diff > (_maxDiff[quantity] ?? 0)
      ? diff
      : (_maxDiff[quantity] ?? 0);
  expect(diff, lessThan(_tolerance), reason: '$where: $actual vs $expected');
}

void _closeAll(String quantity, List<double> actual, List expected, String w) {
  expect(actual.length, expected.length, reason: w);
  for (var i = 0; i < actual.length; i++) {
    _close(quantity, actual[i], expected[i] as num, '$w[$i]');
  }
}

void _expectRejected<T>(ParseResult<T> r, _Json expected, String reason) {
  expect(r, isA<Rejected<T>>());
  final rej = r as Rejected<T>;
  expect(rej.reason.name, reason);
  if (expected.containsKey('expected_bytes')) {
    expect(rej.expectedBytes, expected['expected_bytes']);
    expect(rej.actualBytes, expected['actual_bytes']);
  }
}

void _checkSensor(_Json file, _Json c) {
  final blob = (file['calibrations'] as _Json)[c['calibration']];
  final calResult = parseCalibration(jsonEncode(blob));
  expect(calResult, isA<Parsed<Calibration>>(), reason: '$calResult');
  final cal = (calResult as Parsed<Calibration>).value;
  expect(cal.fsrCount, c['fsr_count']);

  final result = parseSensorPacket(
    _hex(c['hex'] as String),
    fsrCount: cal.fsrCount,
  );
  final expected = c['expected'] as _Json;

  final dartRejected = c['dart_rejected'] as String?;
  if (dartRejected != null) {
    // TS accepted it; byte counts are the same either way.
    _expectRejected(result, expected, dartRejected);
    return;
  }
  final rejected = expected['rejected'] as String?;
  if (rejected != null) {
    _expectRejected(result, expected, rejected);
    return;
  }

  expect(result, isA<Parsed<SensorPacket>>(), reason: '$result');
  final p = (result as Parsed<SensorPacket>).value;
  final h = expected['header'] as _Json;
  expect(p.header.seq, h['seq']);
  expect(p.header.t0Ms, h['t0_ms']);
  expect(p.header.count, h['count']);
  expect(p.header.saturated, h['saturated']);
  expect(p.header.calibrating, h['calibrating']);
  expect(p.byteLength, expected['actual_bytes']);
  expect(p.byteLength, expected['expected_bytes']);

  final samples = (expected['samples'] as List).cast<_Json>();
  expect(p.samples.length, samples.length);
  for (var i = 0; i < samples.length; i++) {
    final s = p.samples[i];
    final e = samples[i];
    final where = '${c['name']} sample $i';
    expect(s.deviceMs, e['t_ms'], reason: where);
    expect(s.fsrAdc, e['fsr_adc'], reason: where);
    expect(s.accelRaw, e['accel_raw'], reason: where);
    expect(s.gyroRaw, e['gyro_raw'], reason: where);
    _closeAll(
      'adc_corrected',
      [
        for (var ch = 0; ch < cal.fsrCount; ch++)
          correctAdc(s.fsrAdc[ch], cal.channels[ch].offsetAdc),
      ],
      e['adc_corrected'] as List,
      '$where adc_corrected',
    );
    _closeAll('kpa', sampleKpa(s, cal), e['kpa'] as List, '$where kpa');
    _closeAll(
      'accel_g',
      s.accelRaw.map(accelRawToG).toList(),
      e['accel_g'] as List,
      '$where accel_g',
    );
    _closeAll(
      'gyro_dps',
      s.gyroRaw.map(gyroRawToDps).toList(),
      e['gyro_dps'] as List,
      '$where gyro_dps',
    );
  }
}

/// The v1 (12-byte) vectors stay as the record of the old format; since
/// DATA-CONTRACT v1.6 every one of them must be refused, never misread as
/// 8 sites.
void _checkTempV1(_Json file, _Json c) {
  final bytes = _hex(c['hex'] as String);
  final result = parseTempPacket(bytes);
  _expectRejected(result, {
    'expected_bytes': 32,
    'actual_bytes': bytes.length,
  }, 'tempLength');
}

void _checkTemp(_Json file, _Json c) {
  final result = parseTempPacket(_hex(c['hex'] as String));
  final e = c['expected'] as _Json;
  final rejected = e['rejected'] as String?;
  if (rejected != null) {
    _expectRejected(result, e, rejected);
    return;
  }
  expect(result, isA<Parsed<TempPacket>>(), reason: '$result');
  final p = (result as Parsed<TempPacket>).value;
  expect(p.seq, e['seq']);
  expect(p.tMs, e['t_ms']);
  expect(p.siteCount, e['count']);
  expect(p.quality.map((q) => q.index).toList(), e['quality']);
  final celsius = e['celsius'] as List;
  expect(p.celsius, hasLength(celsius.length));
  for (var i = 0; i < celsius.length; i++) {
    final label = '${c['name']} site $i';
    if (celsius[i] == null) {
      expect(p.celsius[i], isNull, reason: label);
    } else {
      expect(p.celsius[i], isNotNull, reason: label);
      _close('temp_c', p.celsius[i]!, celsius[i] as num, label);
    }
  }
}

void _checkStatus(_Json file, _Json c) {
  final result = parseStatusPacket(_hex(c['hex'] as String));
  final e = c['expected'] as _Json;
  final rejected = e['rejected'] as String?;
  if (rejected != null) {
    _expectRejected(result, const {}, rejected);
    return;
  }
  expect(result, isA<Parsed<StatusPacket>>(), reason: '$result');
  final p = (result as Parsed<StatusPacket>).value;
  expect(p.batteryPct, e['battery_pct']);
  expect(p.batteryMv, e['battery_mv']);
  expect(p.footSide.index, e['foot_side']);
  expect(p.fwMajor, e['fw_major']);
  expect(p.fwMinor, e['fw_minor']);
  expect(p.state.index, e['state']);
  expect(p.errorCode, e['error_code']);
}

void _checkCalibration(_Json file, _Json c) {
  final result = parseCalibration(c['text'] as String);
  final e = c['expected'] as _Json;
  final rejected = e['rejected'] as String?;
  if (rejected != null) {
    _expectRejected(result, const {}, rejected);
    return;
  }
  expect(result, isA<Parsed<Calibration>>(), reason: '$result');
  final cal = (result as Parsed<Calibration>).value;
  expect(cal.deviceId, e['device_id']);
  expect(cal.rPulldownOhm, e['r_pulldown_ohm']);
  expect(cal.sensorAreaM2, e['sensor_area_m2']);
  final channels = (e['channels'] as List).cast<_Json>();
  expect(cal.channels.length, channels.length);
  for (var i = 0; i < channels.length; i++) {
    expect(cal.channels[i].index, channels[i]['index']);
    expect(cal.channels[i].a, channels[i]['a']);
    expect(cal.channels[i].b, channels[i]['b']);
    expect(cal.channels[i].offsetAdc, channels[i]['offset_adc']);
  }
}

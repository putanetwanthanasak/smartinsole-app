import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/packet_parser.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

/// DATA-CONTRACT Appendix C is the page the hardware team writes firmware
/// from. Its numbers and examples are written by hand, so this test holds
/// them to the code: every byte count, offset and channel count it states
/// must equal the parser's constants, every hex example must be the vector
/// case its caption names, and the parser must read each example as the
/// text says. (S11-1: the text once put the temperature quality bytes at
/// offset 16 instead of 20; firmware built from it would have passed every
/// check in the app with wrong temperatures.)
void main() {
  final contract = File('../docs/DATA-CONTRACT.md').readAsStringSync();
  final start = contract.indexOf('## Appendix C');
  final end = contract.indexOf('\n## ', start + 1);
  if (start < 0) throw StateError('DATA-CONTRACT.md has no Appendix C');
  final appendix = contract.substring(start, end < 0 ? null : end);
  // Statements wrap across lines and list indentation: compare on one line.
  final text = appendix.replaceAll(RegExp(r'\s+'), ' ');

  const n = SensorLayout.fsrCount;
  const sites = TempLayout.siteCount;
  final sample = SensorLayout.sampleBytes(n);
  final packet = SensorLayout.packetBytes(n, SensorLayout.samplesPerPacket);
  final fallback = SensorLayout.packetBytes(
    n,
    MtuLayout.fallbackSamplesPerPacket,
  );

  /// The numbers [pattern] captures in Appendix C; fails if it is gone.
  List<String> stated(String pattern) {
    final m = RegExp(pattern).firstMatch(text);
    expect(m, isNotNull, reason: 'Appendix C no longer states: $pattern');
    return [for (var i = 1; i <= m!.groupCount; i++) m.group(i)!];
  }

  int hex(String s) => int.parse(s, radix: 16);

  group('Appendix C numbers equal the parser constants', () {
    test('sensor stream', () {
      final s = stated(
        r'fsr uint16 × (\d+), accel int16 × 3, gyro int16 × 3\), '
        r'8 \+ 8 × (\d+) = (\d+)-byte packets',
      );
      expect(int.parse(s[0]), n);
      expect(int.parse(s[1]), sample);
      expect(int.parse(s[2]), packet);
      final mtu = stated(
        r'the app needs MTU (\d+); with 4 samples per packet, '
        r'(\d+) bytes, MTU (\d+)',
      );
      expect(int.parse(mtu[0]), packet + MtuLayout.attOverhead);
      expect(int.parse(mtu[1]), fallback);
      expect(int.parse(mtu[2]), MtuLayout.minUsableMtu(n));
      final s0 = stated(
        r'Sample 0 \(bytes (\d+)–(\d+)\).*?sample 1 starts at byte (\d+)',
      );
      expect(int.parse(s0[0]), SensorLayout.headerBytes);
      expect(int.parse(s0[1]), SensorLayout.headerBytes + sample - 1);
      expect(int.parse(s0[2]), SensorLayout.headerBytes + sample);
    });

    test('temperature v2', () {
      expect(text, contains('`8 + 3 × count` bytes'));
      expect(TempLayout.bytesFor(sites), TempLayout.packetBytes);
      final t = stated(r'with count (\d+): \*\*(\d+) bytes\*\*');
      expect(int.parse(t[0]), sites);
      expect(int.parse(t[1]), TempLayout.packetBytes);
      expect(int.parse(stated(r'temp int16 × (\d+)')[0]), sites);
      expect(int.parse(stated(r'quality uint8 × (\d+)')[0]), sites);
      final q = stated(
        r'quality bytes start at offset `8 \+ 2 × count` = (\d+) '
        r'\(0x([0-9a-f]+)\)',
      );
      expect(int.parse(q[0]), TempLayout.qualityOffset);
      expect(hex(q[1]), TempLayout.qualityOffset);
      final range = stated(
        r'quality per site 0–\d+ \[[^\]]*\] \(bytes 0x([0-9a-f]+)–0x([0-9a-f]+)\)',
      );
      expect(hex(range[0]), TempLayout.qualityOffset);
      expect(hex(range[1]), TempLayout.packetBytes - 1);
    });

    test('calibration and the reject table', () {
      final c = stated(r'lists exactly (\d+) entries, indexes 0–(\d+)');
      expect(int.parse(c[0]), n);
      expect(int.parse(c[1]), n - 1);
      expect(int.parse(stated(r'a channel count other than (\d+)')[0]), n);
      expect(int.parse(stated(r'`N \d+ \(needs (\d+)\)`')[0]), n);
      expect(int.parse(stated(r'does not match its count at N = (\d+)')[0]), n);
      expect(int.parse(stated(r'but the count is not (\d+)')[0]), sites);
      expect(
        stated(r'`format (N \d+ · temperature v2, \d+ sites · rejects 0)`')[0],
        'N $n · temperature v2, $sites sites · rejects 0',
      );
    });
  });

  group('Appendix C examples', () {
    final vectorDir = Directory('../shared/test_vectors');
    // Every case of every vector file, by file and name (names repeat
    // across files: `quality_mixed` is also a v1.6 8-site case).
    final cases = <String, Map<String, Map<String, dynamic>>>{};
    Map<String, dynamic>? sensorCalibrations;
    for (final f in vectorDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final file = f.uri.pathSegments.last;
      if (file == 'sensor.json') {
        sensorCalibrations = doc['calibrations'] as Map<String, dynamic>;
      }
      cases[file] = {
        for (final c in (doc['cases'] as List? ?? const []))
          (c as Map<String, dynamic>)['name'] as String: c,
      };
    }

    // Each fenced block with the paragraph just before it (its caption).
    final blocks = RegExp(
      r'([^\n]*)\n\n```(json)?\n(.*?)\n```',
      dotAll: true,
    ).allMatches(appendix).toList();

    test('every hex example is its vector case and parses as stated', () {
      var checked = 0;
      for (final b in blocks.where((b) => b.group(2) == null)) {
        final caption = b.group(1)!;
        final rows = b.group(3)!.split('\n');
        final bytes = <int>[];
        for (final (i, row) in rows.indexed) {
          final parts = row.trim().split(RegExp(r'\s+'));
          expect(hex(parts.first), 16 * i, reason: 'offset column: $row');
          bytes.addAll(parts.skip(1).map(hex));
        }
        // Every hex caption names its file and case: (`file.json` → `case`).
        final ref = RegExp(r'`([a-z0-9_]+\.json)` → `([a-z0-9_]+)`')
            .firstMatch(caption);
        if (ref == null) fail('no (`file.json` → `case`) in: $caption');
        final file = ref.group(1)!;
        final name = ref.group(2)!;
        final c = cases[file]?[name];
        if (c == null) fail('$file has no case $name');
        expect(bytes, [
          for (var i = 0; i < (c['hex'] as String).length; i += 2)
            hex((c['hex'] as String).substring(i, i + 2)),
        ], reason: '$name hex differs from $file');
        final size = RegExp(r'(\d+)[ -]bytes?\b').firstMatch(caption);
        if (size != null) {
          expect(bytes.length, int.parse(size.group(1)!), reason: caption);
        }
        final wantReason = RegExp(r'reason `([A-Za-z]+)`')
            .firstMatch(caption)
            ?.group(1);
        final data = Uint8List.fromList(bytes);
        final ParseResult<Object> got = file.startsWith('sensor')
            ? parseSensorPacket(data, fsrCount: n)
            : file.startsWith('temperature')
            ? parseTempPacket(data)
            : parseStatusPacket(data);
        if (wantReason != null) {
          expect(got, isA<Rejected<Object>>(), reason: name);
          expect((got as Rejected).reason.name, wantReason, reason: name);
        } else {
          expect(got, isA<Parsed<Object>>(), reason: name);
        }
        checked++;
      }
      // sensor, two temperature, status, two rejected temperature.
      expect(checked, greaterThanOrEqualTo(6));
    });

    test('the decoded values written under the examples', () {
      List<num> list(String pattern) => [
        for (final v in stated(pattern)[0].split(', ')) num.parse(v),
      ];
      final sensorHex =
          cases['sensor.json']!['normal_8_samples_200_bytes']!['hex'] as String;
      final s = parseSensorPacket(
        Uint8List.fromList([
          for (var i = 0; i < sensorHex.length; i += 2)
            hex(sensorHex.substring(i, i + 2)),
        ]),
        fsrCount: n,
      );
      final s0 = (s as Parsed<SensorPacket>).value.samples.first;
      expect(list(r'Sample 0 \(bytes \d+–\d+\): fsr \[([^\]]*)\]'), s0.fsrAdc);
      expect(list(r'accel raw \[([^\]]*)\]'), s0.accelRaw);
      expect(list(r'gyro raw \[([^\]]*)\]'), s0.gyroRaw);

      final tempHex =
          cases['temperature_v2.json']!['quality_mixed']!['hex'] as String;
      final t = parseTempPacket(
        Uint8List.fromList([
          for (var i = 0; i < tempHex.length; i += 2)
            hex(tempHex.substring(i, i + 2)),
        ]),
      );
      final tv = (t as Parsed<TempPacket>).value;
      expect(list(r'°C per site 0–\d+ \[([^\]]*)\]'), tv.celsius);
      expect(list(r'quality per site 0–\d+ \[([^\]]*)\]'), [
        for (final q in tv.quality) q.index,
      ]);
    });

    test('the calibration JSON examples', () {
      final json = [
        for (final b in blocks.where((b) => b.group(2) == 'json')) b.group(3)!,
      ];
      expect(json, hasLength(2), reason: 'compact and spaced examples');
      final compact = json.first;
      expect(compact, isNot(contains(' ')));
      final bytes = utf8.encode(compact).length;
      expect(int.parse(stated(r'is (\d+) bytes compact')[0]), bytes);
      expect(
        int.parse(stated(r'Sent compact, as here, it is (\d+) bytes')[0]),
        bytes,
      );
      expect(bytes, lessThanOrEqualTo(512));
      final key = stated(r'`calibrations\.([a-z_]+)`')[0];
      for (final j in json) {
        expect(jsonDecode(j), sensorCalibrations![key]);
        final cal = parseCalibration(j);
        expect(cal, isA<Parsed<Calibration>>());
        expect((cal as Parsed<Calibration>).value.fsrCount, n);
      }
    });
  });
}

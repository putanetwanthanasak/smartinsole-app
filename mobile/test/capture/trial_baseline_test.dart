import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_files.dart';
import 'package:smartinsole/capture/trial_baseline.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/gait/baseline_recorder.dart';

import '../helpers/pump_app.dart';

/// BACKLOG 74: capture trial 00 and the Researcher recording go through
/// one baseline function. `shared/test_vectors/baseline/` is made by
/// `tools/model/preprocess.py --make-vectors`; the app must give the same
/// failure, row count and float64 medians, through the trial path and
/// through the live recorder.
void main() {
  final dir = Directory('../shared/test_vectors/baseline');
  final doc = jsonDecode(
    File('${dir.path}/expected.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (doc['cases'] as List).cast<Map<String, dynamic>>();

  test('the vectors were made with the app\'s thresholds and window', () {
    final t = doc['thresholds'] as Map<String, dynamic>;
    expect(t['windowMs'], testThresholds.walkingWindowMs);
    expect(t['accelG'], testThresholds.walkingAccelG);
    expect(t['contactKpa'], testThresholds.stepContactKpa);
    expect(doc['baselineSeconds'], testPreprocess.baselineSeconds);
    expect(
      doc['baselineToleranceSamples'],
      testPreprocess.baselineToleranceSamples,
    );
  });

  for (final c in cases) {
    test('trial path: ${c['name']} (${c['about']})', () async {
      final got = await checkTrialBaseline(
        File('${dir.path}/${c['csv']}'),
        spec: testPreprocess,
        thresholds: testThresholds,
      );
      final exp = c['expected'] as Map<String, dynamic>;
      for (final side in FootSide.values) {
        final e = exp[sideCode(side)] as Map<String, dynamic>;
        final f = got.feet[side]!;
        expect(f.failure?.name, e['failure'], reason: '$side failure');
        expect(f.sampleCount, e['sampleCount'], reason: '$side rows');
        final want = (e['values'] as List?)?.cast<num>().map(
          (v) => v.toDouble(),
        );
        // Exact: the same float64 bits as Python.
        expect(f.values, want?.toList(), reason: '$side values');
      }
      expect(got.ok, ['ok', 'slow_clock'].contains(c['name']));
    });
  }

  test('live path: the ok trial fed as 50 Hz batches gives the same', () {
    final lines = File('${dir.path}/ok.csv').readAsLinesSync();
    final cols = lines.first.split(',');
    int at(String n) => cols.indexOf(n);
    final rec = BaselineRecorder(
      spec: testPreprocess,
      thresholds: testThresholds,
      insoleIds: const {FootSide.left: 'L-1', FootSide.right: 'R-1'},
    );
    // Rows grouped back into their packets (side, seq), in file order.
    final packets = <(String, int), List<List<String>>>{};
    for (final line in lines.skip(1)) {
      final v = line.split(',');
      packets
          .putIfAbsent((v[at('side')], int.parse(v[at('seq')])), () => [])
          .add(v);
    }
    for (final MapEntry(key: (side, seq), value: rows) in packets.entries) {
      final first = rows.first;
      double d(List<String> v, String n) => double.parse(v[at(n)]);
      rec.add(
        FootBatch(
          side: side == 'L' ? FootSide.left : FootSide.right,
          session: int.parse(first[at('conn_session')]),
          seq: seq,
          missingBefore: int.parse(first[at('missing_before')]),
          receivedAt: DateTime(2026, 11, 2),
          saturated: false,
          calibrating: first[at('calibrating')] == '1',
          samples: [
            for (final v in rows)
              FootSample(
                unixMs: d(v, 'unix_ms'),
                deviceMs: int.parse(v[at('device_ms')]),
                fsrAdc: List.filled(8, 0),
                fsrKpa: [for (var i = 0; i < 8; i++) d(v, 'fsr${i}_kpa')],
                accelG: [for (final a in 'xyz'.split('')) d(v, 'accel_${a}_g')],
                gyroDps: [
                  for (final a in 'xyz'.split('')) d(v, 'gyro_${a}_dps'),
                ],
              ),
          ],
        ),
      );
    }
    expect(rec.failure, isNull);
    expect(rec.done, isTrue);
    final exp =
        cases.firstWhere((c) => c['name'] == 'ok')['expected']
            as Map<String, dynamic>;
    for (final b in rec.result(0)!) {
      final e = exp[sideCode(b.side)] as Map<String, dynamic>;
      expect(b.sampleCount, e['sampleCount']);
      expect(
        b.values,
        (e['values'] as List).cast<num>().map((v) => v.toDouble()),
      );
    }
  });

  test('a schema-1 trial (6 FSR) is wrongInsole', () {
    final header = [
      'unix_ms',
      'side',
      'conn_session',
      'missing_before',
      'calibrating',
      'valid',
      for (var i = 0; i < 6; i++) 'fsr${i}_kpa',
      'accel_x_g',
      'accel_y_g',
      'accel_z_g',
      'gyro_x_dps',
      'gyro_y_dps',
      'gyro_z_dps',
    ].join(',');
    final r = trialBaselineOf(
      [header, '1000,L,1,0,0,1,${List.filled(6, '30').join(',')},0,0,1,0,0,0'],
      spec: testPreprocess,
      thresholds: testThresholds,
    );
    expect(r.feet[FootSide.left]!.failure, BaselineFailure.wrongInsole);
    expect(r.feet[FootSide.right]!.failure, BaselineFailure.tooShort);
  });
}

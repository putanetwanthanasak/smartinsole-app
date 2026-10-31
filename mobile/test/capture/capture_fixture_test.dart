import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/alerts_csv.dart';
import 'package:smartinsole/capture/export.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/device/model_channels.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/models.dart';

import 'capture_rig.dart';

/// `shared/capture_fixture/schema2/`: one rehearsal session recorded by the
/// real capture code (capture schema 2: 8 FSR, 8 temperature sites),
/// exported with its manifest, plus `expected.json` — the 28-channel rows
/// the app's own [pairFeet] + [modelRow] make from the same samples.
/// `tools/capture/load_capture.py --selftest` must reproduce them from the
/// files, which checks the column order and the pairing rule across the two
/// languages. `schema1/` is the frozen schema-1 (6-FSR) fixture: the loader
/// must keep reading it; nothing writes it any more.
///
/// Regenerate after an intended format change (rewrites `schema2/` only):
///   UPDATE_CAPTURE_FIXTURE=1 flutter test test/capture/capture_fixture_test.dart
const fixtureDir = '../shared/capture_fixture/schema2';

/// Values exactly representable at the CSV's decimals (kPa 3, g 6, dps 4),
/// different per channel and per sample, so a swapped column shows.
SensorSample Function(int i, int deviceMs) samples(double base) => (i, ms) {
  final k = (ms ~/ 20) % 50;
  return SensorSample(
    deviceMs: ms,
    fsrAdc: [for (var c = 0; c < modelFsrCount; c++) 100 * c + k],
    fsrKpa: [for (var c = 0; c < modelFsrCount; c++) base + 10 * c + k + 0.125],
    accelG: [for (var a = 0; a < 3; a++) (base + a) / 100 + k / 1000],
    gyroDps: [for (var a = 0; a < 3; a++) -(base + a) - k / 10],
  );
};

void main() {
  test('capture fixture matches the code that writes it', () {
    final generated = Directory.systemTemp.createTempSync('fixture_');
    fakeAsync((async) {
      final rig = CaptureRig(async, code: 'TEST-009');
      final batches = <FootBatch>[];
      rig.manager.batches.listen(batches.add);
      final s = rig.session..startRecording();
      final start = s.recorder!.startUnixMs;
      for (var k = 0; k < 40; k++) {
        async.elapse(const Duration(milliseconds: 153));
        if (k == 3 || k == 33) {
          // Temperature v2 readings: every site different, one site the
          // left sensor could not read, one right site in poor contact.
          rig.left.temp(
            null,
            sites: {for (var i = 0; i < 8; i++) i: i == 6 ? null : 31 + i / 8},
          );
          rig.right.temp(
            null,
            sites: {for (var i = 0; i < 8; i++) i: 31.5 + i / 4 + k / 100},
            qualityAt: {2: TempQuality.poorContact},
          );
        }
        rig.left.packet(sample: samples(100));
        async.elapse(const Duration(milliseconds: 7));
        if (k == 20) {
          rig.right.seq += 1; // one packet lost on the right
          rig.right.t0 += 160;
        } else {
          rig.right.packet(
            sample: samples(500),
            missingBefore: k == 21 ? 1 : 0,
          );
        }
      }
      s.stopEarly();
      async.elapse(const Duration(seconds: 1));
      final end = s.attempt!;
      final j = File('${s.dir.path}/${end.baseName}.json').readAsStringSync();
      final endUnix = (jsonDecode(j) as Map)['endUnixMs']! as double;

      List<FootSample> side(FootSide f) => [
        for (final b in batches)
          if (b.side == f)
            for (final x in b.samples)
              if (x.unixMs >= start && x.unixMs < endUnix) x,
      ];
      final pairs = pairFeet(side(FootSide.left), side(FootSide.right));
      s.noteExport();
      // One alert raised during the trial (BACKLOG 40), as the export
      // writes it.
      stageExport(
        s.dir,
        generated,
        extra: {
          alertsCsvName: alertsCsv([
            StoredAlert(
              id: 1,
              kind: AlertKind.pressurePeak,
              level: AlertKind.pressurePeak.level,
              patientLevel: PatientLevel.careful,
              atMs: (start + 1000).round(),
              localDate: '2026-11-10',
              side: FootSide.left,
              zone: 'meta1',
              measuredValue: 236.5,
              threshold: 200,
              details: const {'walking': true},
              captureStamp: captureStampOf(s.sessionId),
            ),
            StoredAlert(
              id: 2,
              kind: AlertKind.tempDelta,
              level: AlertKind.tempDelta.level,
              patientLevel: PatientLevel.rest,
              atMs: (start + 3000).round(),
              localDate: '2026-11-10',
              side: FootSide.right,
              zone: 'heel',
              measuredValue: 2.6,
              threshold: 2.2,
              details: {
                'consecutive': 2,
                TempSiteEntry.listKey: [
                  TempSiteEntry(
                    zone: 'heel',
                    deltaC: 2.6,
                    atMs: (start + 3000).round(),
                  ).toJson(),
                  TempSiteEntry(
                    zone: 'lateralHeel',
                    deltaC: 2.31,
                    atMs: (start + 4000).round(),
                  ).toJson(),
                ],
              },
              captureStamp: captureStampOf(s.sessionId),
            ),
          ]),
        },
      );
      File('${generated.path}/expected.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'about': 'Rows from mobile pairFeet + modelRow on the samples of '
              '${end.baseName}; see capture_fixture_test.dart.',
          'trial': end.baseName,
          'channels': modelChannelNames,
          'pairs': [
            for (final (l, r) in pairs) [l.unixMs, r.unixMs],
          ],
          'rows': [for (final (l, r) in pairs) modelRow(l, r)],
        })}\n',
      );
      rig.dispose();
    });

    final fixture = Directory(fixtureDir);
    if (Platform.environment['UPDATE_CAPTURE_FIXTURE'] == '1') {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      fixture.createSync(recursive: true);
      for (final f in generated.listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(generated.path.length + 1);
        File('${fixture.path}/$rel')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(f.readAsBytesSync());
      }
    }
    final want = {
      for (final f in fixture.listSync(recursive: true).whereType<File>())
        f.path.substring(fixture.path.length + 1): f.readAsStringSync(),
    };
    final got = {
      for (final f in generated.listSync(recursive: true).whereType<File>())
        f.path.substring(generated.path.length + 1): f.readAsStringSync(),
    };
    generated.deleteSync(recursive: true);
    expect(got.keys.toSet(), want.keys.toSet());
    for (final k in got.keys) {
      expect(got[k], want[k], reason: k);
    }
  });
}

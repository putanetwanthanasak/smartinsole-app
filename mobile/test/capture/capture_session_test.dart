import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_files.dart';
import 'package:smartinsole/capture/capture_protocol.dart';
import 'package:smartinsole/capture/capture_session.dart';
import 'package:smartinsole/capture/cues.dart';
import 'package:smartinsole/capture/export.dart';
import 'package:smartinsole/device/display_snapshot.dart';
import 'package:smartinsole/device/model_channels.dart';

import 'capture_rig.dart';

Map<String, Object?> sidecar(CaptureRig rig, String base) =>
    readJson(File('${rig.session.dir.path}/$base.json'));

Csv csvOf(CaptureRig rig, String base) =>
    Csv(File('${rig.session.dir.path}/$base.csv'));

/// Records one trial to the end (plus the grace period).
void recordToEnd(CaptureRig rig) {
  rig.session.startRecording();
  rig.walk(rig.session.plannedDuration + const Duration(seconds: 1));
}

void main() {
  test('CSV per-foot columns are model_input.json names without L_/R_', () {
    final cols = csvColumns(modelFsrCount);
    for (final side in FootSide.values) {
      final names = [
        for (final c in cols)
          if (modelChannelNames.contains(modelChannelOf(side, c)))
            modelChannelOf(side, c),
      ];
      // Same channels, same order (§7.1) as the model's block of that foot.
      final start = modelChannelOffset(side);
      expect(names, modelChannelNames.sublist(start, start + 12));
    }
  });

  test('a session writes session.json with coded subject data only', () {
    fakeAsync((async) {
      final rig = CaptureRig(async, code: 'SI-002');
      final j = readJson(File('${rig.session.dir.path}/session.json'));
      expect(rig.session.sessionId, 'SI-002_20261110-090000');
      expect((j['subject']! as Map).keys.toSet(), {
        'code',
        'sex',
        'ageRange',
        'footLengthCm',
      });
      expect(j['painSide'], 'R');
      expect((j['order']! as List).first, 'normal');
      expect(j['orderSeed'], 7);
      expect(j['roomTempC'], 25.5);
      rig.dispose();
    });
  });

  group('recording', () {
    test('auto-stops at the deadline: 50 Hz rows per foot, in window', () {
      fakeAsync((async) {
        final rig = CaptureRig(async, code: 'SI-001');
        final s = rig.session;
        expect(s.current.plan.isCalibration, isTrue);
        s.startRecording();
        expect(s.phase, CapturePhase.recording);
        rig.walk(const Duration(seconds: 29, milliseconds: 920));
        expect(s.phase, CapturePhase.recording);
        rig.walk(const Duration(seconds: 2));
        expect(s.phase, CapturePhase.saved);
        expect(rig.cues.played, [Cue.start, Cue.warning, Cue.end]);

        final j = sidecar(rig, 'SI-001_00_calibration_a1');
        expect(j['endReason'], 'completed');
        expect(j['valid'], isTrue);
        expect(j['durationS'], 30.0);
        expect(j['gaps'], isEmpty);
        expect(j['painSide'], isNull);
        final start = j['startUnixMs']! as double;
        final end = j['endUnixMs']! as double;

        final csv = csvOf(rig, 'SI-001_00_calibration_a1');
        expect(csv.header, csvColumns(6));
        for (final side in ['L', 'R']) {
          final rows = csv.side(side);
          // 30 s × 50 Hz, less at most one packet at each edge.
          expect(rows.length, inInclusiveRange(1500 - 16, 1500));
          var prev = double.negativeInfinity;
          for (final r in rows) {
            final t = csv.num(r, 'unix_ms');
            expect(t, greaterThan(prev));
            expect(t, greaterThanOrEqualTo(start));
            expect(t, lessThan(end));
            if (prev.isFinite) expect(t - prev, closeTo(20, 0.5));
            prev = t;
          }
        }
        final feet = j['feet']! as Map<String, Object?>;
        final l = feet['L']! as Map<String, Object?>;
        expect(l['batteryStartPct'], 90);
        expect(l['firmware'], '1.2');
        expect((l['calibration']! as Map)['deviceId'], 'L-001');
        rig.dispose();
      });
    });

    test('a starved timer cannot stretch a trial (deadline, not ticks)', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session..startRecording();
        rig.walk(const Duration(seconds: 2));
        // The wall clock moves 5 s while no timer fires.
        rig.skew = const Duration(seconds: 5);
        rig.walk(const Duration(seconds: 3, milliseconds: 200));
        // 10 s calibration: 5.2 s of timer time + 5 s skew ≥ 10 s.
        expect(s.phase, isNot(CapturePhase.recording));
        rig.walk(const Duration(seconds: 1));
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        expect(j['durationS'], 10.0);
        final csv = csvOf(rig, 'TEST-001_00_calibration_a1');
        final end = j['endUnixMs']! as double;
        for (final r in csv.rows) {
          expect(csv.num(r, 'unix_ms'), lessThan(end));
        }
        rig.dispose();
      });
    });

    test('stop early: stopped_early, the window ends at the stop', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session..startRecording();
        rig.walk(const Duration(seconds: 4));
        s.stopEarly();
        expect(s.phase, CapturePhase.saving);
        rig.walk(const Duration(seconds: 1));
        expect(s.phase, CapturePhase.saved);
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        expect(j['endReason'], 'stopped_early');
        expect(j['durationS'], closeTo(4.0, 0.01));
        // Every row is inside the window the sidecar gives.
        final csv = csvOf(rig, 'TEST-001_00_calibration_a1');
        for (final r in csv.rows) {
          expect(csv.num(r, 'unix_ms'), lessThan(j['endUnixMs']! as double));
        }
        expect(rig.cues.played.last, Cue.end);
        rig.dispose();
      });
    });

    test('redo keeps the old files, marked invalid; a2 is recorded', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session;
        recordToEnd(rig);
        final before = File('${s.dir.path}/TEST-001_00_calibration_a1.csv')
            .readAsStringSync();
        s.redo();
        expect(s.phase, CapturePhase.ready);
        expect(s.current.plan.isCalibration, isTrue);
        recordToEnd(rig);
        final a1 = sidecar(rig, 'TEST-001_00_calibration_a1');
        expect(a1['valid'], isFalse);
        expect(a1['invalidReason'], 'redo');
        expect(
          File('${s.dir.path}/TEST-001_00_calibration_a1.csv')
              .readAsStringSync(),
          before,
        );
        final a2 = sidecar(rig, 'TEST-001_00_calibration_a2');
        expect(a2['valid'], isTrue);
        expect(a2['attempt'], 2);
        final sj = readJson(File('${s.dir.path}/session.json'));
        final attempts = ((sj['trials']! as List).first as Map)['attempts'];
        expect(attempts, hasLength(2));
        rig.dispose();
      });
    });

    test('a seq gap and a link loss with reconnect are both recorded', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session;
        s
          ..next() // not saved yet: ignored
          ..startRecording();
        rig.walk(const Duration(seconds: 1));
        rig.left.seq += 2; // two packets lost
        rig.left.packet(missingBefore: 2);
        rig.walk(const Duration(seconds: 1));
        // The left link drops for 4 s, then a new session streams.
        rig
          ..leftOn = false
          ..left.set(const LinkSearching(deviceId: 'X'));
        rig.walk(const Duration(seconds: 4));
        expect(s.linkLost, {FootSide.left});
        rig
          ..left.stream()
          ..leftOn = true;
        rig.walk(const Duration(seconds: 1));
        expect(s.linkLost, isEmpty);
        rig.walk(const Duration(seconds: 5));
        expect(s.phase, CapturePhase.saved);

        expect(
          rig.cues.played.where((c) => c == Cue.linkLost).length,
          greaterThanOrEqualTo(1),
        );
        expect(rig.cues.played, contains(Cue.linkBack));
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        final kinds = [for (final g in j['gaps']! as List) (g as Map)['kind']];
        expect(kinds, ['seq_gap', 'link_lost']);
        final seqGap = (j['gaps']! as List).first as Map;
        expect(seqGap['missingPackets'], 2);
        expect(seqGap['side'], 'L');
        final l = (j['feet']! as Map)['L']! as Map;
        expect(l['connSessions'], [1, 2]);
        expect(s.attempt!.gapCount, 2);

        final csv = csvOf(rig, 'TEST-001_00_calibration_a1');
        final left = csv.side('L');
        expect(
          left.where((r) => r[csv.col('missing_before')] == '2'),
          hasLength(1),
        );
        expect({for (final r in left) r[csv.col('conn_session')]}, {'1', '2'});
        rig.dispose();
      });
    });

    test('a foot silent at the end is a gap', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        rig.session.startRecording();
        rig.walk(const Duration(seconds: 8));
        rig.rightOn = false;
        rig.walk(const Duration(seconds: 3));
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        expect(
          [for (final g in j['gaps']! as List) (g as Map)['kind']],
          ['no_data_at_end'],
        );
        rig.dispose();
      });
    });

    test('a marked segment sets valid 0 on its rows only', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session..startRecording();
        rig.walk(const Duration(seconds: 2));
        s.toggleMarkInvalid();
        expect(s.markedInvalid, isTrue);
        rig.walk(const Duration(seconds: 2));
        s.toggleMarkInvalid();
        rig.walk(const Duration(seconds: 7));
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        final seg = (j['invalidSegments']! as List).single as Map;
        final from = seg['fromUnixMs']! as double;
        final to = seg['toUnixMs']! as double;
        expect(to - from, closeTo(1920, 1));
        final csv = csvOf(rig, 'TEST-001_00_calibration_a1');
        for (final r in csv.rows) {
          final t = csv.num(r, 'unix_ms');
          final inside = t >= from && t < to;
          expect(r[csv.col('valid')], inside ? '0' : '1');
        }
        expect(
          csv.rows.where((r) => r[csv.col('valid')] == '0').length,
          inInclusiveRange(2 * 90, 2 * 100),
        );
        rig.dispose();
      });
    });

    test('temperature readings land on the next row and the sidecar', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        rig.session.startRecording();
        rig.walk(const Duration(seconds: 1));
        rig.left.temp(31.25, 30.5);
        rig.walk(const Duration(seconds: 10));
        final csv = csvOf(rig, 'TEST-001_00_calibration_a1');
        final withTemp = [
          for (final r in csv.rows)
            if (r[csv.col('temp_forefoot_c')].isNotEmpty) r,
        ];
        expect(withTemp, hasLength(1));
        expect(withTemp.single[csv.col('side')], 'L');
        expect(withTemp.single[csv.col('temp_forefoot_c')], '31.25');
        expect(withTemp.single[csv.col('temp_quality')], 'normal');
        final j = sidecar(rig, 'TEST-001_00_calibration_a1');
        final temps = ((j['feet']! as Map)['L']! as Map)['temps'] as List;
        expect((temps.single as Map)['heelC'], 30.5);
        // The calibration summary takes ΔT only from both feet (rule 4).
        final sum = rig.session.calibrationSummary!;
        expect(sum['startDeltaForefootC'], isNull);
        rig.dispose();
      });
    });
  });

  group('flow', () {
    test('practice cues, then recording starts on its own', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session;
        recordToEnd(rig);
        s.next();
        expect(s.current.plan.gait, GaitClass.normal);
        s.startPractice();
        expect(s.phase, CapturePhase.practice);
        rig.walk(const Duration(seconds: 5, milliseconds: 120));
        expect(s.phase, CapturePhase.recording);
        expect(rig.cues.played.sublist(2), [Cue.practice, Cue.start]);
        rig.dispose();
      });
    });

    test('rotated foot needs the direction before it can start', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session;
        for (var i = 0; i < 6; i++) {
          if (s.current.plan.gait == GaitClass.rotatedFoot) break;
          recordToEnd(rig);
          s.next();
        }
        expect(s.current.plan.gait, GaitClass.rotatedFoot);
        expect(s.canStart, isFalse);
        s.startRecording();
        expect(s.phase, CapturePhase.ready);
        s
          ..setRotation(Rotation.outToeing)
          ..startRecording();
        expect(s.phase, CapturePhase.recording);
        rig.walk(const Duration(seconds: 31));
        final j = sidecar(rig, s.attempt!.baseName);
        expect(j['rotation'], 'out_toeing');
        expect(j['gait'], {'id': 'rotated_foot', 'modelIndex': 4});
        rig.dispose();
      });
    });

    test('a whole session ends done; antalgic carries the pain side', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        final s = rig.session;
        while (s.phase != CapturePhase.done) {
          if (s.current.plan.gait == GaitClass.rotatedFoot) {
            s.setRotation(Rotation.inToeing);
          }
          recordToEnd(rig);
          s.next();
        }
        final files = s.dir.listSync().map((f) => f.uri.pathSegments.last);
        expect(files.where((f) => f.endsWith('.csv')), hasLength(6));
        final antalgic = files.firstWhere(
          (f) => f.contains('antalgic') && f.endsWith('.json'),
        );
        expect(sidecar(rig, antalgic.replaceAll('.json', ''))['painSide'], 'L');
        final sj = readJson(File('${s.dir.path}/session.json'));
        expect(sj['status'], 'done');
        rig.dispose();
      });
    });

    test('resume after a crash: the open attempt becomes interrupted', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        recordToEnd(rig);
        rig.session
          ..next()
          ..startRecording();
        rig.walk(const Duration(seconds: 3));
        // The app dies here: nothing else runs. A new process reopens it.
        final resumed = CaptureSession.resume(
          deps: rig.session.deps,
          dir: rig.session.dir,
        );
        expect(resumed.index, 1);
        expect(resumed.phase, CapturePhase.ready);
        final a = resumed.current.attempts.single;
        expect(a.endReason, EndReason.interrupted);
        expect(a.valid, isFalse);
        final j = sidecar(rig, a.baseName);
        expect(j['endReason'], 'interrupted');
        expect(j['valid'], isFalse);
        expect(resumed.trials.first.done, isTrue);
        expect(resumed.order, rig.session.order);
        resumed.dispose();
        rig.dispose();
      });
    });

    test('leaving mid-recording closes the attempt as interrupted', () {
      fakeAsync((async) {
        final rig = CaptureRig(async);
        rig.session.startRecording();
        rig.walk(const Duration(seconds: 3));
        final base = rig.session.attempt!.baseName;
        rig.session.dispose();
        final j = sidecar(rig, base);
        expect(j['endReason'], 'interrupted');
        expect(j['valid'], isFalse);
        rig.manager.dispose();
        rig.root.deleteSync(recursive: true);
      });
    });
  });

  group('pre-check', () {
    FootView view({
      FootConnection c = FootConnection.streaming,
      int? battery = 90,
      int fsr = 6,
    }) => FootView(
      side: FootSide.left,
      connection: c,
      batteryPct: battery,
      firmware: '1.2',
      kpa: c == FootConnection.streaming ? List.filled(fsr, 0) : null,
    );

    test('passes at 80 %, blocks at 79 %', () {
      expect(precheckIssues(view(battery: 80), hasCalibration: true), isEmpty);
      expect(precheckIssues(view(battery: 79), hasCalibration: true), [
        'battery 79 % < 80 %',
      ]);
    });

    test('blocks a stale foot, a wrong FSR count, no calibration', () {
      expect(
        precheckIssues(view(c: FootConnection.stale), hasCalibration: true),
        contains('not streaming'),
      );
      expect(precheckIssues(view(fsr: 8), hasCalibration: true), [
        '8 FSR channels, need 6',
      ]);
      expect(precheckIssues(view(), hasCalibration: false), [
        'no calibration read',
      ]);
    });
  });

  test('export: manifest hashes match, originals untouched', () {
    fakeAsync((async) {
      final rig = CaptureRig(async);
      recordToEnd(rig);
      rig.session.noteExport();
      final out = Directory('${rig.root.path}/export');
      final entries = stageExport(rig.session.dir, out);
      final dest = Directory('${out.path}/${rig.session.sessionId}');
      final manifest = jsonDecode(
        File('${dest.path}/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final files = manifest['files']! as List;
      expect(files, hasLength(entries.length));
      expect(
        [for (final f in files) (f as Map)['name']],
        containsAll([
          'session.json',
          'TEST-001_00_calibration_a1.csv',
          'TEST-001_00_calibration_a1.json',
        ]),
      );
      for (final f in files.cast<Map<String, Object?>>()) {
        final copy = File('${dest.path}/${f['name']}');
        expect(sha256Of(copy), f['sha256']);
        expect(copy.lengthSync(), f['size']);
        expect(
          File('${rig.session.dir.path}/${f['name']}').existsSync(),
          isTrue,
        );
      }
      final sj = readJson(File('${dest.path}/session.json'));
      expect(sj['exports'], hasLength(1));
      expect(listSessions(rig.root).single.exported, isTrue);
      rig.dispose();
    });
  });
}

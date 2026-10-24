import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/gait_note.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';

import '../helpers/pump_app.dart';
import 'rules_rig.dart';

void main() {
  final t = testThresholds;
  const zero = <double>[0, 0, 0, 0, 0, 0];

  /// [k] kPa at [channel] only, during every stance.
  List<double> at(int channel, double k) => [
    for (var c = 0; c < 6; c++) c == channel ? k : 0,
  ];

  /// A light normal walk, nothing near any boundary.
  const light = Gait(kpa: [20, 20, 20, 20, 20, 20]);

  /// Strides for [steps] steps of one foot.
  Duration strides(int steps, Gait g) =>
      Duration(milliseconds: steps * g.strideMs + g.strideMs ~/ 2);

  Iterable<AlertCode> codes(RulesRig rig) =>
      rig.view().conditions.map((c) => c.code);

  group('PRESSURE_WATCH (level 2, no walking gate)', () {
    test('above watchKpa, not at it; stored but never listed', () async {
      final rig = RulesRig()..stream();
      rig.walkBoth(const Duration(seconds: 3), Gait(kpa: at(1, t.watchKpa)));
      expect(codes(rig), isNot(contains(AlertCode.pressureWatch)));
      rig.walkBoth(
        const Duration(seconds: 3),
        Gait(kpa: at(1, t.watchKpa + 0.5)),
      );
      final c = rig.view().conditions.firstWhere(
        (c) => c.code == AlertCode.pressureWatch,
      );
      expect((c.channel, c.value, c.threshold), (1, t.watchKpa + 0.5, 75));
      expect(rig.view().status, PatientStatus.safe, reason: 'level 2');
      final stored = await rig.stored();
      expect(stored.map((a) => a.kind).toSet(), {AlertKind.pressureWatch});
      expect(stored.map((a) => a.side).toSet(), FootSide.values.toSet());
      expect(
        await rig.alerts.watchVisible(rig.now().millisecondsSinceEpoch).first,
        isEmpty,
      );
    });

    test('a high value while standing is WATCH, never PEAK (rule 7)', () async {
      final rig = RulesRig()..stream();
      final high = Gait.standing(at(5, t.alertKpa + 50));
      rig.run(const Duration(seconds: 5), left: high, right: high);
      expect(codes(rig), contains(AlertCode.pressureWatch));
      expect(codes(rig), isNot(contains(AlertCode.pressurePeak)));
      expect(await rig.storedKinds(), [
        AlertKind.pressureWatch,
        AlertKind.pressureWatch,
      ]);
    });
  });

  group('PRESSURE_PEAK (level 3, walking only)', () {
    test('above alertKpa while walking, not at it', () async {
      final rig = RulesRig()..stream();
      rig.walkBoth(const Duration(seconds: 3), Gait(kpa: at(1, t.alertKpa)));
      expect(codes(rig), isNot(contains(AlertCode.pressurePeak)));
      rig.walkBoth(
        const Duration(seconds: 3),
        Gait(kpa: at(1, t.alertKpa + 0.5)),
        right: light,
      );
      final s = rig.view().status;
      expect(s.level, PatientLevel.careful);
      expect(s.cause!.code, AlertCode.pressurePeak);
      expect((s.cause!.side, s.cause!.channel), (FootSide.left, 1));
      final peak = (await rig.stored()).firstWhere(
        (a) => a.kind == AlertKind.pressurePeak,
      );
      expect(peak.zone, 'meta1');
      expect(peak.measuredValue, t.alertKpa + 0.5);
      expect(peak.threshold, 200);
      expect(peak.patientLevel, PatientLevel.careful);
      expect(peak.details, {'walking': true});
    });

    test('stops holding peakHoldMs after the last walking sample above', () {
      final rig = RulesRig()..stream();
      rig.walkBoth(
        const Duration(seconds: 3),
        Gait(kpa: at(1, t.alertKpa + 40)),
      );
      expect(rig.view().status.level, PatientLevel.careful);
      // Stops walking: standing on a light load.
      final stand = Gait.standing(at(5, 30));
      rig.run(
        Duration(milliseconds: t.peakHoldMs),
        left: stand,
        right: stand,
      );
      rig.run(const Duration(seconds: 1), left: stand, right: stand);
      expect(rig.view().status, PatientStatus.safe);
    });
  });

  group('PRESSURE_PTI (level 3; per step, 1 h mean, BACKLOG 31)', () {
    // 63 samples of 64 kPa per stance: exactly 80 kPa·s per step (see
    // step_detector_test.dart). 64.5 kPa: 80.625 kPa·s.
    Gait pti(double k) => Gait(strideMs: 1700, stanceMs: 1260, kpa: at(2, k));

    test('mean per-step PTI above ptiKpaS, not at it', () {
      final atLimit = RulesRig()..stream();
      atLimit.walkBoth(strides(25, pti(64)), pti(64));
      expect(codes(atLimit), isNot(contains(AlertCode.pressurePti)));

      final above = RulesRig()..stream();
      above.walkBoth(strides(25, pti(64.5)), pti(64.5));
      final c = above.view().conditions.firstWhere(
        (c) => c.code == AlertCode.pressurePti,
      );
      expect(c.value, 80.625);
      expect(c.channel, 2);
      expect(c.details['windowMin'], 60);
      expect(above.view().status.cause!.code, AlertCode.pressurePti);
    });

    test('needs ptiMinSteps steps in the window', () {
      final rig = RulesRig()..stream();
      final g = pti(100);
      // The first step ends at 1260 ms; step n at 1260 + (n − 1) × 1700.
      rig.walkBoth(Duration(milliseconds: 1260 + 18 * 1700 + 100), g);
      expect(codes(rig), isNot(contains(AlertCode.pressurePti)));
      rig.walkBoth(const Duration(milliseconds: 1700), g);
      expect(codes(rig), contains(AlertCode.pressurePti));
    });

    test('steps older than ptiWindowMin leave the mean', () {
      final rig = RulesRig()..stream();
      rig.walkBoth(strides(25, pti(100)), pti(100));
      expect(codes(rig), contains(AlertCode.pressurePti));
      // An hour and a minute later, a light walk: only new steps count.
      rig.pause(Duration(minutes: t.ptiWindowMin + 1));
      rig.walkBoth(strides(5, pti(20)), pti(20));
      expect(codes(rig), isNot(contains(AlertCode.pressurePti)));
    });

    test('stops holding when the walk stops (status, not the window)', () {
      final rig = RulesRig()..stream();
      rig.walkBoth(strides(25, pti(100)), pti(100));
      expect(rig.view().status.level, PatientLevel.careful);
      final sit = Gait.standing(at(5, 30));
      rig.run(
        Duration(milliseconds: t.maxStanceMs + 500),
        left: sit,
        right: sit,
      );
      expect(rig.view().status, PatientStatus.safe);
    });
  });

  group('LOAD_CONCENTRATION (level 3; same zone, consecutive steps)', () {
    Gait conc(double top) =>
        Gait(kpa: [top, 10, 10, 10, 10, 20]); // 40 of 100 = exactly 40 %

    test('above concentrationPct, not at it', () {
      final rig = RulesRig()..stream();
      rig.walkBoth(strides(25, conc(40)), conc(40));
      expect(codes(rig), isNot(contains(AlertCode.loadConcentration)));
      rig.walkBoth(strides(25, conc(41)), conc(41));
      final c = rig.view().conditions.firstWhere(
        (c) => c.code == AlertCode.loadConcentration,
      );
      expect(c.channel, 0);
      expect(c.value, closeTo(41 * 100 / 101, 1e-9));
    });

    test('concentrationSteps in a row; a different top zone restarts', () {
      final rig = RulesRig()..stream();
      // Step n of the left foot ends at 600 + (n − 1) × 1000 ms.
      rig.walkBoth(
        const Duration(milliseconds: 600 + 18 * 1000 + 100),
        conc(60),
      );
      expect(codes(rig), isNot(contains(AlertCode.loadConcentration)));
      rig.walkBoth(const Duration(milliseconds: 1000), conc(60));
      expect(codes(rig), contains(AlertCode.loadConcentration));
      // The heel takes over: a new run of the heel, from 1.
      const heel = Gait(kpa: [10, 10, 10, 10, 10, 60]);
      rig.walkBoth(const Duration(milliseconds: 1000), heel);
      expect(codes(rig), isNot(contains(AlertCode.loadConcentration)));
    });

    test('never while standing', () {
      final rig = RulesRig()..stream();
      final g = Gait.standing(const [60, 10, 10, 10, 10, 0]);
      rig.run(const Duration(seconds: 30), left: g, right: g);
      expect(codes(rig), isNot(contains(AlertCode.loadConcentration)));
    });
  });

  group('ASYMMETRY_PEAK (level 2; per-step peaks, BACKLOG 37)', () {
    // PAI of 107.5 and 92.5 is exactly 15 %.
    Gait foot(double k, {int phase = 0}) => Gait(kpa: at(5, k), phaseMs: phase);

    test('above peakPct for peakSteps steps; stored, Safe card', () async {
      final rig = RulesRig()..stream();
      rig.run(
        const Duration(seconds: 15),
        left: foot(107.5),
        right: foot(92.5, phase: 500),
      );
      expect(codes(rig), isNot(contains(AlertCode.asymmetryPeak)));
      expect(rig.engine.asymmetrySteps, 0);

      // Steps of either foot count, from the first one that has a step
      // of the other foot to compare with: 19 above, then the 20th.
      final rig2 = RulesRig()..stream();
      void walkUntil(int steps) {
        while (rig2.engine.asymmetrySteps < steps) {
          rig2.run(
            const Duration(milliseconds: 160),
            left: foot(107.5),
            right: foot(92, phase: 500),
          );
        }
      }

      walkUntil(t.peakAsymmetrySteps - 1);
      expect(codes(rig2), isNot(contains(AlertCode.asymmetryPeak)));
      walkUntil(t.peakAsymmetrySteps);
      final c = rig2.view().asymmetry!;
      expect(c.side, FootSide.left, reason: 'the higher foot');
      expect(rig2.view().status, PatientStatus.safe);
      expect(await rig2.storedKinds(), contains(AlertKind.asymmetryPeak));
    });

    test('needs both feet (rule 4)', () {
      final rig = RulesRig()..stream();
      rig.run(
        const Duration(seconds: 15),
        left: foot(150),
        right: foot(50, phase: 500),
      );
      expect(codes(rig), contains(AlertCode.asymmetryPeak));
      rig.run(const Duration(seconds: 4), left: foot(150));
      expect(codes(rig), isNot(contains(AlertCode.asymmetryPeak)));
    });
  });

  group('TEMP_DELTA (level 4; 2 consecutive readings, rule 6)', () {
    final over = t.deltaC + 0.4;

    void pair(RulesRig rig, double l, double r) {
      rig.walkBoth(const Duration(milliseconds: 320), light);
      rig
        ..temp(FootSide.left, l, 30)
        ..temp(FootSide.right, r, 30);
    }

    test('two pairs above deltaC at one site; the warmer foot', () async {
      final rig = RulesRig()..stream();
      pair(rig, 31.0, 31.0 + over);
      expect(rig.engine.overCount(TempSite.forefoot), 1);
      expect(rig.view().status, PatientStatus.safe);
      pair(rig, 31.0, 31.0 + over);
      final s = rig.view().status;
      expect(s.level, PatientLevel.rest);
      expect(s.cause!.side, FootSide.right);
      expect(s.cause!.site, TempSite.forefoot);
      expect(s.cause!.deltaC, closeTo(over, 1e-9));
      final a = (await rig.stored()).single;
      expect(a.kind, AlertKind.tempDelta);
      expect(a.patientLevel, PatientLevel.rest);
      expect(a.details!['consecutive'], 2);
      expect(a.details!['rightC'], 31.0 + over);
    });

    test('exactly deltaC is not above, and resets the run', () {
      final rig = RulesRig()..stream();
      pair(rig, 31.0 + over, 31.0);
      pair(rig, 31.0 + t.deltaC, 31.0);
      expect(rig.engine.overCount(TempSite.forefoot), 0);
      pair(rig, 31.0 + over, 31.0);
      expect(rig.view().status, PatientStatus.safe);
      pair(rig, 31.0 + over, 31.0);
      expect(rig.view().status.level, PatientLevel.rest);
      expect(rig.view().status.cause!.side, FootSide.left);
    });

    test('a pair without a ΔT (poor contact) resets the run', () {
      final rig = RulesRig()..stream();
      pair(rig, 31.0 + over, 31.0);
      rig.walkBoth(const Duration(milliseconds: 320), light);
      rig
        ..temp(FootSide.left, 31.0 + over, 30)
        ..temp(FootSide.right, 31.0, 30, quality: TempQuality.poorContact);
      expect(rig.engine.overCount(TempSite.forefoot), 0);
    });

    test('a reading missed in between keeps the run', () {
      final rig = RulesRig()..stream();
      pair(rig, 31.0, 31.0 + over);
      // The right foot's next reading is lost; the left sends two.
      rig.walkBoth(const Duration(milliseconds: 320), light);
      rig.temp(FootSide.left, 31.0, 30);
      rig.walkBoth(const Duration(milliseconds: 320), light);
      rig
        ..temp(FootSide.left, 31.0, 30)
        ..temp(FootSide.right, 31.0 + over, 30);
      expect(rig.engine.overCount(TempSite.forefoot), 2);
      expect(rig.view().status.level, PatientLevel.rest);
    });
  });

  group('BATTERY_LOW (level 1)', () {
    test('below lowPct, not at it; the card does not change', () async {
      final rig = RulesRig()..stream();
      rig.left.status(battery: t.batteryLowPct.toInt());
      rig.walkBoth(const Duration(seconds: 1), light);
      expect(codes(rig), isNot(contains(AlertCode.batteryLow)));
      rig.left.status(battery: t.batteryLowPct.toInt() - 1);
      rig.walkBoth(const Duration(seconds: 1), light);
      expect(codes(rig), contains(AlertCode.batteryLow));
      expect(rig.view().status, PatientStatus.safe);
      final a = (await rig.stored()).single;
      expect(a.kind, AlertKind.batteryLow);
      expect(a.measuredValue, 14);
      expect(a.patientLevel, PatientLevel.safe);
      expect(
        await rig.alerts
            .watchUnreadCount(rig.now().millisecondsSinceEpoch)
            .first,
        1,
        reason: 'level 1 is listed',
      );
    });
  });

  group('DEVICE_LOST (level 1)', () {
    test('no data for longer than lostAfterMin, not exactly it', () async {
      final rig = RulesRig()..stream();
      rig.left.status(battery: 43);
      rig.walkBoth(const Duration(seconds: 2), light);
      // The left goes silent (out of range); the right keeps walking.
      final lostAt = rig.now();
      final limit = Duration(minutes: t.deviceLostAfterMin);
      while (rig.now().difference(lostAt) < limit) {
        rig.run(const Duration(milliseconds: 160), right: light);
      }
      expect(rig.now().difference(lostAt), limit);
      expect(codes(rig), isNot(contains(AlertCode.deviceLost)));
      expect(rig.view().status, const PatientStatus.missing(FootSide.left));
      rig.run(const Duration(milliseconds: 160), right: light);
      final c = rig.view().conditions.firstWhere(
        (c) => c.code == AlertCode.deviceLost,
      );
      expect(c.side, FootSide.left);
      final a = (await rig.stored()).single;
      expect(a.kind, AlertKind.deviceLost);
      expect(a.patientLevel, PatientLevel.noData);
      expect(a.details!['lastBatteryPct'], 43);
      expect(a.threshold, 5);
    });

    test('not after the user\'s own Disconnect', () async {
      final rig = RulesRig()..stream();
      rig.walkBoth(const Duration(seconds: 2), light);
      await rig.left.disconnect();
      rig.run(const Duration(minutes: 6), right: light);
      expect(codes(rig), isNot(contains(AlertCode.deviceLost)));
      expect(await rig.storedKinds(), isEmpty);
    });

    test('is checked by the timer too, with no data arriving', () async {
      final rig = RulesRig()..stream();
      rig.walkBoth(const Duration(seconds: 2), light);
      rig.pause(const Duration(minutes: 7));
      expect(await rig.storedKinds(), [
        AlertKind.deviceLost,
        AlertKind.deviceLost,
      ]);
      expect(rig.view().status, PatientStatus.noData);
    });
  });

  group('repeat suppression (contract §8.5)', () {
    Future<void> peakEpisode(RulesRig rig, {int channel = 1}) async {
      rig.walkBoth(
        const Duration(seconds: 2),
        Gait(kpa: at(channel, t.alertKpa + 40)),
        right: light,
      );
      // The walk stops long enough for the rule to end.
      final sit = Gait.standing(at(5, 30));
      rig.run(
        Duration(milliseconds: t.peakHoldMs + 500),
        left: sit,
        right: sit,
      );
      await rig.stored();
    }

    int peaks(List<StoredAlert> all) =>
        all.where((a) => a.kind == AlertKind.pressurePeak).length;

    test(
      'same code + side + zone once per repeatMin; exactly then again',
      () async {
        final rig = RulesRig()..stream();
        final first = rig.now();
        await peakEpisode(rig);
        expect(peaks(await rig.stored()), 1);
        await peakEpisode(rig);
        expect(peaks(await rig.stored()), 1, reason: 'within repeatMin');
        // Wait until exactly repeatMin after the first one was raised.
        final raised = (await rig.stored())
            .firstWhere((a) => a.kind == AlertKind.pressurePeak)
            .atMs;
        expect(raised, greaterThan(first.millisecondsSinceEpoch));
        final repeat = Duration(minutes: t.repeatMin).inMilliseconds;
        final sit = Gait.standing(at(5, 30));
        // Stand until 1.5 s before; the next episode starts within a
        // packet of exactly repeatMin. Then check both sides of it.
        while (rig.now().millisecondsSinceEpoch < raised + repeat - 1500) {
          rig.run(const Duration(seconds: 60), left: sit, right: sit);
        }
        await peakEpisode(rig);
        final all = await rig.stored();
        final times = [
          for (final a in all)
            if (a.kind == AlertKind.pressurePeak) a.atMs,
        ];
        expect(times, hasLength(2));
        expect(times.last - times.first, greaterThanOrEqualTo(repeat));
      },
    );

    test(
      'exactly repeatMin after is allowed; one packet before is not',
      () async {
        final repeat = Duration(minutes: t.repeatMin).inMilliseconds;
        final sit = Gait.standing(at(5, 30));
        const walkLight = Gait(
          strideMs: 1000,
          stanceMs: 1000,
          kpa: [
            20, 20, 20, 20, 20, 20, //
          ],
        );

        /// Raises PRESSURE_PEAK again so that it starts to hold exactly at
        /// [offsetMs] after repeatMin from the first one (packets come every
        /// 160 ms on a grid, so the offset is a multiple of 160).
        Future<List<int>> again(int offsetMs) async {
          final rig = RulesRig()..stream();
          await peakEpisode(rig);
          final raised = (await rig.stored())
              .firstWhere((a) => a.kind == AlertKind.pressurePeak)
              .atMs;
          final target = raised + repeat + offsetMs;
          // Stand, then walk lightly long enough for the gate to open.
          while (rig.now().millisecondsSinceEpoch < target - 1280) {
            rig.run(const Duration(milliseconds: 160), left: sit, right: sit);
          }
          while (rig.now().millisecondsSinceEpoch < target - 160) {
            rig.walkBoth(const Duration(milliseconds: 160), walkLight);
          }
          expect(target - rig.now().millisecondsSinceEpoch, 160);
          rig.walkBoth(
            const Duration(milliseconds: 160),
            Gait(strideMs: 1000, stanceMs: 1000, kpa: at(1, t.alertKpa + 40)),
            right: walkLight,
          );
          expect(rig.now().millisecondsSinceEpoch, target);
          return [
            for (final a in await rig.stored())
              if (a.kind == AlertKind.pressurePeak) a.atMs - raised,
          ];
        }

        expect(await again(0), [0, repeat]);
        expect(await again(-160), [0], reason: 'still within repeatMin');
      },
    );

    test('a different zone is a different alert', () async {
      final rig = RulesRig()..stream();
      await peakEpisode(rig, channel: 1);
      await peakEpisode(rig, channel: 5);
      final zones = [
        for (final a in await rig.stored())
          if (a.kind == AlertKind.pressurePeak) a.zone,
      ];
      expect(zones, ['meta1', 'heel']);
    });

    test(
      'holds across an app restart (memory from the alerts table)',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final rig = RulesRig(db: db)..stream();
        await peakEpisode(rig);
        expect(peaks(await rig.stored()), 1);
        // Restart: a new engine on the same database.
        rig.engine.stop();
        rig.engine = rig.newEngine();
        await peakEpisode(rig);
        expect(peaks(await rig.stored()), 1);
        // A restart 31 minutes on raises it again.
        rig.engine.stop();
        rig.pause(Duration(minutes: t.repeatMin + 1));
        rig.engine = rig.newEngine();
        await peakEpisode(rig);
        expect(peaks(await rig.stored()), 2);
      },
    );
  });

  group('status: level max and the 3-level mapping (FLUTTER-PLAN §7)', () {
    test('every row of the table', () {
      // patientLevelFor: the level column.
      expect(patientLevelFor(1), isNull);
      expect(patientLevelFor(2), isNull);
      expect(patientLevelFor(3), PatientLevel.careful);
      expect(patientLevelFor(4), PatientLevel.rest);
      expect(patientLevelFor(5), PatientLevel.rest, reason: 'synthetic 5');
      for (final code in AlertCode.values) {
        final cause = StatusCause(code: code, side: FootSide.left);
        if (code.level >= 4) {
          expect(PatientStatus.from(cause).level, PatientLevel.rest);
        } else if (code.level == 3) {
          expect(PatientStatus.from(cause).level, PatientLevel.careful);
        } else {
          expect(() => PatientStatus.from(cause), throwsArgumentError);
        }
      }
      expect(AlertCode.values, hasLength(8));
    });

    test('no rule → Safe; level 2 → Safe; level 3 → Be careful', () {
      final rig = RulesRig()..stream();
      rig.walkBoth(const Duration(seconds: 2), light);
      expect(rig.view().status, PatientStatus.safe);
      rig.walkBoth(const Duration(seconds: 2), Gait(kpa: at(1, 120)));
      expect(rig.view().status, PatientStatus.safe);
      rig.walkBoth(const Duration(seconds: 2), Gait(kpa: at(1, 240)));
      expect(rig.view().status.level, PatientLevel.careful);
    });

    test('level 4 wins over level 3; PTI names the status before PEAK', () {
      final rig = RulesRig()..stream();
      final g = Gait(strideMs: 1700, stanceMs: 1260, kpa: at(1, 240));
      rig.walkBoth(strides(25, g), g);
      final rules = rig.view();
      expect(
        rules.conditions.map((c) => c.code),
        containsAll([AlertCode.pressurePeak, AlertCode.pressurePti]),
      );
      expect(rules.status.cause!.code, AlertCode.pressurePti);
      rig
        ..temp(FootSide.left, 34, 30)
        ..temp(FootSide.right, 31, 30);
      rig.walkBoth(const Duration(milliseconds: 320), g);
      rig
        ..temp(FootSide.left, 34, 30)
        ..temp(FootSide.right, 31, 30);
      expect(rig.view().status.level, PatientLevel.rest);
      expect(rig.view().status.cause!.code, AlertCode.tempDelta);
    });

    test('the same code on both feet: the one further past its threshold', () {
      final rig = RulesRig()..stream();
      rig.run(
        const Duration(seconds: 3),
        left: Gait(kpa: at(1, 230)),
        right: Gait(kpa: at(5, 260), phaseMs: 500),
      );
      expect(rig.view().status.cause!.side, FootSide.right);
    });
  });

  group('one foot missing (BACKLOG 38)', () {
    test('the connected foot\'s level 3 wins over No data', () {
      final rig = RulesRig()..stream([FootSide.left]);
      rig.run(const Duration(seconds: 3), left: Gait(kpa: at(1, 240)));
      final s = rig.view().status;
      expect(s.level, PatientLevel.careful);
      expect(s.cause!.side, FootSide.left);
    });

    test('otherwise No data, naming the missing foot', () {
      final rig = RulesRig()..stream([FootSide.left]);
      rig.run(const Duration(seconds: 3), left: light);
      expect(rig.view().status, const PatientStatus.missing(FootSide.right));
      expect(rig.view().status.level, PatientLevel.noData);
    });

    test('neither foot: plain No data', () {
      final rig = RulesRig();
      expect(rig.view().status, PatientStatus.noData);
    });
  });

  group('gait hook (contract §8.3.1)', () {
    test('the estimate is stored with pressure alerts only, and never '
        'changes the level', () async {
      final rig = RulesRig(
        gait: (side) =>
            const GaitEstimate(gaitClass: 'toe_walking', confidence: 0.78),
      )..stream();
      rig.walkBoth(
        const Duration(seconds: 3),
        Gait(kpa: at(1, 240)),
        right: light,
      );
      rig.left.status(battery: 10);
      rig.walkBoth(const Duration(seconds: 1), light);
      final all = await rig.stored();
      final peak = all.firstWhere((a) => a.kind == AlertKind.pressurePeak);
      expect((peak.gaitClass, peak.gaitConfidence), ('toe_walking', 0.78));
      expect(peak.level, 3);
      final battery = all.firstWhere((a) => a.kind == AlertKind.batteryLow);
      expect(battery.gaitClass, isNull);
    });

    test('a note only above minConfidence and for a matching zone', () {
      String? note(
        String cls,
        double conf,
        String zone, [
        AlertCode code = AlertCode.pressurePeak,
      ]) => gaitNoteTh(
        code: code,
        zoneId: zone,
        gaitClass: cls,
        confidence: conf,
        thresholds: t,
      );
      final min = t.minConfidence;
      expect(note('toe_walking', min, 'meta1'), contains('เขย่งปลายเท้า'));
      expect(note('toe_walking', min - 0.01, 'meta1'), isNull);
      expect(note('toe_walking', 0.9, 'heel'), isNull, reason: 'zone');
      expect(note('heel_walking', 0.9, 'heel'), contains('ลงส้น'));
      expect(note('antalgic', 0.9, 'meta5'), contains('ไม่สมมาตร'));
      expect(note('normal', 0.9, 'meta1'), isNull);
      expect(
        note('rotated_foot', 0.9, 'midfoot'),
        isNull,
        reason: 'no in/out direction (BACKLOG 41)',
      );
      expect(note('toe_walking', 0.9, 'meta1', AlertCode.tempDelta), isNull);
    });
  });

  group('research capture tag (BACKLOG 40)', () {
    test('alerts raised while a capture is open carry its stamp', () async {
      String? stamp = '20261110-093000';
      final rig = RulesRig(capture: () => stamp)..stream();
      rig.walkBoth(
        const Duration(seconds: 2),
        Gait(kpa: at(1, 240)),
        right: light,
      );
      await rig.stored();
      stamp = null;
      rig.left.status(battery: 10);
      rig.walkBoth(const Duration(seconds: 1), light);
      final all = await rig.stored();
      expect(
        all.firstWhere((a) => a.kind == AlertKind.pressurePeak).captureStamp,
        '20261110-093000',
      );
      expect(
        all.firstWhere((a) => a.kind == AlertKind.batteryLow).captureStamp,
        isNull,
      );
      expect(await rig.alerts.forCapture('20261110-093000'), isNotEmpty);
    });
  });

  test('zone ids come from the foot layout', () {
    expect(footLayout.zones.map((z) => z.id), [
      'hallux',
      'meta1',
      'meta3',
      'meta5',
      'midfoot',
      'heel',
    ]);
    expect(zero, hasLength(footLayout.zones.length));
  });
}

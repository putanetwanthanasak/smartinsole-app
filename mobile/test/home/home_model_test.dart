import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_engine.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/rules/pressure_level.dart';
import 'package:smartinsole/ui/screens/home/home_copy.dart';
import 'package:smartinsole/ui/screens/home/home_model.dart';

import '../device/fake_source.dart';
import '../helpers/pump_app.dart';

const safeRules = RulesView(status: PatientStatus.safe, conditions: []);

void main() {
  test('the pressure caption comes from the live dot levels, not the '
      'status', () {
    fakeAsync((async) {
      final now = async.getClock(DateTime(2026, 10, 23, 9)).now;
      final left = FakeSource(FootSide.left, now: now);
      final right = FakeSource(FootSide.right, now: now);
      final manager = DeviceManager(left: left, right: right, now: now);
      final high = testThresholds.alertKpa + 40;
      left
        ..stream()
        ..packet(
          sample: (i, ms) => SensorSample(
            deviceMs: ms,
            fsrAdc: List.filled(6, 1000),
            fsrKpa: [10, high, 10, 10, 10, 10],
            accelG: const [0, 0, 1],
            gyroDps: const [0, 0, 0],
          ),
        );
      right
        ..stream()
        ..packet();
      async.flushMicrotasks();

      // No rule set a level 3 here: the status is Safe, with no mock.
      final v = homeViewOf(
        manager.snapshot(),
        thresholds: testThresholds,
        rules: safeRules,
        channelPeaks: const {},
        meanLoads: const {},
      );
      expect(v.leftMap.levels![1], PressureLevel.high);
      expect(mapCaption(v.leftMap, v.rightMap), (
        'ปลายเท้าซ้ายรับน้ำหนักมาก',
        true,
      ));
      expect(mapLabel(v.leftMap), 'เท้าซ้าย ปลายเท้ารับน้ำหนักมาก');
      expect(mapLabel(v.rightMap), 'เท้าขวา แรงกดกระจายดี');
    });
  });

  test('balance: weight share of the mean loads, note above peakPct', () {
    fakeAsync((async) {
      final now = async.getClock(DateTime(2026, 10, 23, 9)).now;
      final left = FakeSource(FootSide.left, now: now);
      final right = FakeSource(FootSide.right, now: now);
      final manager = DeviceManager(left: left, right: right, now: now);
      left
        ..stream()
        ..packet();
      right
        ..stream()
        ..packet();
      async.flushMicrotasks();
      HomeView view(double l, double r) => homeViewOf(
        manager.snapshot(),
        thresholds: testThresholds,
        rules: safeRules,
        channelPeaks: const {},
        meanLoads: {FootSide.left: l, FootSide.right: r},
      );
      expect(view(300, 200).leftSharePct, 60);
      expect(view(300, 200).heavierSide, FootSide.left);
      expect(balanceNote(view(300, 200)), 'ลงน้ำหนักเท้าซ้ายมากกว่า');
      expect(balanceNote(view(205, 195)), 'ซ้ายและขวาพอ ๆ กัน');
      expect(balanceNote(view(100, 160)), 'ลงน้ำหนักเท้าขวามากกว่า');
      // The number holds within 1 point of what is shown, then moves.
      HomeView shown(double l, int was) => homeViewOf(
        manager.snapshot(),
        thresholds: testThresholds,
        rules: safeRules,
        channelPeaks: const {},
        meanLoads: {FootSide.left: l, FootSide.right: 100 - l},
        shownSharePct: was,
      );
      expect(shown(50.9, 50).leftSharePct, 50);
      expect(shown(49.2, 50).leftSharePct, 50);
      expect(shown(48.8, 50).leftSharePct, 49);
      expect(shown(53.4, 50).leftSharePct, 53);

      // ASYMMETRY_PEAK names its own foot, even when the weight share
      // says the other one or nothing (BACKLOG 37).
      HomeView asym(double l, double r) => homeViewOf(
        manager.snapshot(),
        thresholds: testThresholds,
        rules: const RulesView(
          status: PatientStatus.safe,
          conditions: [
            AlertCondition(
              code: AlertCode.asymmetryPeak,
              side: FootSide.right,
              value: 30,
              threshold: 15,
            ),
          ],
        ),
        channelPeaks: const {},
        meanLoads: {FootSide.left: l, FootSide.right: r},
      );
      expect(asym(205, 195).asymmetrySide, FootSide.right);
      expect(balanceNote(asym(205, 195)), 'ลงน้ำหนักเท้าขวามากกว่า');
      expect(balanceNote(asym(300, 200)), 'ลงน้ำหนักเท้าขวามากกว่า');
      expect(view(300, 200).asymmetrySide, isNull);
    });
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/interim_status.dart';
import 'package:smartinsole/rules/patient_status.dart';

import '../device/fake_source.dart';
import '../helpers/pump_app.dart';

class Rig {
  Rig(this.async, {MockPreset? preset}) {
    now = async.getClock(DateTime(2026, 10, 23, 9)).now;
    left = FakeSource(FootSide.left, now: now);
    right = FakeSource(FootSide.right, now: now);
    manager = DeviceManager(left: left, right: right, now: now);
    status = InterimStatus(
      manager: manager,
      thresholds: testThresholds,
      mockPreset: preset == null ? null : () => preset,
    );
  }

  final FakeAsync async;
  late final DateTime Function() now;
  late final FakeSource left;
  late final FakeSource right;
  late final DeviceManager manager;
  late final InterimStatus status;

  PatientStatus get current => status.status(manager.snapshot());

  void streamBoth() {
    left
      ..stream()
      ..packet();
    right
      ..stream()
      ..packet();
    async.flushMicrotasks();
  }

  /// One temperature reading pair (left, right forefoot; heels equal).
  void pair(double l, double r) {
    left
      ..packet()
      ..temp(l, 30);
    right
      ..packet()
      ..temp(r, 30);
    async.flushMicrotasks();
  }
}

void main() {
  final over = testThresholds.deltaC + 0.4;

  test('No data unless both feet are usable (D7; S7 refines, BACKLOG 38)', () {
    fakeAsync((async) {
      final rig = Rig(async);
      expect(rig.current, PatientStatus.noData);
      rig.left
        ..stream()
        ..packet();
      async.flushMicrotasks();
      expect(rig.current, PatientStatus.noData);
      rig.right
        ..stream()
        ..packet();
      async.flushMicrotasks();
      expect(rig.current, PatientStatus.safe);
    });
  });

  test('TEMP_DELTA needs consecutiveReadings pairs above deltaC (rule 6)', () {
    fakeAsync((async) {
      final rig = Rig(async)..streamBoth();
      rig.pair(31.0, 31.0 + over);
      expect(rig.status.overCount(TempSite.forefoot), 1);
      expect(rig.current.level, PatientLevel.safe);
      rig.pair(31.0, 31.0 + over);
      final s = rig.current;
      expect(s.level, PatientLevel.rest);
      expect(s.cause!.code, AlertCode.tempDelta);
      expect(s.cause!.side, FootSide.right, reason: 'the warmer foot');
      expect(s.cause!.site, TempSite.forefoot);
      expect(s.cause!.deltaC, closeTo(over, 1e-9));
    });
  });

  test('a reading at or below deltaC resets the count', () {
    fakeAsync((async) {
      final rig = Rig(async)..streamBoth();
      rig.pair(31.0 + over, 31.0);
      rig.pair(31.0 + testThresholds.deltaC, 31.0); // not above
      rig.pair(31.0 + over, 31.0);
      expect(rig.current.level, PatientLevel.safe);
      rig.pair(31.0 + over, 31.0);
      expect(rig.current.level, PatientLevel.rest);
      expect(rig.current.cause!.side, FootSide.left);
    });
  });

  test('one foot reading twice is not a pair', () {
    fakeAsync((async) {
      final rig = Rig(async)..streamBoth();
      rig.right.temp(31.0 + over, 30);
      rig.left.temp(31.0, 30);
      rig.left.temp(31.0, 30);
      async.flushMicrotasks();
      expect(rig.status.overCount(TempSite.forefoot), 1);
    });
  });

  test('a mock preset supplies only its level-3 scenario', () {
    fakeAsync((async) {
      final rig = Rig(async, preset: MockPreset.watch)..streamBoth();
      final s = rig.current;
      expect(s.level, PatientLevel.careful);
      expect(s.cause!.code, AlertCode.pressurePti);
      expect(s.cause!.side, FootSide.left);
      // Never over a missing foot.
      final rig2 = Rig(async, preset: MockPreset.watch);
      expect(rig2.current, PatientStatus.noData);
    });
  });

  test('level mapping: 3 → Be careful, 4 → Rest; 1–2 never set the card', () {
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
}

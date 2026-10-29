import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/models.dart';

import 'storage_rig.dart';

void main() {
  final now = bkk(2026, 10, 24, 14, 32);

  test('an alert reads back with every field', () async {
    final rig = StorageRig();
    final id = await rig.alerts.add(
      NewAlert(
        kind: AlertKind.tempDelta,
        patientLevel: PatientLevel.rest,
        atMs: now,
        side: FootSide.right,
        zone: 'heel',
        measuredValue: 2.6,
        threshold: 2.2,
        gaitClass: 'normal',
        gaitConfidence: 0.78,
        details: {'leftC': 31.4, 'rightC': 34.0, 'consecutive': 3},
        captureStamp: '20261110-093000',
      ),
    );
    final a = (await rig.alerts.byId(id))!;
    expect(a.kind, AlertKind.tempDelta);
    expect(a.level, 4, reason: 'level comes from the code');
    expect(a.patientLevel, PatientLevel.rest);
    expect(a.atMs, now);
    expect(a.localDate, '2026-10-24');
    expect(a.side, FootSide.right);
    expect(a.zone, 'heel');
    expect(a.legacySite, isNull);
    expect(a.measuredValue, 2.6);
    expect(a.threshold, 2.2);
    expect(a.gaitClass, 'normal');
    expect(a.gaitConfidence, 0.78);
    expect(a.details, {'leftC': 31.4, 'rightC': 34.0, 'consecutive': 3});
    expect(a.captureStamp, '20261110-093000');
    expect(a.isRead, isFalse);
  });

  test('codes are stored by their contract names', () async {
    final rig = StorageRig();
    await rig.alerts.add(alertOf(AlertKind.loadConcentration, now));
    final raw = await rig.db.customSelect('SELECT code FROM alerts').get();
    expect(raw.single.read<String>('code'), 'LOAD_CONCENTRATION');
  });

  test('the schema rejects a level outside 1–5', () async {
    final rig = StorageRig();
    expect(
      rig.db.customStatement(
        "INSERT INTO alerts (code, level, patient_status, at_ms, local_date) "
        "VALUES ('TEMP_DELTA', 6, 'rest', 0, '1970-01-01')",
      ),
      throwsA(anything),
    );
  });

  test('every kind has its contract level; only level 2 is hidden', () {
    expect(
      {for (final k in AlertKind.values) k.wireName: k.level},
      {
        'TEMP_DELTA': 4,
        'PRESSURE_WATCH': 2,
        'PRESSURE_PEAK': 3,
        'PRESSURE_PTI': 3,
        'ASYMMETRY_PEAK': 2,
        'LOAD_CONCENTRATION': 3,
        'DEVICE_LOST': 1,
        'BATTERY_LOW': 1,
        'FOOT_CHECK_FINDING': 3,
      },
    );
    expect(
      [
        for (final k in AlertKind.values)
          if (!k.patientVisible) k,
      ],
      [AlertKind.pressureWatch, AlertKind.asymmetryPeak],
    );
  });

  group('read state (decision 7)', () {
    test('mark-as-read keeps the first time', () async {
      final rig = StorageRig();
      final id = await rig.alerts.add(alertOf(AlertKind.pressurePeak, now));
      await rig.alerts.markRead(id, now + 1000);
      await rig.alerts.markRead(id, now + 5000);
      expect((await rig.alerts.byId(id))!.readAtMs, now + 1000);
    });

    test('unread count is 0 on an empty table', () async {
      final rig = StorageRig();
      expect(await rig.alerts.watchUnreadCount(now).first, 0);
    });

    test('unread count drops when one is opened', () async {
      final rig = StorageRig();
      final a = await rig.alerts.add(alertOf(AlertKind.pressurePeak, now));
      await rig.alerts.add(alertOf(AlertKind.deviceLost, now + 1));
      expect(await rig.alerts.watchUnreadCount(now + 2).first, 2);
      await rig.alerts.markRead(a, now + 3);
      expect(await rig.alerts.watchUnreadCount(now + 4).first, 1);
    });

    test('the count stream updates on insert', () async {
      final rig = StorageRig();
      final counts = rig.alerts.watchUnreadCount(now);
      final seen = <int>[];
      final sub = counts.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await rig.alerts.add(alertOf(AlertKind.tempDelta, now - 1));
      await pumpEventQueue();
      expect(seen, [0, 1]);
    });
  });

  group('visibility: list and badge share one rule', () {
    test('level-2 events are stored but never listed or counted', () async {
      final rig = StorageRig();
      await rig.alerts.add(alertOf(AlertKind.pressureWatch, now));
      await rig.alerts.add(alertOf(AlertKind.asymmetryPeak, now));
      expect(await rig.alerts.watchVisible(now).first, isEmpty);
      expect(await rig.alerts.watchUnreadCount(now).first, 0);
      final all = await rig.db.select(rig.db.alerts).get();
      expect(all, hasLength(2));
    });

    test(
      'for every kind and age, the count equals the unread listed',
      () async {
        final rig = StorageRig();
        const day = 24 * 3600 * 1000;
        for (final k in AlertKind.values) {
          for (final age in [0, 29 * day, 30 * day, 30 * day + 1, 40 * day]) {
            await rig.alerts.add(
              alertOf(k, now - age, captureStamp: '20261110-093000'),
            );
          }
        }
        final listed = await rig.alerts.watchVisible(now).first;
        final count = await rig.alerts.watchUnreadCount(now).first;
        expect(count, listed.where((a) => !a.isRead).length);
        expect(listed.every((a) => a.kind.patientVisible), isTrue);
        // 7 visible kinds × 3 ages inside the window (0, 29 d, exactly 30 d).
        expect(listed, hasLength(7 * 3));
      },
    );

    test('the list is newest first', () async {
      final rig = StorageRig();
      await rig.alerts.add(alertOf(AlertKind.deviceLost, now - 60000));
      await rig.alerts.add(alertOf(AlertKind.tempDelta, now));
      await rig.alerts.add(alertOf(AlertKind.pressurePeak, now - 30000));
      final listed = await rig.alerts.watchVisible(now).first;
      expect(listed.map((a) => a.kind), [
        AlertKind.tempDelta,
        AlertKind.pressurePeak,
        AlertKind.deviceLost,
      ]);
    });
  });

  group('research capture', () {
    test('a session id is stored as its stamp only (no subject code)', () {
      expect(captureStampOf('SI-001_20261110-093000'), '20261110-093000');
      expect(captureStampOf('TEST-07_20261024-101500'), '20261024-101500');
    });

    test(
      'a capture\'s alerts, all levels, oldest first; then delete',
      () async {
        final rig = StorageRig();
        await rig.alerts.add(
          alertOf(AlertKind.tempDelta, now, captureStamp: 'B'),
        );
        await rig.alerts.add(
          alertOf(AlertKind.pressureWatch, now - 5, captureStamp: 'B'),
        );
        await rig.alerts.add(
          alertOf(AlertKind.tempDelta, now, captureStamp: 'A'),
        );
        await rig.alerts.add(alertOf(AlertKind.deviceLost, now));
        final b = await rig.alerts.forCapture('B');
        expect(b.map((a) => a.kind), [
          AlertKind.pressureWatch,
          AlertKind.tempDelta,
        ]);
        expect(await rig.alerts.deleteForCapture('B'), 2);
        expect(await rig.alerts.forCapture('B'), isEmpty);
        expect(await rig.alerts.forCapture('A'), hasLength(1));
      },
    );
  });

  group('appendTempSite (sites that qualify during suppression)', () {
    TempSiteEntry entry(String zone, double d, int at) =>
        TempSiteEntry(zone: zone, deltaC: d, atMs: at);
    Future<int> tempAlert(StorageRig rig, {Map<String, Object?>? details}) =>
        rig.alerts.add(
          NewAlert(
            kind: AlertKind.tempDelta,
            patientLevel: PatientLevel.rest,
            atMs: now,
            side: FootSide.right,
            zone: 'heel',
            measuredValue: 2.6,
            threshold: 2.2,
            details:
                details ??
                {
                  'consecutive': 2,
                  TempSiteEntry.listKey: [entry('heel', 2.6, now).toJson()],
                },
          ),
        );

    test('a new site is added after the listed ones', () async {
      final rig = StorageRig();
      final id = await tempAlert(rig);
      expect(
        await rig.alerts.appendTempSite(id, entry('lateralHeel', 2.3, now + 1)),
        isTrue,
      );
      final a = (await rig.alerts.byId(id))!;
      expect(TempSiteEntry.listOf(a.details).map((e) => e.zone), [
        'heel',
        'lateralHeel',
      ]);
      expect(TempSiteEntry.listOf(a.details).last.atMs, now + 1);
      expect(a.details!['consecutive'], 2, reason: 'other details kept');
      expect(a.zone, 'heel', reason: 'the named site does not change');
      expect(a.measuredValue, 2.6);
    });

    test('a listed site is never added twice', () async {
      final rig = StorageRig();
      final id = await tempAlert(rig);
      expect(
        await rig.alerts.appendTempSite(id, entry('heel', 2.9, now + 1)),
        isFalse,
      );
      final a = (await rig.alerts.byId(id))!;
      expect(TempSiteEntry.listOf(a.details), hasLength(1));
      expect(TempSiteEntry.listOf(a.details).single.deltaC, 2.6);
    });

    test('refused for a missing row, another code, or an alert stored '
        'before the 8 sites', () async {
      final rig = StorageRig();
      final e = entry('meta1', 2.4, now);
      expect(await rig.alerts.appendTempSite(999, e), isFalse);
      final pressure = await rig.alerts.add(
        alertOf(AlertKind.pressurePeak, now),
      );
      expect(await rig.alerts.appendTempSite(pressure, e), isFalse);
      final legacy = await tempAlert(
        rig,
        details: {'consecutive': 2, 'otherSiteDeltaC': 0.4},
      );
      expect(await rig.alerts.appendTempSite(legacy, e), isFalse);
      expect((await rig.alerts.byId(legacy))!.details, {
        'consecutive': 2,
        'otherSiteDeltaC': 0.4,
      });
    });
  });

  test('every alert is counted in its day\'s summary by level', () async {
    final rig = StorageRig();
    await rig.alerts.add(alertOf(AlertKind.tempDelta, now));
    await rig.alerts.add(alertOf(AlertKind.pressureWatch, now));
    await rig.alerts.add(alertOf(AlertKind.pressurePeak, now));
    await rig.alerts.add(alertOf(AlertKind.pressurePti, now));
    await rig.alerts.add(alertOf(AlertKind.batteryLow, now));
    final s = (await rig.summaries.get('2026-10-24'))!;
    expect(s.alertsByLevel, [1, 1, 2, 1, 0]);
  });
}

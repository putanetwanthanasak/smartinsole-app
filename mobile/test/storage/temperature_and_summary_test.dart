import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/temperature_repository.dart';

import 'storage_rig.dart';

void main() {
  final t0 = bkk(2026, 10, 24, 14, 0);

  group('temperature readings', () {
    Future<void> add(StorageRig rig, FootSide side, int atMs) =>
        addReading(rig.temperatures, side, atMs);

    test('a reading reads back with every site and field', () async {
      final rig = StorageRig();
      await rig.temperatures.add(
        side: FootSide.left,
        atMs: t0,
        celsius: [for (var i = 0; i < 8; i++) i == 2 ? null : 30 + i / 10],
        quality: sitesQ(TempQuality.normal, {
          2: TempQuality.sensorFault,
          6: TempQuality.poorContact,
        }),
        timeFromArrival: true,
      );
      final r = (await rig.temperatures.latest(FootSide.left))!;
      expect(r.atMs, t0);
      expect(r.localDate, '2026-10-24');
      expect(r.side, FootSide.left);
      expect(r.siteC, [30.0, 30.1, null, 30.3, 30.4, 30.5, 30.6, 30.7]);
      expect(r.siteQuality[2], TempQuality.sensorFault);
      expect(r.siteQuality[6], TempQuality.poorContact);
      expect(r.quality, TempQuality.sensorFault, reason: 'the worst site');
      expect(r.isLegacy, isFalse);
      expect(r.usableC(0), 30.0);
      expect(r.usableC(2), isNull, reason: 'could not read (-32768)');
      expect(r.usableC(6), isNull, reason: 'poor contact is not a value');
      expect(r.legacyForefootC, isNull);
      expect(r.timeFromArrival, isTrue);
      expect(await rig.temperatures.latest(FootSide.right), isNull);
    });

    test('the row quality is the worst site\'s', () {
      expect(worstQuality(sitesQ()), TempQuality.normal);
      expect(
        worstQuality(sitesQ(TempQuality.normal, {7: TempQuality.poorContact})),
        TempQuality.poorContact,
      );
      expect(
        worstQuality(
          sitesQ(TempQuality.poorContact, {0: TempQuality.sensorFault}),
        ),
        TempQuality.sensorFault,
      );
    });

    test('the day query keeps both feet, oldest first, and leaves '
        'connection gaps as gaps between rows', () async {
      final rig = StorageRig();
      for (var i = 0; i < 4; i++) {
        await add(rig, FootSide.left, t0 + i * 30000);
        await add(rig, FootSide.right, t0 + i * 30000 + 5);
      }
      // Right drops for 10 minutes, then comes back.
      await add(rig, FootSide.right, t0 + 13 * 60000);
      await add(rig, FootSide.left, bkk(2026, 10, 25, 0, 0, 10));
      final day = await rig.temperatures.watchDay('2026-10-24').first;
      expect(day, hasLength(9));
      expect(
        day.map((r) => r.atMs).toList(),
        [for (final r in day) r.atMs]..sort(),
      );
      final right = day.where((r) => r.side == FootSide.right).toList();
      expect(
        right.last.atMs - right[right.length - 2].atMs,
        greaterThan(5 * 60000),
      );
    });

    test('between filters by time and side', () async {
      final rig = StorageRig();
      for (var i = 0; i < 6; i++) {
        await add(rig, FootSide.values[i % 2], t0 + i * 30000);
      }
      final mid = await rig.temperatures.between(t0 + 30000, t0 + 120000);
      expect(mid, hasLength(4));
      final left = await rig.temperatures.between(
        t0,
        t0 + 150000,
        side: FootSide.left,
      );
      expect(left.map((r) => r.side).toSet(), {FootSide.left});
      expect(left, hasLength(3));
    });

    test('stats count rows per foot with the newest time', () async {
      final rig = StorageRig();
      expect((await rig.temperatures.watchStats().first).count, isEmpty);
      await add(rig, FootSide.left, t0);
      await add(rig, FootSide.left, t0 + 30000);
      await add(rig, FootSide.right, t0 + 1000);
      final s = await rig.temperatures.watchStats().first;
      expect(s.count, {FootSide.left: 2, FootSide.right: 1});
      expect(s.latestMs, {
        FootSide.left: t0 + 30000,
        FootSide.right: t0 + 1000,
      });
    });
  });

  group('daily summary', () {
    test('a day with nothing has no row', () async {
      final rig = StorageRig();
      expect(await rig.summaries.get('2026-10-24'), isNull);
    });

    test('max ΔT keeps the day\'s largest |ΔT| of the 8 sites and its '
        'site; nulls never win', () async {
      final rig = StorageRig();
      List<double?> d(Map<int, double> at) => sitesC(null, at);
      await rig.summaries.recordDelta(t0, d({1: -0.4}));
      var s = (await rig.summaries.get('2026-10-24'))!;
      expect(s.maxDeltaC, 0.4);
      expect(s.maxDeltaSite, 1);
      await rig.summaries.recordDelta(t0 + 1, d({1: 0.2, 5: -2.6, 7: 2.3}));
      await rig.summaries.recordDelta(t0 + 2, d({7: 1.0}));
      await rig.summaries.recordDelta(t0 + 3, sitesC(null));
      s = (await rig.summaries.get('2026-10-24'))!;
      expect(s.maxDeltaC, 2.6);
      expect(s.maxDeltaSite, 5, reason: 'the site moves with the value');
      expect(s.legacyMaxDeltaForefootC, isNull);
      expect(s.legacyMaxDeltaHeelC, isNull);
      expect(s.steps, isNull, reason: 'S8A fills activity');
      expect(s.alertsByLevel, [0, 0, 0, 0, 0]);
      expect(s.footCheckDone, isFalse);
    });

    test('activity sets only the fields given', () async {
      final rig = StorageRig();
      await rig.summaries.setActivity('2026-10-24', t0, steps: 2340);
      await rig.summaries.setActivity('2026-10-24', t0 + 1, wornMin: 95);
      final s = (await rig.summaries.get('2026-10-24'))!;
      expect(s.steps, 2340);
      expect(s.wornMin, 95);
      expect(s.walkingMin, isNull);
    });

    test('range is inclusive and oldest first', () async {
      final rig = StorageRig();
      for (final d in [26, 22, 24, 21]) {
        await rig.summaries.setActivity('2026-10-$d', t0, steps: d);
      }
      final r = await rig.summaries.range('2026-10-22', '2026-10-26');
      expect(r.map((s) => s.localDate), [
        '2026-10-22',
        '2026-10-24',
        '2026-10-26',
      ]);
    });

    test('watch follows changes', () async {
      final rig = StorageRig();
      final seen = <int?>[];
      final sub = rig.summaries
          .watch('2026-10-24')
          .listen((s) => seen.add(s?.steps));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await rig.summaries.setActivity('2026-10-24', t0, steps: 10);
      await pumpEventQueue();
      expect(seen, [null, 10]);
    });
  });
}

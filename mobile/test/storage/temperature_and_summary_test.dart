import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';

import 'storage_rig.dart';

void main() {
  final t0 = bkk(2026, 10, 24, 14, 0);

  group('temperature readings', () {
    Future<void> add(
      StorageRig rig,
      FootSide side,
      int atMs, {
      double? forefoot = 30.8,
      double? heel = 31.4,
      TempQuality quality = TempQuality.normal,
      bool fromArrival = false,
    }) => rig.temperatures.add(
      side: side,
      atMs: atMs,
      forefootC: forefoot,
      heelC: heel,
      quality: quality,
      timeFromArrival: fromArrival,
    );

    test('a reading reads back with every field', () async {
      final rig = StorageRig();
      await add(
        rig,
        FootSide.left,
        t0,
        forefoot: null,
        heel: 31.4,
        quality: TempQuality.poorContact,
        fromArrival: true,
      );
      final r = (await rig.temperatures.latest(FootSide.left))!;
      expect(r.atMs, t0);
      expect(r.localDate, '2026-10-24');
      expect(r.side, FootSide.left);
      expect(r.forefootC, isNull, reason: 'could not read (-32768)');
      expect(r.heelC, 31.4);
      expect(r.quality, TempQuality.poorContact);
      expect(r.timeFromArrival, isTrue);
      expect(await rig.temperatures.latest(FootSide.right), isNull);
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

    test('max ΔT keeps the largest |ΔT| per site, nulls never win', () async {
      final rig = StorageRig();
      await rig.summaries.recordDelta(t0, forefootC: -0.4);
      var s = (await rig.summaries.get('2026-10-24'))!;
      expect(s.maxDeltaForefootC, 0.4);
      expect(s.maxDeltaHeelC, isNull);
      await rig.summaries.recordDelta(t0 + 1, forefootC: 0.2, heelC: -2.6);
      await rig.summaries.recordDelta(t0 + 2, heelC: 1.0);
      await rig.summaries.recordDelta(t0 + 3, forefootC: null, heelC: null);
      s = (await rig.summaries.get('2026-10-24'))!;
      expect(s.maxDeltaForefootC, 0.4);
      expect(s.maxDeltaHeelC, 2.6);
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

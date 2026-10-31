import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/local_date.dart';
import 'package:smartinsole/storage/models.dart';

import 'storage_rig.dart';

void main() {
  test('Bangkok midnight is 17:00 UTC', () {
    final last = DateTime.utc(2026, 10, 24, 16, 59, 59, 999);
    final first = DateTime.utc(2026, 10, 24, 17);
    expect(bangkok.of(last.millisecondsSinceEpoch), '2026-10-24');
    expect(bangkok.of(first.millisecondsSinceEpoch), '2026-10-25');
    expect(bkk(2026, 10, 25), first.millisecondsSinceEpoch);
  });

  test('the device default matches the phone\'s own calendar', () {
    const dates = LocalDates();
    for (final ms in [0, 1761300000000, bkk(2026, 12, 31, 23, 59, 59, 999)]) {
      final local = DateTime.fromMillisecondsSinceEpoch(ms);
      final want =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      expect(dates.of(ms), want);
    }
  });

  test('a changing offset is taken at each moment', () {
    // A made-up zone that moves from +1 to +2 at 2026-03-29 01:00 UTC.
    final change = DateTime.utc(2026, 3, 29, 1);
    final dates = LocalDates(
      (utc) => utc.isBefore(change)
          ? const Duration(hours: 1)
          : const Duration(hours: 2),
    );
    expect(
      dates.of(DateTime.utc(2026, 3, 28, 22, 59).millisecondsSinceEpoch),
      '2026-03-28',
    );
    expect(
      dates.of(DateTime.utc(2026, 3, 28, 23).millisecondsSinceEpoch),
      '2026-03-29',
    );
  });

  test('rows either side of local midnight fall on their own days', () async {
    final rig = StorageRig();
    final before = bkk(2026, 10, 24, 23, 59, 59, 999);
    final after = bkk(2026, 10, 25);
    for (final at in [before, after]) {
      await rig.alerts.add(alertOf(AlertKind.tempDelta, at));
      await rig.temperatures.add(
        side: FootSide.left,
        atMs: at,
        celsius: List.filled(8, 30),
        quality: List.filled(8, TempQuality.normal),
        timeFromArrival: false,
      );
      await rig.footChecks.save(draftOf(at));
    }
    final listed = await rig.alerts.watchVisible(after).first;
    expect(listed.map((a) => a.localDate), ['2026-10-25', '2026-10-24']);
    expect(await rig.temperatures.watchDay('2026-10-24').first, hasLength(1));
    expect(await rig.temperatures.watchDay('2026-10-25').first, hasLength(1));
    for (final d in ['2026-10-24', '2026-10-25']) {
      final s = (await rig.summaries.get(d))!;
      expect(s.alertsByLevel[3], 1, reason: d);
      expect(s.footCheckDone, isTrue);
      expect((await rig.footChecks.watchLatestOn(d).first)!.localDate, d);
    }
  });
}

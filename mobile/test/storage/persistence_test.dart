import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/daily_summary_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/temperature_repository.dart';

import 'storage_rig.dart';

void main() {
  test('data survives closing and reopening the file', () async {
    final dir = Directory.systemTemp.createTempSync('persistence_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/smartinsole.sqlite');
    final at = bkk(2026, 10, 24, 14, 32);

    var db = AppDatabase(NativeDatabase(file));
    final alertId = await DriftAlertRepository(
      db,
      bangkok,
    ).add(alertOf(AlertKind.tempDelta, at, side: FootSide.right));
    await DriftAlertRepository(db, bangkok).markRead(alertId, at + 1);
    for (var i = 0; i < 4; i++) {
      await DriftTemperatureRepository(db, bangkok).add(
        side: FootSide.values[i % 2],
        atMs: at + i * 30000,
        celsius: List.filled(8, 30.8),
        quality: List.filled(8, TempQuality.normal),
        timeFromArrival: false,
      );
    }
    await DriftFootCheckRepository(db, bangkok).save(draftOf(at));
    await DriftDailySummaryRepository(
      db,
      bangkok,
    ).recordDelta(at, [null, null, null, null, null, 2.6, null, null]);
    await db.close();
    expect(file.existsSync(), isTrue);

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final a = (await DriftAlertRepository(db, bangkok).byId(alertId))!;
    expect(
      (a.kind, a.side, a.readAtMs),
      (AlertKind.tempDelta, FootSide.right, at + 1),
    );
    final stats = await DriftTemperatureRepository(
      db,
      bangkok,
    ).watchStats().first;
    expect(stats.count, {FootSide.left: 2, FootSide.right: 2});
    expect(
      await DriftFootCheckRepository(
        db,
        bangkok,
      ).watchLatestOn('2026-10-24').first,
      isNotNull,
    );
    final s = (await DriftDailySummaryRepository(
      db,
      bangkok,
    ).get('2026-10-24'))!;
    expect((s.maxDeltaC, s.footCheckDone, s.alertsByLevel[3]), (2.6, true, 1));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/temperature_repository.dart';
import 'package:smartinsole/storage/test_data.dart';

final t0 = DateTime(2026, 10, 20, 9).millisecondsSinceEpoch;

NewAlert alertAt(int atMs, {String? stamp}) => NewAlert(
  kind: AlertKind.tempDelta,
  patientLevel: PatientLevel.rest,
  atMs: atMs,
  captureStamp: stamp,
);

void main() {
  late AppDatabase db;
  late Directory photos;
  setUp(() {
    db = AppDatabase.memory();
    photos = Directory.systemTemp.createTempSync('foot_photos_');
  });
  tearDown(() async {
    await db.close();
    if (photos.existsSync()) photos.deleteSync(recursive: true);
  });

  test(
    'clears untagged alerts and the other 3 tables; tagged alerts stay',
    () async {
      final alerts = DriftAlertRepository(db);
      await alerts.add(alertAt(t0));
      await alerts.add(alertAt(t0 + 1000, stamp: 'capture:SI-001_a'));
      await alerts.add(alertAt(t0 + 2000, stamp: 'capture:SI-002_b'));
      await DriftTemperatureRepository(db).add(
        side: FootSide.left,
        atMs: t0,
        forefootC: 31,
        heelC: 30,
        quality: TempQuality.normal,
        timeFromArrival: false,
      );
      // A finding: a foot check, its untagged alert and the day's summary.
      await DriftFootCheckRepository(db).save(
        FootCheckDraft(
          atMs: t0,
          redness: FootCheckAnswer.yesOrUnsure,
          wound: FootCheckAnswer.none,
          swelling: FootCheckAnswer.none,
          answerOnly: false,
        ),
      );
      File('${photos.path}/a.jpg').writeAsStringSync('x');
      File('${photos.path}/b.jpg').writeAsStringSync('y');

      final done = await clearTestData(db, photoDir: () async => photos);

      expect(done.alerts, 2);
      expect(done.temperatureReadings, 1);
      expect(done.dailySummaries, 1);
      expect(done.footChecks, 1);
      expect(done.photos, 2);
      final left = await alerts.since(0);
      expect(left.map((a) => a.captureStamp), [
        'capture:SI-001_a',
        'capture:SI-002_b',
      ]);
      expect(await db.select(db.temperatureReadings).get(), isEmpty);
      expect(await db.select(db.dailySummaries).get(), isEmpty);
      expect(await db.select(db.footChecks).get(), isEmpty);
      expect(photos.existsSync(), isTrue);
      expect(photos.listSync(), isEmpty);
    },
  );

  test('a missing photo folder is fine', () async {
    photos.deleteSync();
    final done = await clearTestData(db, photoDir: () async => photos);
    expect(done.photos, 0);
  });
}

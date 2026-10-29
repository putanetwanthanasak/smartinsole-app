// Migration tests. The schema dumps are drift_schemas/app_database/
// drift_schema_v1.json and drift_schema_v2.json; generated/ comes from
//   dart run drift_dev make-migrations
// (also lib/storage/database.steps.dart). After the next schemaVersion bump,
// run it again and add a vN → vN+1 data test next to the v1 → v2 one.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/daily_summary_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/temperature_repository.dart';

import '../../storage/storage_rig.dart' show bangkok, bkk;
import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a database the app creates matches the committed v2 dump', () async {
    // Catches a table change without a schema version bump and a new dump.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('v1 → v2 matches the v2 dump', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('v1 → v2 keeps every v1 row and value (S8D: nothing on the phone '
      'is deleted)', () async {
    final at = bkk(2026, 10, 28, 14, 30);
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old
        .into(old.alerts)
        .insert(
          v1.AlertsCompanion.insert(
            code: 'TEMP_DELTA',
            level: 4,
            patientStatus: 'rest',
            side: const Value('right'),
            site: const Value('heel'),
            measuredValue: const Value(2.6),
            threshold: const Value(2.2),
            details: Value(
              jsonEncode({
                'leftC': 31.4,
                'rightC': 34.0,
                'consecutive': 3,
                'otherSiteDeltaC': 0.4,
              }),
            ),
            atMs: at,
            localDate: '2026-10-28',
          ),
        );
    await old
        .into(old.alerts)
        .insert(
          v1.AlertsCompanion.insert(
            code: 'PRESSURE_PEAK',
            level: 3,
            patientStatus: 'careful',
            side: const Value('left'),
            zone: const Value('meta1'),
            measuredValue: const Value(236.5),
            details: Value(
              jsonEncode({
                'walking': true,
                'map': {
                  'left': {
                    'kpa': [20.0, 236.5, 85.0, 20.0, 20.0, 60.0],
                    'levels': ['low', 'high', 'medium', 'low', 'low', 'low'],
                  },
                  'right': null,
                },
              }),
            ),
            atMs: at + 1,
            localDate: '2026-10-28',
          ),
        );
    await old
        .into(old.temperatureReadings)
        .insert(
          v1.TemperatureReadingsCompanion.insert(
            atMs: at,
            localDate: '2026-10-28',
            side: 'left',
            forefootC: const Value(30.8),
            heelC: const Value(31.4),
            quality: 'normal',
            timeFromArrival: 0,
          ),
        );
    await old
        .into(old.dailySummary)
        .insert(
          v1.DailySummaryCompanion.insert(
            localDate: '2026-10-28',
            steps: const Value(2340),
            maxDeltaForefootC: const Value(0.4),
            maxDeltaHeelC: const Value(2.6),
            alertsL4: const Value(1),
            updatedAtMs: at,
          ),
        );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    // The old TEMP_DELTA keeps its forefoot / heel site, and no zone.
    final alerts = DriftAlertRepository(db, bangkok);
    final rows = await alerts.since(0);
    expect(rows, hasLength(2));
    final temp = rows.firstWhere((a) => a.kind == AlertKind.tempDelta);
    expect(temp.legacySite, LegacyTempSite.heel);
    expect(temp.zone, isNull);
    expect(temp.side, FootSide.right);
    expect(temp.measuredValue, 2.6);
    expect(temp.details!['otherSiteDeltaC'], 0.4);
    expect(TempSiteEntry.listOf(temp.details), isEmpty);
    // A site is never appended to an alert stored before the 8 sites.
    expect(
      await alerts.appendTempSite(
        temp.id,
        const TempSiteEntry(zone: 'meta1', deltaC: 2.4, atMs: 0),
      ),
      isFalse,
    );
    // The old pressure alert keeps its 6-zone foot map.
    final peak = rows.firstWhere((a) => a.kind == AlertKind.pressurePeak);
    expect(peak.zone, 'meta1');
    final map = peak.details!['map'] as Map;
    expect((map['left'] as Map)['kpa'], hasLength(6));

    // The old reading keeps its two values; it has no per-site values.
    final reading = (await DriftTemperatureRepository(
      db,
      bangkok,
    ).latest(FootSide.left))!;
    expect(reading.isLegacy, isTrue);
    expect(reading.legacyForefootC, 30.8);
    expect(reading.legacyHeelC, 31.4);
    expect(reading.quality, TempQuality.normal);
    expect(reading.siteC.every((c) => c == null), isTrue);
    expect(reading.usableC(0), isNull);

    // The day keeps its old two maxima; the new columns start empty and
    // fill from the next two-foot reading.
    final summaries = DriftDailySummaryRepository(db, bangkok);
    var day = (await summaries.get('2026-10-28'))!;
    expect(day.legacyMaxDeltaForefootC, 0.4);
    expect(day.legacyMaxDeltaHeelC, 2.6);
    expect(day.maxDeltaC, isNull);
    expect(day.steps, 2340);
    expect(day.alertsByLevel[3], 1);
    await summaries.recordDelta(at + 60000, [
      null,
      1.1,
      null,
      null,
      null,
      null,
      null,
      null,
    ]);
    day = (await summaries.get('2026-10-28'))!;
    expect(day.maxDeltaC, 1.1);
    expect(day.maxDeltaSite, 1);
    expect(day.legacyMaxDeltaHeelC, 2.6);
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/gait/gait_providers.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/baseline_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/temperature_repository.dart';
import 'package:smartinsole/ui/screens/alerts/alert_view.dart';

import '../helpers/pump_app.dart' show testThresholds;
import 'storage_rig.dart';

/// S11 (DATA-CONTRACT v1.7, 6 sites) changed no table: a phone that ran a
/// v1.6 build (8 sites) keeps its rows. This database holds what such a
/// build wrote: 8-site temperature readings, 14-value baselines, alerts at
/// the retired zones with 8-entry foot maps. The v1.7 code opens it, every
/// row is still there, and reads give the 6 current sites without
/// rewriting anything.
void main() {
  test('a v3 database written by a v1.6 build opens and reads under '
      'v1.7', () async {
    final dir = Directory.systemTemp.createTempSync('v16_rows_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/smartinsole.sqlite');
    final at = bkk(2026, 11, 20, 10, 0);

    // --- What the v1.6 build wrote ---------------------------------------
    var db = AppDatabase(NativeDatabase(file));
    for (var i = 0; i < 4; i++) {
      await db
          .into(db.temperatureReadings)
          .insert(
            TemperatureReadingsCompanion.insert(
              atMs: at + i * 30000,
              localDate: '2026-11-20',
              side: FootSide.values[i % 2],
              // The worst of its 8 sites: site 7 only.
              quality: TempQuality.poorContact,
              timeFromArrival: false,
              site0C: const Value(31.0),
              site1C: const Value(31.1),
              site2C: const Value(31.2),
              site3C: const Value(31.3),
              site4C: const Value(31.4),
              site5C: const Value(31.5),
              site6C: const Value(31.6),
              site7C: const Value(31.7),
              site0Q: const Value(TempQuality.normal),
              site1Q: const Value(TempQuality.normal),
              site2Q: const Value(TempQuality.normal),
              site3Q: const Value(TempQuality.normal),
              site4Q: const Value(TempQuality.normal),
              site5Q: const Value(TempQuality.normal),
              site6Q: const Value(TempQuality.normal),
              site7Q: const Value(TempQuality.poorContact),
            ),
          );
    }
    var alerts = DriftAlertRepository(db, bangkok);
    final tempId = await alerts.add(
      NewAlert(
        kind: AlertKind.tempDelta,
        patientLevel: PatientLevel.rest,
        atMs: at,
        side: FootSide.right,
        zone: 'lateralHeel',
        measuredValue: 2.6,
        threshold: 2.2,
        details: {
          'leftC': 31.1,
          'rightC': 33.7,
          'consecutive': 2,
          TempSiteEntry.listKey: [
            TempSiteEntry(zone: 'lateralHeel', deltaC: 2.6, atMs: at).toJson(),
            TempSiteEntry(zone: 'heel', deltaC: 2.4, atMs: at).toJson(),
            TempSiteEntry(zone: 'medialArch', deltaC: 2.3, atMs: at).toJson(),
          ],
        },
      ),
    );
    final peakId = await alerts.add(
      NewAlert(
        kind: AlertKind.pressurePeak,
        patientLevel: PatientLevel.careful,
        atMs: at + 1000,
        side: FootSide.left,
        zone: 'meta1',
        measuredValue: 236,
        threshold: 200,
        details: {
          'walking': true,
          'map': {
            'left': {
              'kpa': [20, 236, 85, 20, 20, 60, 30, 240],
              'levels': [
                'low',
                'high',
                'medium',
                'low',
                'low',
                'low',
                'low',
                'high',
              ],
            },
            'right': null,
          },
        },
      ),
    );
    final retiredPeakId = await alerts.add(
      NewAlert(
        kind: AlertKind.pressurePeak,
        patientLevel: PatientLevel.careful,
        atMs: at + 2000,
        side: FootSide.left,
        zone: 'lateralHeel',
        measuredValue: 240,
        threshold: 200,
      ),
    );
    var baselines = DriftBaselineRepository(db);
    for (final side in FootSide.values) {
      await baselines.save(
        FootBaseline(
          side: side,
          insoleId: '${side.name}-1',
          recordedAtMs: at,
          sampleCount: 1500,
          values: List.filled(14, 1.5),
        ),
      );
    }
    await db.close();

    // --- The v1.7 build opens it -----------------------------------------
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    alerts = DriftAlertRepository(db, bangkok);
    baselines = DriftBaselineRepository(db);
    Future<int> count(String table) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
            .read<int>('n');
    expect(await count('temperature_readings'), 4);
    expect(await count('alerts'), 3);
    expect(await count('baselines'), 2);

    // Readings: the 6 current sites; site 6/7 kept in the table.
    final temps = DriftTemperatureRepository(db, bangkok);
    final r = (await temps.latest(FootSide.right))!;
    expect(r.siteC, [31.0, 31.1, 31.2, 31.3, 31.4, 31.5]);
    expect(r.siteQuality, everyElement(TempQuality.normal));
    final day = await temps.watchDay('2026-11-20').first;
    expect(day, hasLength(4));
    expect(day.every((x) => x.siteC.length == TempLayout.siteCount), isTrue);
    // A new v1.7 reading next to them leaves the old rows as they were.
    await temps.add(
      side: FootSide.left,
      atMs: at + 600000,
      celsius: List.filled(TempLayout.siteCount, 30.0),
      quality: List.filled(TempLayout.siteCount, TempQuality.normal),
      timeFromArrival: true,
    );
    final raw = await db
        .customSelect(
          'SELECT site6_c, site7_c, site7_q FROM temperature_readings '
          'ORDER BY at_ms',
        )
        .get();
    expect(
      [for (final x in raw) x.read<double?>('site7_c')],
      [31.7, 31.7, 31.7, 31.7, null],
    );
    expect(raw.first.read<double?>('site6_c'), 31.6);
    expect(raw.first.read<String?>('site7_q'), 'poorContact');

    // Alerts: read back unchanged; the app names the retired sites and
    // draws no map for them.
    final temp = (await alerts.byId(tempId))!;
    expect(temp.zone, 'lateralHeel');
    expect(TempSiteEntry.listOf(temp.details).map((e) => e.zone), [
      'lateralHeel',
      'heel',
      'medialArch',
    ]);
    expect(tempMapOf(temp), isNull);
    expect(footLayout.nameThOf(temp.zone!), 'ส้นเท้าด้านนอก');
    final peak = (await alerts.byId(peakId))!;
    final map = pressureMapOf(peak, testThresholds)!;
    expect(map.levels[FootSide.left], hasLength(footLayout.zones.length));
    expect(
      ((peak.details!['map'] as Map)['left'] as Map)['kpa'],
      hasLength(8),
      reason: 'stored as written',
    );
    final retiredPeak = (await alerts.byId(retiredPeakId))!;
    expect(pressureMapOf(retiredPeak, testThresholds), isNull);
    // Titles carry word joiners (display only, S10).
    expect(
      copyOf(retiredPeak).title.replaceAll('\u2060', ''),
      'ส้นเท้าซ้ายรับน้ำหนักมากตอนเดิน',
    );

    // Baselines: kept, but not a v1.7 baseline ("record again"); a new
    // recording replaces the foot's row under the same key.
    final stored = await baselines.watchAll().first;
    expect(stored, hasLength(2));
    expect(stored.first.values, hasLength(14));
    expect(currentBaselines(stored), isEmpty);
    await baselines.save(
      FootBaseline(
        side: FootSide.left,
        insoleId: 'left-1',
        recordedAtMs: at + 1,
        sampleCount: 1500,
        values: List.filled(12, 2.0),
      ),
    );
    final after = await baselines.watchAll().first;
    expect(after, hasLength(2));
    expect(currentBaselines(after).map((b) => b.side), [FootSide.left]);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/alerts_csv.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/capture/export.dart';
import 'package:smartinsole/config/thresholds.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/gait/model_spec.dart';
import 'package:smartinsole/rules/alert_providers.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';

import '../helpers/pump_app.dart';
import '../rules/rules_rig.dart';
import '../storage/storage_rig.dart';
import 'capture_rig.dart';

/// BACKLOG 40: a research capture's alerts go into its export and leave
/// the phone with it.
void main() {
  late CaptureRig capture;
  late StorageRig storage;
  late Directory exportRoot;

  setUp(() {
    fakeAsync((async) => capture = CaptureRig(async, code: 'TEST-004'));
    addTearDown(capture.dispose);
    storage = StorageRig();
    exportRoot = Directory.systemTemp.createTempSync('capture_export_');
    addTearDown(() => exportRoot.deleteSync(recursive: true));
  });

  String stampOf() => captureStampOf(capture.session.sessionId);

  Future<void> addAlerts() async {
    final at = DateTime(2026, 11, 10, 9, 5).millisecondsSinceEpoch;
    await storage.alerts.add(
      NewAlert(
        kind: AlertKind.tempDelta,
        patientLevel: PatientLevel.rest,
        atMs: at,
        side: FootSide.right,
        zone: 'meta1',
        measuredValue: 2.6,
        threshold: 2.2,
        details: {
          'leftC': 31.0,
          'rightC': 33.6,
          'consecutive': 2,
          TempSiteEntry.listKey: [
            TempSiteEntry(zone: 'meta1', deltaC: 2.6, atMs: at).toJson(),
            TempSiteEntry(
              zone: 'meta3',
              deltaC: 2.3,
              atMs: at + 30000,
            ).toJson(),
          ],
        },
        captureStamp: stampOf(),
      ),
    );
    await storage.alerts.add(
      alertOf(AlertKind.pressureWatch, at + 1, captureStamp: stampOf()),
    );
    // Another capture's, and an everyday one: not this export's.
    await storage.alerts.add(
      alertOf(AlertKind.tempDelta, at, captureStamp: '20261109-100000'),
    );
    await storage.alerts.add(alertOf(AlertKind.batteryLow, at));
  }

  test('the export has alerts.csv with exactly this session\'s alerts, '
      'listed and hashed in the manifest', () async {
    await addAlerts();
    final (entries, count) = await exportSession(
      capture.session,
      exportRoot,
      storage.alerts,
    );
    expect(count, 2);
    final dir = Directory('${exportRoot.path}/${capture.session.sessionId}');
    final csv = File('${dir.path}/$alertsCsvName');
    final lines = csv.readAsLinesSync();
    expect(lines.first, alertsCsvColumns.join(','));
    expect(lines.skip(1).map((l) => l.split(',')[1]), [
      'TEMP_DELTA',
      'PRESSURE_WATCH',
    ]);
    expect(lines[1], contains('"{""leftC"":31.0,""rightC"":33.6'));
    // The TEMP_DELTA row: its zone and every qualifying site.
    final cells = lines[1].split(',');
    final col = alertsCsvColumns.indexOf;
    expect(cells[col('zone')], 'meta1');
    expect(cells[col('site')], '');
    final at = DateTime(2026, 11, 10, 9, 5).millisecondsSinceEpoch;
    expect(cells[col('temp_sites')], 'meta1:2.60:$at;meta3:2.30:${at + 30000}');
    // A pressure alert has none.
    expect(lines[2].split(',')[col('temp_sites')], '');
    final manifest = jsonDecode(
      File('${dir.path}/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final listed = {
      for (final f in manifest['files']! as List<Object?>)
        (f! as Map)['name']: f,
    };
    expect(listed.keys, contains(alertsCsvName));
    final entry = listed[alertsCsvName]! as Map;
    expect(entry['sha256'], sha256Of(csv));
    expect(entry['size'], csv.lengthSync());
    expect(entries.map((e) => e.name), contains(alertsCsvName));
    // Export only: the private session folder never holds it.
    expect(
      File('${capture.session.dir.path}/$alertsCsvName').existsSync(),
      isFalse,
    );
  });

  test('a session with no alerts exports a header-only alerts.csv', () async {
    await exportSession(capture.session, exportRoot, storage.alerts);
    final csv = File(
      '${exportRoot.path}/${capture.session.sessionId}/$alertsCsvName',
    );
    expect(csv.readAsLinesSync(), [alertsCsvColumns.join(',')]);
  });

  test('Delete from phone removes the session and its alerts only', () async {
    await addAlerts();
    await deleteSession(capture.session, storage.alerts);
    expect(capture.session.dir.existsSync(), isFalse);
    expect(await storage.alerts.forCapture(stampOf()), isEmpty);
    final left = await storage.alerts.since(0);
    expect(left.map((a) => a.captureStamp).toSet(), {'20261109-100000', null});
    // Recreate the folder so the rig's teardown has something to remove.
    capture.root.createSync(recursive: true);
  });

  test('the engine tags alerts with the open capture, and stops when it '
      'closes', () async {
    final rig = RulesRig()..stream();
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        thresholdsProvider.overrideWithValue(testThresholds),
        modelInputSpecProvider.overrideWithValue(testModelInput),
        deviceManagerProvider.overrideWithValue(rig.manager),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    final engine = container.read(alertEngineProvider);
    container.read(activeCaptureProvider.notifier).open('20261110-090000');
    rig.walkBoth(
      const Duration(seconds: 2),
      const Gait(kpa: [0, 240, 0, 0, 0, 0]),
    );
    engine.check();
    await engine.flush();
    final active = container.read(activeCaptureProvider.notifier)
      ..close('19990101-000000'); // another stamp: no effect
    expect(container.read(activeCaptureProvider), '20261110-090000');
    active.close('20261110-090000');
    rig.left.status(battery: 5);
    rig.walkBoth(const Duration(seconds: 1), const Gait());
    engine.check();
    await engine.flush();
    final all = await container.read(alertRepositoryProvider).since(0);
    final tagged = {
      for (final a in all)
        if (a.captureStamp != null) a.kind,
    };
    expect(tagged, {AlertKind.pressurePeak, AlertKind.pressureWatch});
    expect(
      all.firstWhere((a) => a.kind == AlertKind.batteryLow).captureStamp,
      isNull,
    );
  });
}

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/storage/models.dart';

import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/database.dart';

import '../alerts/alerts_rig.dart';
import '../helpers/pump_app.dart';

/// Alerts list, empty state and alert details (DESIGN-SPEC §7) at 100 %
/// and 200 % text, on surfaces tall enough for the whole page.
/// Regenerate: flutter test --update-goldens test/goldens/alerts_golden_test.dart
void main() {
  for (final scale in [1.0, 2.0]) {
    final pct = (scale * 100).round();
    final tall = scale == 1 ? 1900.0 : 4600.0;

    testWidgets('alerts_list_$pct', (tester) async {
      // Mixed read / unread over three days.
      await pumpAlerts(
        tester,
        textScale: scale,
        size: Size(390, tall),
        read: {AlertKind.pressurePti, AlertKind.deviceLost},
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/alerts_list_$pct.png'),
      );
    });

    testWidgets('alerts_empty_$pct', (tester) async {
      await pumpAlerts(tester, seed: false, textScale: scale);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/alerts_empty_$pct.png'),
      );
    });

    for (final (kind, open) in [
      (AlertKind.tempDelta, false),
      (AlertKind.pressurePeak, true),
      (AlertKind.pressurePti, false),
      (AlertKind.loadConcentration, false),
      (AlertKind.deviceLost, false),
    ]) {
      final name = 'alert_detail_${kind.wireName.toLowerCase()}_$pct';
      testWidgets(name, (tester) async {
        final ids = await pumpAlerts(
          tester,
          textScale: scale,
          size: Size(390, scale == 1 ? 2300 : 5600),
        );
        await openAlert(tester, ids, kind);
        if (open) {
          await tester.tap(byKey('details-expander'));
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('screens/$name.png'),
        );
      });
    }
  }

  testWidgets('alert_detail_no_map_100', (tester) async {
    // An alert stored before S6B: no foot map, only the triggering zone.
    final db = AppDatabase.memory();
    final id = await tester.runAsync(
      () => DriftAlertRepository(db).add(
        NewAlert(
          kind: AlertKind.pressurePeak,
          patientLevel: PatientLevel.careful,
          atMs: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          side: FootSide.right,
          zone: 'heel',
          measuredValue: 228,
          threshold: testThresholds.alertKpa,
          details: {'walking': true},
        ),
      ),
    );
    await pumpApp(tester, database: db, size: const Size(390, 2300));
    await tester.tap(byKey('tab-alerts'));
    await tester.pumpAndSettle();
    await openAlert(tester, {
      AlertKind.pressurePeak: id!,
    }, AlertKind.pressurePeak);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screens/alert_detail_no_map_100.png'),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/sample_alerts.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../helpers/pump_app.dart';

/// The app's provider container, once [pumpApp] has run (also while a
/// pushed route covers the shell).
ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(AppShell, skipOffstage: false)),
);

/// A new in-memory database holding the design boards' sample alerts
/// ([seedSampleAlerts]) at [fixedNow] (Sunday 18 Oct, 09:30): today
/// TEMP_DELTA 09:00, LOAD_CONCENTRATION 08:30, PRESSURE_PEAK 07:30
/// (toe-walking note), PRESSURE_PTI 06:30; yesterday BATTERY_LOW 18:05,
/// DEVICE_LOST 16:20; 16 Oct a foot-check finding. [read] are marked read.
/// Written before the app runs (see [pumpApp]'s `database`).
Future<(AppDatabase, Map<AlertKind, int>)> seededDatabase(
  WidgetTester tester, {
  Set<AlertKind> read = const {},
}) async {
  final db = AppDatabase.memory();
  final ids = await tester.runAsync(() async {
    final repo = DriftAlertRepository(db);
    await seedSampleAlerts(
      alerts: repo,
      footChecks: DriftFootCheckRepository(db),
      thresholds: testThresholds,
      now: fixedNow,
    );
    final all = await repo.since(0);
    for (final a in all) {
      if (read.contains(a.kind)) await repo.markRead(a.id, a.atMs + 60000);
    }
    return {for (final a in all) a.kind: a.id};
  });
  return (db, ids!);
}

/// Pumps the app, optionally on the seeded sample alerts, and opens the
/// Alerts tab. Returns each seeded kind's id.
Future<Map<AlertKind, int>> pumpAlerts(
  WidgetTester tester, {
  bool seed = true,
  Set<AlertKind> read = const {},
  double textScale = 1.0,
  bool reduceMotion = false,
  Size size = referenceSize,
}) async {
  AppDatabase? db;
  var ids = const <AlertKind, int>{};
  if (seed) (db, ids) = await seededDatabase(tester, read: read);
  await pumpApp(
    tester,
    database: db,
    textScale: textScale,
    reduceMotion: reduceMotion,
    size: size,
  );
  await tester.tap(byKey('tab-alerts'));
  await tester.pumpAndSettle();
  return ids;
}

/// Opens the detail of [kind]'s alert from the list.
Future<void> openAlert(
  WidgetTester tester,
  Map<AlertKind, int> ids,
  AlertKind kind,
) async {
  final card = byKey('alert-card-${ids[kind]}');
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.descendant(
      of: byKey('alerts-scroll'),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(card);
  await tester.pumpAndSettle();
}

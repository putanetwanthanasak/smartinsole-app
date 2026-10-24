import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/routes.dart';

import '../helpers/pump_app.dart';
import 'widget_rig.dart';

Future<void> tapClear(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  // The page is a lazy list: drag until the last section is built.
  final list = find.byType(ListView).first;
  for (var i = 0; i < 20 && byKey('clear-test-data').evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
  }
  await tester.ensureVisible(byKey('clear-test-data'));
  await tester.pump();
  await tester.tap(byKey('clear-test-data'));
  await tester.pump();
}

/// Capture home › "Clear app database (test data)" (SR checklist).
void main() {
  late WidgetRig rig;
  late Directory photos;
  setUp(() {
    rig = WidgetRig();
    photos = Directory('${rig.root.path}/foot_photos')..createSync();
  });
  tearDown(() => rig.dispose());

  testWidgets('two confirmations; a stored session and its tagged alerts '
      'survive', (tester) async {
    final session = rig.newSession();
    final stamp = captureStampOf(session.sessionId);
    final db = AppDatabase.memory();
    await tester.runAsync(() async {
      final repo = DriftAlertRepository(db);
      await repo.add(
        NewAlert(
          kind: AlertKind.tempDelta,
          patientLevel: PatientLevel.rest,
          atMs: rig.t.millisecondsSinceEpoch,
        ),
      );
      await repo.add(
        NewAlert(
          kind: AlertKind.pressurePeak,
          patientLevel: PatientLevel.careful,
          atMs: rig.t.millisecondsSinceEpoch,
          captureStamp: stamp,
        ),
      );
    });
    File('${photos.path}/p.jpg').writeAsStringSync('x');

    await pumpApp(
      tester,
      initialRoute: Routes.capture,
      now: rig.now,
      database: db,
      overrides: [
        ...rig.overrides,
        footPhotoDirProvider.overrideWithValue(() async => photos),
      ],
      settle: false,
    );
    await tapClear(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(byKey('clear-confirm-1'), findsOneWidget);
    expect(
      find.textContaining('1 session on this phone keeps its alerts.'),
      findsOneWidget,
    );
    await tester.tap(byKey('clear-confirm-1-ok'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(byKey('clear-confirm-2'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(byKey('clear-confirm-2-ok'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 500));
    expect(byKey('clear-done'), findsOneWidget);
    expect(find.textContaining('Removed 1 alerts'), findsOneWidget);

    final left = await tester.runAsync(() => DriftAlertRepository(db).since(0));
    expect(left!.map((a) => a.captureStamp), [stamp]);
    expect(session.dir.existsSync(), isTrue);
    expect(photos.listSync(), isEmpty);
  });

  testWidgets('Cancel on the first confirmation changes nothing', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    await tester.runAsync(
      () => DriftAlertRepository(db).add(
        NewAlert(
          kind: AlertKind.tempDelta,
          patientLevel: PatientLevel.rest,
          atMs: rig.t.millisecondsSinceEpoch,
        ),
      ),
    );
    await pumpApp(
      tester,
      initialRoute: Routes.capture,
      now: rig.now,
      database: db,
      overrides: rig.overrides,
      settle: false,
    );
    await tapClear(tester);
    await tester.pump(const Duration(milliseconds: 500));
    // No sessions stored: no "keep their alerts" line.
    expect(find.textContaining('keep'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(byKey('clear-confirm-2'), findsNothing);
    final left = await tester.runAsync(() => DriftAlertRepository(db).since(0));
    expect(left, hasLength(1));
  });
}

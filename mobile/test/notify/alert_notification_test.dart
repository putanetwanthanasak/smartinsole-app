import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/notify/alert_notification_service.dart';
import 'package:smartinsole/notify/alert_notifier.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_copy.dart';
import 'package:smartinsole/rules/alert_engine.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/settings/settings_providers.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../alerts/alerts_rig.dart';
import '../helpers/fake_alert_notifier.dart';
import '../helpers/fake_reminder_notifier.dart';
import '../helpers/pump_app.dart';

RaisedAlert raised(
  int id,
  AlertKind kind, {
  FootSide side = FootSide.left,
  String? zone = 'meta1',
  String? stamp,
}) => RaisedAlert(
  id,
  NewAlert(
    kind: kind,
    patientLevel: PatientLevel.careful,
    atMs: 0,
    side: side,
    zone: zone,
    measuredValue: 2.5,
    threshold: 2.2,
    captureStamp: stamp,
  ),
);

/// Foot alert notifications (S9, user decisions 4–8).
void main() {
  group('noticeFor', () {
    test('the 4 foot codes notify, with the alert\'s title and "ควรทำ"', () {
      for (final code in notifiedCodes) {
        final kind = AlertKind.values.firstWhere((k) => k.code == code);
        final n = noticeFor(raised(7, kind), capturing: false)!;
        final copy = alertCopyFor(
          code,
          side: FootSide.left,
          channel: 1,
          value: 2.5,
          threshold: 2.2,
        );
        expect(n.alertId, 7);
        expect(n.title, copy.title, reason: code.name);
        expect(n.body, copy.todo, reason: code.name);
      }
      expect(notifiedCodes, {
        AlertCode.tempDelta,
        AlertCode.pressurePeak,
        AlertCode.pressurePti,
        AlertCode.loadConcentration,
      });
    });

    test('every other code stays in the app only', () {
      for (final kind in AlertKind.values) {
        if (notifiedCodes.contains(kind.code)) continue;
        expect(
          noticeFor(raised(1, kind), capturing: false),
          isNull,
          reason: kind.name,
        );
      }
    });

    test('nothing during a research capture (stamp, or open now)', () {
      expect(
        noticeFor(
          raised(1, AlertKind.tempDelta, stamp: '20261110-093000'),
          capturing: false,
        ),
        isNull,
      );
      expect(
        noticeFor(raised(1, AlertKind.tempDelta), capturing: true),
        isNull,
      );
    });

    test('payload round trip; the reminder\'s payload is not an alert', () {
      expect(alertIdOfPayload(alertPayloadOf(42)), 42);
      expect(alertIdOfPayload('foot-check-reminder'), isNull);
      expect(alertIdOfPayload(null), isNull);
      expect(alertIdOfPayload('alert:x'), isNull);
    });
  });

  group('AlertNotificationService', () {
    late StreamController<RaisedAlert> raisedCtl;
    late FakeAlertNotifier fake;
    late ProviderContainer c;

    setUp(() {
      raisedCtl = StreamController<RaisedAlert>.broadcast();
      fake = FakeAlertNotifier();
      c = ProviderContainer(
        overrides: [
          raisedAlertsProvider.overrideWithValue(raisedCtl.stream),
          alertNotifierProvider.overrideWithValue(fake),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        ],
      );
    });
    tearDown(() async {
      c.dispose();
      await raisedCtl.close();
    });

    Future<void> start({void Function(int)? open}) => c
        .read(alertNotificationServiceProvider)
        .start(openAlert: open ?? (_) {});

    test('posts each notified alert on the sound channel', () async {
      await start();
      raisedCtl
        ..add(raised(1, AlertKind.tempDelta))
        ..add(raised(2, AlertKind.pressureWatch))
        ..add(raised(3, AlertKind.loadConcentration));
      await pumpEventQueue();
      expect(fake.shown.map((s) => s.$1.alertId), [1, 3]);
      expect(fake.shown.every((s) => s.$2), isTrue);
    });

    test('sound off → the silent channel', () async {
      await start();
      await c.read(settingsProvider.notifier).setSound(false);
      raisedCtl.add(raised(1, AlertKind.pressurePeak));
      await pumpEventQueue();
      expect(fake.shown.single.$2, isFalse);
    });

    test('a research capture open: nothing posted', () async {
      await start();
      c.read(activeCaptureProvider.notifier).open('S01_20261110_0930');
      raisedCtl.add(raised(1, AlertKind.pressurePti));
      await pumpEventQueue();
      expect(fake.shown, isEmpty);
      c.read(activeCaptureProvider.notifier).close('S01_20261110_0930');
      raisedCtl.add(raised(2, AlertKind.pressurePti));
      await pumpEventQueue();
      expect(fake.shown.single.$1.alertId, 2);
    });

    test('a launch from an alert notification opens it once', () async {
      fake.launchedFrom = 9;
      final opened = <int>[];
      await start(open: opened.add);
      expect(opened, [9]);
      fake.onTap!(4);
      expect(opened, [9, 4]);
    });
  });

  testWidgets('a tap during a research capture navigates nowhere (it would '
      'end a running trial); alert and reminder alike', (tester) async {
    final (db, ids) = await seededDatabase(tester);
    final fake = FakeAlertNotifier();
    final reminders = FakeReminderNotifier();
    await pumpApp(
      tester,
      database: db,
      alertNotifier: fake,
      reminders: reminders,
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    // Stands in for the open session screen.
    await tester.tap(byKey('settings-button'));
    await tester.pumpAndSettle();
    c.read(activeCaptureProvider.notifier).open('S01_20261110_0930');
    fake.onTap!(ids[AlertKind.pressurePeak]!);
    reminders.onTap!();
    await tester.pumpAndSettle();
    expect(byKey('detail-status-card'), findsNothing);
    expect(byKey('back-link'), findsOneWidget, reason: 'still on Settings');
    expect(c.read(selectedTabProvider), AppTab.today);
    c.read(activeCaptureProvider.notifier).close('S01_20261110_0930');
  });

  group('a tap opens that alert over the Alerts tab', () {
    for (final launched in [false, true]) {
      testWidgets(
        launched ? 'launch from a notification' : 'tap while running',
        (tester) async {
          final (db, ids) = await seededDatabase(tester);
          final id = ids[AlertKind.pressurePeak]!;
          final fake = FakeAlertNotifier()..launchedFrom = launched ? id : null;
          await pumpApp(tester, database: db, alertNotifier: fake);
          if (!launched) {
            // From another tab and a pushed screen.
            await tester.tap(byKey('settings-button'));
            await tester.pumpAndSettle();
            fake.onTap!(id);
          }
          await tester.pumpAndSettle();
          expect(byKey('detail-status-card'), findsOneWidget);
          final title = alertCopyFor(
            AlertCode.pressurePeak,
            side: FootSide.left,
            channel: 1,
          ).title;
          expect(find.text(title), findsWidgets);
          await tester.tap(byKey('back-link'));
          await tester.pumpAndSettle();
          expect(byKey('alerts-header'), findsOneWidget);
        },
      );
    }
  });
}

import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/screens/connection_screen.dart';
import 'package:smartinsole/ui/screens/foot_check_found_screen.dart';

import '../helpers/pump_app.dart';
import 'alerts_rig.dart';

/// Largest bell rotation (degrees) on the Alerts tab right now.
double bellAngle(WidgetTester tester) {
  var max = 0.0;
  for (final t in tester.widgetList<Transform>(
    find.descendant(of: byKey('tab-alerts'), matching: find.byType(Transform)),
  )) {
    final m = t.transform.storage;
    max = math.max(max, math.atan2(m[1], m[0]).abs() * 180 / math.pi);
  }
  return max;
}

Future<int> insertAlert(WidgetTester tester, {int minutesAgo = 1}) async {
  final id = await tester.runAsync(
    () => containerOf(tester)
        .read(alertRepositoryProvider)
        .add(
          NewAlert(
            kind: AlertKind.tempDelta,
            patientLevel: PatientLevel.rest,
            atMs: fixedNow
                .subtract(Duration(minutes: minutesAgo))
                .millisecondsSinceEpoch,
            side: FootSide.left,
            zone: 'meta1',
            measuredValue: 2.4,
            threshold: testThresholds.deltaC,
          ),
        ),
  );
  return id!;
}

String? unreadLine(WidgetTester tester) {
  final texts = find.descendant(
    of: byKey('alerts-unread'),
    matching: find.byType(Text),
  );
  return texts.evaluate().isEmpty
      ? null
      : (tester.widget<Text>(texts.first).data);
}

String? groupTitle(WidgetTester tester, String date) => tester
    .widget<Text>(
      find.descendant(of: byKey('group-$date'), matching: find.byType(Text)),
    )
    .data;

void main() {
  group('list', () {
    testWidgets('groups by day, newest first, with the footer', (tester) async {
      await pumpAlerts(tester, size: const Size(390, 2000));
      // fixedNow is Sunday 18 Oct 2026.
      expect(groupTitle(tester, '2026-10-18'), 'วันนี้');
      expect(groupTitle(tester, '2026-10-17'), 'เมื่อวาน · เสาร์ 17 ต.ค.');
      expect(groupTitle(tester, '2026-10-16'), 'ศุกร์ 16 ต.ค.');
      expect(find.text('แสดงย้อนหลัง 30 วัน'), findsOneWidget);
      expect(
        tester.getTopLeft(byKey('group-2026-10-18')).dy,
        lessThan(tester.getTopLeft(byKey('group-2026-10-17')).dy),
      );
      expect(find.text('จากการดูเท้าประจำวัน'), findsOneWidget);
    });

    testWidgets('a finding\'s label carries its source line and advice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAlerts(tester, size: const Size(390, 2000));
      expect(
        find.bySemanticsLabel(
          'ควรระวัง 09:30 พบสิ่งที่ควรให้แพทย์ดู ยังไม่ได้อ่าน '
          'จากการดูเท้าประจำวัน ควรทำ: ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน '
          'และนำรูปที่ถ่ายไว้ไปให้ดู',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('empty state', (tester) async {
      await pumpAlerts(tester, seed: false);
      expect(byKey('alerts-empty'), findsOneWidget);
      expect(find.text('ยังไม่มีการแจ้งเตือน'), findsOneWidget);
      expect(unreadLine(tester), isNull);
      expect(byKey('alerts-footer'), findsNothing);
    });

    testWidgets('unread line and "ใหม่" chips follow read state', (
      tester,
    ) async {
      await pumpAlerts(
        tester,
        size: const Size(390, 2000),
        read: {AlertKind.deviceLost, AlertKind.pressurePti},
      );
      expect(unreadLine(tester), 'ยังไม่ได้อ่าน 5 รายการ');
      expect(find.text('ใหม่'), findsNWidgets(5));
    });

    testWidgets('the unread line is a live region that stays in the tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAlerts(tester, seed: false);
      final node = tester.getSemantics(byKey('alerts-unread'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      await insertAlert(tester);
      await tester.pumpAndSettle();
      expect(unreadLine(tester), 'ยังไม่ได้อ่าน 1 รายการ');
      expect(
        tester
            .getSemantics(byKey('alerts-unread'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('card TalkBack label: tag, time, title, read state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final ids = await pumpAlerts(tester, read: {AlertKind.deviceLost});
      expect(
        find.bySemanticsLabel(
          'ควรพักเท้า 09:00 เท้าขวาอุ่นกว่าเท้าซ้าย ยังไม่ได้อ่าน '
          'ควรทำ: นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        byKey('alert-card-${ids[AlertKind.deviceLost]}'),
        200,
        scrollable: find.descendant(
          of: byKey('alerts-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'อุปกรณ์ 16:20 แผ่นรองเท้าซ้ายหลุดการเชื่อมต่อ อ่านแล้ว '
          'ควรทำ: ตรวจว่าแผ่นรองเท้าเปิดอยู่ แล้วเชื่อมต่อใหม่',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('read state and navigation', () {
    testWidgets('opening a detail marks it read; back returns to Alerts', (
      tester,
    ) async {
      final ids = await pumpAlerts(tester);
      expect(
        find.descendant(of: byKey('alerts-badge'), matching: find.text('7')),
        findsOneWidget,
      );
      await openAlert(tester, ids, AlertKind.tempDelta);
      expect(byKey('detail-status-card'), findsOneWidget);
      await tester.tap(byKey('back-link'));
      await tester.pumpAndSettle();
      expect(byKey('alerts-header'), findsOneWidget);
      expect(unreadLine(tester), 'ยังไม่ได้อ่าน 6 รายการ');
      expect(
        find.descendant(of: byKey('alerts-badge'), matching: find.text('6')),
        findsOneWidget,
      );
      final stored = await tester.runAsync(
        () => containerOf(tester).read(alertRepositoryProvider).since(0),
      );
      final a = stored!.firstWhere((a) => a.id == ids[AlertKind.tempDelta]);
      expect(a.readAtMs, fixedNow.millisecondsSinceEpoch);
    });

    testWidgets('BATTERY_LOW opens Connection and is marked read', (
      tester,
    ) async {
      final ids = await pumpAlerts(tester);
      await openAlert(tester, ids, AlertKind.batteryLow);
      expect(find.byType(ConnectionScreen), findsOneWidget);
      final stored = await tester.runAsync(
        () => containerOf(tester).read(alertRepositoryProvider).since(0),
      );
      expect(
        stored!.firstWhere((a) => a.kind == AlertKind.batteryLow).isRead,
        isTrue,
      );
    });

    testWidgets('a finding opens Foot check › Found with its id, read', (
      tester,
    ) async {
      final ids = await pumpAlerts(tester);
      await openAlert(tester, ids, AlertKind.footCheckFinding);
      final screen = tester.widget<FootCheckFoundScreen>(
        find.byType(FootCheckFoundScreen),
      );
      final stored = await tester.runAsync(
        () => containerOf(tester).read(alertRepositoryProvider).since(0),
      );
      final finding = stored!.firstWhere(
        (a) => a.kind == AlertKind.footCheckFinding,
      );
      expect(finding.footCheckId, isNotNull);
      expect(screen.footCheckId, finding.footCheckId);
      expect(byKey('foot-check-found-${finding.footCheckId}'), findsOneWidget);
      expect(finding.isRead, isTrue);
    });

    for (final (kind, target) in [
      (AlertKind.tempDelta, 'temperature'),
      (AlertKind.pressurePeak, 'pressure'),
      (AlertKind.pressurePti, 'pressure'),
      (AlertKind.loadConcentration, 'pressure'),
    ]) {
      testWidgets('${kind.wireName} action opens My feet › $target', (
        tester,
      ) async {
        final ids = await pumpAlerts(tester, size: const Size(390, 2400));
        await openAlert(tester, ids, kind);
        await tester.tap(byKey('detail-action'));
        await tester.pumpAndSettle();
        expect(byKey('$target-tab'), findsOneWidget);
        expect(byKey('detail-status-card'), findsNothing);
      });
    }

    testWidgets('DEVICE_LOST action opens Connection', (tester) async {
      final ids = await pumpAlerts(tester, size: const Size(390, 2400));
      await openAlert(tester, ids, AlertKind.deviceLost);
      await tester.tap(byKey('detail-action'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
    });

    testWidgets('Home "ดูเพิ่ม" opens My feet › pressure', (tester) async {
      await pumpApp(tester);
      final more = find.text('ดูเพิ่ม');
      await tester.scrollUntilVisible(more, 200);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(byKey('pressure-tab'), findsOneWidget);
    });
  });

  group('motion', () {
    testWidgets('a new alert: bell wiggles and the row opens at the top', (
      tester,
    ) async {
      await pumpAlerts(tester);
      expect(bellAngle(tester), 0);
      final id = await insertAlert(tester);
      final row = find.byKey(ValueKey('alert-$id'));
      // Frame by frame until the row is in, then sample the wiggle.
      for (var i = 0; i < 10 && row.evaluate().isEmpty; i++) {
        await tester.pump();
      }
      expect(row, findsOneWidget);
      final opening = tester.getSize(row).height;
      var angle = 0.0;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        angle = math.max(angle, bellAngle(tester));
      }
      expect(angle, greaterThan(1));
      await tester.pumpAndSettle();
      expect(tester.getSize(row).height, greaterThan(opening));
      expect(bellAngle(tester), 0);
      // Newest first: above the earlier TEMP_DELTA of today.
      expect(
        tester.getTopLeft(row).dy,
        lessThan(tester.getTopLeft(find.text('เท้าขวาอุ่นกว่าเท้าซ้าย')).dy),
      );
    });

    testWidgets('alerts stored before start-up do not wiggle the bell', (
      tester,
    ) async {
      final (db, _) = await seededDatabase(tester);
      await pumpApp(tester, database: db, settle: false);
      var max = 0.0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        max = math.max(max, bellAngle(tester));
      }
      expect(max, 0);
      expect(byKey('alerts-badge'), findsOneWidget);
    });

    testWidgets('reduce motion: a new row and the list are there at once', (
      tester,
    ) async {
      await pumpAlerts(tester, reduceMotion: true);
      final id = await insertAlert(tester);
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(ValueKey('alert-$id')), findsOneWidget);
      expect(bellAngle(tester), 0);
    });
  });

  group('detail', () {
    testWidgets('numbers closed on open; expander says expanded / collapsed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final ids = await pumpAlerts(tester, size: const Size(390, 2400));
      await openAlert(tester, ids, AlertKind.pressurePeak);
      expect(byKey('details-rows'), findsNothing);
      expect(
        tester.getSemantics(byKey('details-expander')),
        matchesSemantics(
          label: 'ดูตัวเลขละเอียด',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );
      await tester.tap(byKey('details-expander'));
      await tester.pumpAndSettle();
      expect(byKey('details-rows'), findsOneWidget);
      expect(
        tester
            .getSemantics(byKey('details-expander'))
            .flagsCollection
            .isExpanded,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('map TalkBack labels (PEAK and TEMP_DELTA)', (tester) async {
      final handle = tester.ensureSemantics();
      final ids = await pumpAlerts(tester, size: const Size(390, 2400));
      await openAlert(tester, ids, AlertKind.pressurePeak);
      expect(
        find.bySemanticsLabel('เท้าซ้าย โคนนิ้วหัวแม่เท้ารับน้ำหนักมาก'),
        findsOneWidget,
      );
      await tester.tap(byKey('back-link'));
      await tester.pumpAndSettle();
      await openAlert(tester, ids, AlertKind.tempDelta);
      // The sample TEMP_DELTA lists two sites: both are named.
      expect(
        find.bySemanticsLabel(
          'เท้าขวา กลางส้นเท้า และส้นเท้าด้านนอกอุ่นกว่าเท้าซ้าย',
        ),
        findsOneWidget,
      );
      expect(
        find.text('จุดที่อุ่นกว่าบนเท้าขวา: กลางส้นเท้า · ส้นเท้าด้านนอก'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('เท้าซ้าย จุดวัดความอุ่นทั้ง 8 จุด'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('gait note only with a stored class; no map for DEVICE_LOST', (
      tester,
    ) async {
      final ids = await pumpAlerts(tester, size: const Size(390, 2400));
      await openAlert(tester, ids, AlertKind.pressurePeak);
      expect(byKey('gait-note'), findsOneWidget);
      await tester.tap(byKey('back-link'));
      await tester.pumpAndSettle();
      await openAlert(tester, ids, AlertKind.loadConcentration);
      expect(byKey('gait-note'), findsNothing);
      expect(byKey('detail-map'), findsOneWidget);
      await tester.tap(byKey('back-link'));
      await tester.pumpAndSettle();
      await openAlert(tester, ids, AlertKind.deviceLost);
      expect(byKey('detail-map'), findsNothing);
    });
  });
}

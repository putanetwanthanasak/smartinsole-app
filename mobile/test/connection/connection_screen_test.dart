import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/settings/settings_store.dart';

import '../ble/fake_ble_central.dart';
import '../helpers/pump_app.dart';
import 'connection_rig.dart';

String statusOf(WidgetTester tester, FootSide side) =>
    tester.widget<Text>(byKey('connect-status-${side.name}')).data!;

void main() {
  testWidgets('both feet connect from the Connection screen alone; the '
      'done button returns to Today', (tester) async {
    final store = MemorySettingsStore();
    await pumpConnection(
      tester,
      insoles: [rightBoard(), leftBoard()],
      settings: store,
    );
    expect(statusOf(tester, FootSide.left), 'ยังไม่ได้เชื่อมต่อ');
    expect(byKey('connect-info'), findsOneWidget);
    expect(byKey('connect-done'), findsNothing);

    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    expect(statusOf(tester, FootSide.left), 'เชื่อมต่อแล้ว');
    expect(
      find.descendant(
        of: byKey('connect-line-left'),
        matching: find.text('แบต 100% · เฟิร์มแวร์ 0.1'),
      ),
      findsOneWidget,
    );
    await tapAndRun(tester, 'connect-action-right', const Duration(seconds: 2));
    expect(statusOf(tester, FootSide.right), 'เชื่อมต่อแล้ว');

    expect(byKey('connect-info'), findsNothing);
    expect(byKey('connect-done'), findsOneWidget);
    expect(store.boundInsole(FootSide.left), 'L1');
    expect(store.boundInsole(FootSide.right), 'R1');

    await tapAndRun(tester, 'connect-done', const Duration(seconds: 1));
    expect(byKey('status-card'), findsOneWidget); // Home
    await unmount(tester);
  });

  testWidgets('searching shows "หยุดค้นหา", which goes back to not '
      'connected', (tester) async {
    await pumpConnection(tester);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 1));
    expect(statusOf(tester, FootSide.left), 'กำลังค้นหา…');
    expect(find.text('หยุดค้นหา'), findsOneWidget);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 1));
    expect(statusOf(tester, FootSide.left), 'ยังไม่ได้เชื่อมต่อ');
    await unmount(tester);
  });

  testWidgets('wrong side (rule 8): only the right insole is on', (
    tester,
  ) async {
    await pumpConnection(tester, insoles: [rightBoard()]);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 5));
    expect(statusOf(tester, FootSide.left), 'แผ่นที่พบเป็นของเท้าขวา');
    expect(
      find.text(
        'ใส่แผ่นนี้ที่รองเท้าข้างขวา หรือเปิดแผ่นของเท้าซ้ายแล้วค้นหาอีกครั้ง',
      ),
      findsOneWidget,
    );
    // The info box hides while a wrong-side message shows.
    expect(byKey('connect-info'), findsNothing);
    expect(find.text('ค้นหาอีกครั้ง'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('not found after 20 s; MTU too small reads "connected, no '
      'data"', (tester) async {
    final board = leftBoard(mtu: 23)..advertising = false;
    await pumpConnection(tester, insoles: [board]);
    await tapAndRun(
      tester,
      'connect-action-right',
      const Duration(seconds: 21),
    );
    expect(statusOf(tester, FootSide.right), 'ไม่พบแผ่นรองเท้า');
    expect(find.text('ตรวจว่าไฟที่กล่องอุปกรณ์ติดอยู่'), findsOneWidget);

    board.advertising = true;
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    expect(
      statusOf(tester, FootSide.left),
      'เชื่อมต่อแล้ว แต่ยังไม่ได้รับข้อมูล',
    );
    expect(find.text('เชื่อมต่อใหม่'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the other foot\'s unusable insole still reads as wrong side '
      'for this foot (rule 8)', (tester) async {
    // Left is "connected, no data" (MTU too small), so its link is closed
    // and it advertises again; the right search finds it.
    await pumpConnection(tester, insoles: [leftBoard(mtu: 23)]);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    await tapAndRun(tester, 'connect-action-right', const Duration(seconds: 5));
    expect(statusOf(tester, FootSide.right), 'แผ่นที่พบเป็นของเท้าซ้าย');
    await unmount(tester);
  });

  testWidgets('a stream that stops reads "connected, no data" (read-time '
      'staleness, rule 2)', (tester) async {
    final central = await pumpConnection(tester, insoles: [leftBoard()]);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    expect(statusOf(tester, FootSide.left), 'เชื่อมต่อแล้ว');
    // The board stops sending without the app asking (the link stays up).
    await central.insoles['L1']!.link!.write(
      BleUuids.control,
      Uint8List.fromList([BleOpcode.stopStream]),
    );
    await pumpFor(tester, DeviceManager.defaultStaleAfter * 2);
    expect(
      statusOf(tester, FootSide.left),
      'เชื่อมต่อแล้ว แต่ยังไม่ได้รับข้อมูล',
    );
    await unmount(tester);
  });

  testWidgets('Bluetooth off: the panel, both cards wait, no info box', (
    tester,
  ) async {
    final central = await pumpConnection(tester, insoles: [leftBoard()]);
    central.setAdapter(AdapterState.off);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(byKey('bt-off-panel'), findsOneWidget);
    expect(byKey('connect-info'), findsNothing);
    expect(statusOf(tester, FootSide.left), 'รอเปิดบลูทูธ');
    expect(statusOf(tester, FootSide.right), 'รอเปิดบลูทูธ');
    await tapAndRun(tester, 'phone-panel-button', const Duration(seconds: 1));
    expect(central.calls, contains('turnOn'));
    expect(byKey('bt-off-panel'), findsNothing);
    await unmount(tester);
  });

  testWidgets('permission refused: the draft panel asks again', (tester) async {
    final perms = FakePermissions(PermissionStatus.denied);
    await pumpConnection(tester, permissions: perms);
    expect(byKey('permission-panel'), findsOneWidget);
    expect(statusOf(tester, FootSide.left), 'รออนุญาตให้ใช้บลูทูธ');
    perms.answer = PermissionStatus.granted;
    await tapAndRun(tester, 'phone-panel-button', const Duration(seconds: 1));
    expect(byKey('permission-panel'), findsNothing);
    expect(statusOf(tester, FootSide.left), 'ยังไม่ได้เชื่อมต่อ');
    await unmount(tester);
  });

  testWidgets('"ยกเลิกการเชื่อมต่อ" disconnects and forgets the insole', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    await pumpConnection(tester, insoles: [leftBoard()], settings: store);
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    expect(store.boundInsole(FootSide.left), 'L1');
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 1));
    expect(statusOf(tester, FootSide.left), 'ยังไม่ได้เชื่อมต่อ');
    expect(store.boundInsole(FootSide.left), isNull);
    await unmount(tester);
  });
}

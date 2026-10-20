import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/debug_ble_screen.dart';

import 'ble/fake_ble_central.dart';
import 'helpers/pump_app.dart';

/// Tall enough that the ListView builds every card.
const debugScreenSize = Size(390, 2400);

/// Lets the fake scan report, connects run and the display tick redraw.
Future<void> settleBle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<FakeBleCentral> openDebug(
  WidgetTester tester, {
  List<FakeInsole> insoles = const [],
  FakePermissions? permissions,
  DateTime Function()? now,
}) async {
  final central = FakeBleCentral(insoles: insoles);
  await pumpApp(
    tester,
    initialRoute: Routes.bleDebug,
    central: central,
    permissions: permissions,
    settle: false,
    size: debugScreenSize,
    now: now,
  );
  await settleBle(tester);
  return central;
}

String stateText(WidgetTester tester, String side) =>
    tester.widget<Text>(byKey('foot-state-$side')).data!;

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(byKey(key));
  await tester.tap(byKey(key));
  await settleBle(tester);
}

void main() {
  testWidgets('Settings opens the BLE debug screen', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    await tester.tap(byKey('ble-debug-button'));
    await settleBle(tester);
    expect(find.byType(DebugBleScreen), findsOneWidget);
    expect(find.text('BLE debug'), findsOneWidget);
  });

  testWidgets('scan lists insoles by id; Connect as LEFT streams', (
    tester,
  ) async {
    await openDebug(
      tester,
      insoles: [
        FakeInsole(id: 'L1', name: 'SMARTINSOLE-L'),
        FakeInsole(id: 'R1', name: 'SMARTINSOLE-R', footSide: 1),
      ],
    );
    expect(find.text('No insole seen yet'), findsOneWidget);
    await tapKey(tester, 'scan-button');
    expect(find.text('L1'), findsOneWidget);
    expect(find.text('R1'), findsOneWidget);

    await tapKey(tester, 'connect-L1-left');
    expect(stateText(tester, 'left'), 'STREAMING · MTU 247 · 8/pkt · N 6');
    expect(stateText(tester, 'right'), 'IDLE');
  });

  testWidgets('the wrong slot shows the Thai rejection, and no stream', (
    tester,
  ) async {
    await openDebug(tester, insoles: [FakeInsole(id: 'L1', footSide: 0)]);
    await tapKey(tester, 'scan-button');
    await tapKey(tester, 'connect-L1-right');
    expect(stateText(tester, 'right'), 'PROBLEM · wrongSide');
    expect(
      find.text('แผ่นรองเท้านี้เป็นข้างซ้าย ใช้เป็นข้างขวาไม่ได้'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an MTU too small for 4 samples is a visible problem', (
    tester,
  ) async {
    await openDebug(tester, insoles: [FakeInsole(id: 'L1', mtu: 23)]);
    await tapKey(tester, 'scan-button');
    await tapKey(tester, 'connect-L1-left');
    expect(stateText(tester, 'left'), 'PROBLEM · mtuTooSmall');
    expect(
      find.textContaining('เชื่อมต่อได้ แต่รับข้อมูลไม่ได้'),
      findsOneWidget,
    );
    expect(
      find.text('MTU 23 fits no packet; 4 samples of N = 6 need MTU 107'),
      findsOneWidget,
    );
  });

  testWidgets('a quiet stream is flagged after 2 s without packets', (
    tester,
  ) async {
    var t = fixedNow;
    final central = await openDebug(
      tester,
      insoles: [FakeInsole(id: 'L1')],
      now: () => t,
    );
    await tapKey(tester, 'scan-button');
    await tapKey(tester, 'connect-L1-left');
    central.insoles['L1']!.link!.sendSensor();
    await settleBle(tester);
    expect(find.textContaining('ไม่ได้รับข้อมูลมา'), findsNothing);
    expect(find.textContaining('1 · 0.10/s'), findsOneWidget);

    // Nothing in the data path runs on a timer: the age is worked out when
    // the card is drawn (rule 2).
    t = t.add(const Duration(seconds: 3));
    await settleBle(tester);
    expect(find.text('ไม่ได้รับข้อมูลมา 3 วินาที'), findsOneWidget);
    expect(stateText(tester, 'left'), startsWith('STREAMING'));
  });

  testWidgets('needs permission → Allow → ready', (tester) async {
    final permissions = FakePermissions(PermissionStatus.denied);
    await openDebug(tester, permissions: permissions);
    expect(find.text('ต้องอนุญาตให้แอปใช้บลูทูธก่อน'), findsOneWidget);
    permissions.answer = PermissionStatus.granted;
    await tapKey(tester, 'ble-readiness-action');
    expect(byKey('ble-readiness'), findsNothing);
  });

  testWidgets('Copy log puts both feet and the event log on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openDebug(tester, insoles: [FakeInsole(id: 'L1')]);
    await tapKey(tester, 'scan-button');
    await tapKey(tester, 'connect-L1-left');
    await tapKey(tester, 'copy-log');
    expect(copied, contains('LEFT: STREAMING'));
    expect(copied, contains('RIGHT: IDLE'));
    expect(copied, contains('MTU requested 247, got 247'));
    expect(find.text('คัดลอกบันทึกแล้ว'), findsOneWidget);
  });
}

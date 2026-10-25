import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/ui/screens/researcher/researcher_model.dart';

import '../connection/connection_rig.dart' show pumpFor;
import '../helpers/pump_app.dart';
import 'researcher_rig.dart';

bool startEnabled(WidgetTester tester) =>
    tester
        .widget<ButtonStyleButton>(
          find.descendant(
            of: byKey('start-capture'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .onPressed !=
    null;

bool rowEnabled(WidgetTester tester, String key) => find
    .descendant(of: byKey(key), matching: find.byType(InkWell))
    .evaluate()
    .isNotEmpty;

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('readiness: the rate check waits for a whole 10 s window, '
      'then every check passes and the start button enables', (tester) async {
    await pumpResearcher(tester);
    expect(find.textContaining('(กำลังวัด)'), findsOneWidget);
    expect(startEnabled(tester), isFalse);
    await pumpFor(tester, const Duration(seconds: 10));
    expect(find.text('เชื่อมต่อแล้วทั้งสองข้าง'), findsOneWidget);
    expect(find.textContaining('รับข้อมูลครบ 50 ครั้ง'), findsOneWidget);
    expect(find.textContaining('(กำลังวัด)'), findsNothing);
    expect(find.bySemanticsLabel('ยังไม่ผ่าน'), findsNothing);
    expect(startEnabled(tester), isTrue);
    await unmount(tester);
  });

  testWidgets('a failed check (battery 10 %) keeps the start button disabled; '
      'the export row still opens capture (6A)', (tester) async {
    await pumpResearcher(tester, preset: MockPreset.lowBattery);
    await pumpFor(tester, const Duration(seconds: 11));
    expect(find.textContaining('ซ้าย 10%'), findsOneWidget);
    expect(startEnabled(tester), isFalse);
    await tester.tap(byKey('researcher-export'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Research capture'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('TARE and reboot are disabled while a capture session is open '
      '(BACKLOG 21)', (tester) async {
    final c = await pumpResearcher(tester);
    expect(rowEnabled(tester, 'researcher-tare'), isTrue);
    expect(rowEnabled(tester, 'researcher-reboot'), isTrue);
    c.read(activeCaptureProvider.notifier).open('S01_20261018_0930');
    await tester.pump();
    expect(rowEnabled(tester, 'researcher-tare'), isFalse);
    expect(rowEnabled(tester, 'researcher-reboot'), isFalse);
    expect(
      find.text('ทั้งสองอย่างทำไม่ได้ระหว่างเก็บข้อมูลวิจัย'),
      findsOneWidget,
    );
    c.read(activeCaptureProvider.notifier).close('S01_20261018_0930');
    await tester.pump();
    expect(rowEnabled(tester, 'researcher-tare'), isTrue);
    await unmount(tester);
  });

  testWidgets('TARE sheet: confirm → in progress → done on both feet', (
    tester,
  ) async {
    await pumpResearcher(tester);
    await tester.tap(byKey('researcher-tare'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(byKey('tare-sheet'), findsOneWidget);
    expect(find.text('ตั้งค่าศูนย์เซนเซอร์'), findsWidgets);
    await tester.tap(byKey('sheet-confirm'));
    await tester.pump();
    expect(byKey('tare-running'), findsOneWidget);
    // No way to cancel a sent TARE.
    expect(byKey('sheet-cancel'), findsNothing);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(byKey('tare-done'), findsOneWidget);
    expect(
      find.text('เท้าซ้าย และ เท้าขวา ตั้งค่าศูนย์เรียบร้อย'),
      findsOneWidget,
    );
    await tester.tap(byKey('sheet-cancel'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(byKey('tare-done'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a capture opened after the sheet: TARE is refused', (
    tester,
  ) async {
    final c = await pumpResearcher(tester);
    await tester.tap(byKey('researcher-tare'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    c.read(activeCaptureProvider.notifier).open('S01_20261018_0930');
    await tester.tap(byKey('sheet-confirm'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(byKey('command-refused'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('reboot: confirm drops both links, and they come back', (
    tester,
  ) async {
    final c = await pumpResearcher(tester);
    await tester.tap(byKey('researcher-reboot'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(byKey('reboot-sheet'), findsOneWidget);
    await tester.tap(byKey('sheet-confirm'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('สั่งรีสตาร์ตแล้ว กำลังเชื่อมต่อกลับ'), findsOneWidget);
    final mock = c.read(mockInsolesProvider)!;
    for (final s in FootSide.values) {
      expect(mock.source(s).state, isNot(isA<LinkStreaming>()));
    }
    await pumpFor(tester, const Duration(seconds: 5));
    for (final s in FootSide.values) {
      expect(mock.source(s).state, isA<LinkStreaming>());
    }
    await unmount(tester);
  });

  testWidgets('device info shows firmware, MTU and the measured rate', (
    tester,
  ) async {
    await pumpResearcher(tester);
    await pumpFor(tester, const Duration(seconds: 10));
    // Both feet agree: one value, as on the board.
    expect(find.text('50 ครั้ง/วินาที ต่อข้าง'), findsOneWidget);
    await unmount(tester);
  });

  test('agreedOrPerFoot: one value when both agree, else per foot', () {
    expect(agreedOrPerFoot((_) => '247'), '247');
    expect(
      agreedOrPerFoot(
        (s) => s == FootSide.left ? '50' : '31',
        unit: ' ครั้ง/วินาที',
        bothNote: ' ต่อข้าง',
      ),
      'ซ้าย 50 · ขวา 31 ครั้ง/วินาที',
    );
    expect(agreedOrPerFoot((_) => null), 'ซ้าย — · ขวา —');
  });
}

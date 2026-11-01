import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/storage/storage_providers.dart';

import '../connection/connection_rig.dart' show pumpFor;
import 'researcher_rig.dart';

/// Researcher › "บันทึกค่ายืนนิ่ง 30 วินาที" (S9) on the mock insoles.
void main() {
  Future<void> open(WidgetTester tester) async {
    final row = find.byKey(const ValueKey('researcher-baseline-row'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await pumpFor(tester, const Duration(seconds: 1));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('standing still 30 s: saved per insole, the card says so', (
    tester,
  ) async {
    final c = await pumpResearcher(tester, preset: MockPreset.standing);
    expect(
      find.text('ยังไม่ได้บันทึก: ซ้าย, ขวา'),
      findsOneWidget,
      reason: 'the Researcher card before any recording',
    );
    await open(tester);
    expect(find.text('บันทึกค่ายืนนิ่ง 30 วินาที'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('baseline-start')));
    await pumpFor(tester, const Duration(seconds: 10));
    expect(
      find.byKey(const ValueKey('baseline-progress-left')),
      findsOneWidget,
    );
    await pumpFor(tester, const Duration(seconds: 22));
    expect(find.byKey(const ValueKey('baseline-saved')), findsOneWidget);
    final db = c.read(databaseProvider);
    final rows = await tester.runAsync(() => db.select(db.baselines).get());
    expect(rows!.map((r) => r.insoleId).toSet(), {'MOCK-L-001', 'MOCK-R-001'});
    expect(rows.every((r) => r.sampleCount >= 1490), isTrue);

    await tester.tap(find.byKey(const ValueKey('back-link')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('บันทึกแล้วทั้งสองข้าง'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('walking: refused with the reason, nothing saved', (
    tester,
  ) async {
    final c = await pumpResearcher(tester, preset: MockPreset.safe);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('baseline-start')));
    await pumpFor(tester, const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('baseline-failed')), findsOneWidget);
    expect(find.textContaining('Movement detected'), findsOneWidget);
    final db = c.read(databaseProvider);
    expect(await tester.runAsync(() => db.select(db.baselines).get()), isEmpty);
    expect(find.text('บันทึกใหม่'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no insole connected: start disabled', (tester) async {
    await pumpResearcher(tester, preset: MockPreset.noData);
    // The mock keeps its calibration while not streaming (as a BLE source
    // does after a disconnect): the card must still say "connect first".
    expect(find.text('เชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน'), findsOneWidget);
    await open(tester);
    expect(find.text('เท้าซ้าย · ไม่ได้เชื่อมต่อ'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('baseline-start')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(start.onPressed, isNull);
    expect(
      find.textContaining('Both insoles must be streaming'),
      findsOneWidget,
    );
    await unmount(tester);
  });
}

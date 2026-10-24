import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/pressure_level.dart';
import 'package:smartinsole/ui/widgets/foot_map.dart';

Future<void> pumpMap(
  WidgetTester tester,
  List<PressureLevel>? levels, {
  bool reduced = false,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: FootMap(
          side: FootSide.left,
          levels: levels,
          semanticLabel: 'เท้าซ้าย',
          width: 84,
          height: 188,
        ),
      ),
    ),
  ),
);

void main() {
  const low = PressureLevel.low;
  final allLow = List.filled(6, low);
  final oneHigh = [PressureLevel.high, ...List.filled(5, low)];

  testWidgets('a high dot pulses', (tester) async {
    await pumpMap(tester, oneHigh);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduce motion: no pulse, the ring stays still', (tester) async {
    await pumpMap(tester, oneHigh, reduced: true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('no high dot, no pulse layer', (tester) async {
    await pumpMap(tester, allLow);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a level change tweens, and a retarget mid-tween continues '
      'from where it is', (tester) async {
    await pumpMap(tester, allLow);
    await pumpMap(tester, [PressureLevel.medium, ...List.filled(5, low)]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    // A 10 Hz update with the same levels does not restart anything.
    await pumpMap(tester, [PressureLevel.medium, ...List.filled(5, low)]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce motion: a level change is immediate', (tester) async {
    await pumpMap(tester, allLow, reduced: true);
    await pumpMap(tester, [
      PressureLevel.medium,
      ...List.filled(5, low),
    ], reduced: true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}

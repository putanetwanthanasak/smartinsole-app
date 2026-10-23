import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/ui/screens/home/home_copy.dart';
import 'package:smartinsole/ui/screens/home/home_model.dart';
import 'package:smartinsole/ui/screens/home_screen.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';
import 'package:smartinsole/ui/theme/colors.dart';

import '../helpers/pump_app.dart';
import 'home_rig.dart';

/// Every string Home renders.
List<String> homeTexts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: find.byType(HomeScreen), matching: find.byType(Text)),
  ))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

Color statusBackground(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: byKey('status-card'),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

Finder inCard(String key, Finder f) =>
    find.descendant(of: byKey(key), matching: f);

void main() {
  const greens = [
    // Safe, and the connected chip dot.
    Color(0xFFE2F2E8),
    Color(0xFF2E7D4F),
    Color(0xFF1B5536),
  ];

  group('copy per preset (DESIGN-SPEC §6)', () {
    for (final (preset, title, detail, advice) in [
      (
        MockPreset.safe,
        'ตอนนี้เท้าปลอดภัย',
        'น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ',
        null,
      ),
      (
        MockPreset.safeOrangeDot,
        'ตอนนี้เท้าปลอดภัย',
        'น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ',
        null,
      ),
      (
        MockPreset.watch,
        'ควรระวัง',
        'ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป',
        'ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่',
      ),
      (
        MockPreset.rest,
        'ควรพักเท้าตอนนี้',
        'เท้าขวาอุ่นกว่าเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก',
        'นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม '
            'ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์',
      ),
      (
        MockPreset.noData,
        'ยังไม่ได้รับข้อมูล',
        'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่',
        null,
      ),
      (
        MockPreset.oneFootMissing,
        'ยังไม่ได้รับข้อมูล',
        'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่',
        null,
      ),
      (
        MockPreset.lowBattery,
        'ตอนนี้เท้าปลอดภัย',
        'น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ',
        null,
      ),
    ]) {
      testWidgets(preset.name, (tester) async {
        await pumpHome(tester, preset);
        expect(inCard('status-card', find.text(title)), findsOneWidget);
        expect(inCard('status-card', find.text(detail)), findsOneWidget);
        if (advice == null) {
          expect(
            inCard('status-card', find.text('สิ่งที่ควรทำตอนนี้')),
            findsNothing,
          );
        } else {
          expect(inCard('status-card', find.text(advice)), findsOneWidget);
        }
        final noData =
            preset == MockPreset.noData || preset == MockPreset.oneFootMissing;
        expect(byKey('connect-button'), noData ? findsOneWidget : findsNothing);

        // Never the terms or units kPa, ΔT, PAI on Home.
        for (final t in homeTexts(tester)) {
          for (final banned in ['kPa', 'ΔT', 'PAI', 'kpa']) {
            expect(t.contains(banned), isFalse, reason: '"$t"');
          }
        }
        await unmount(tester);
      });
    }
  });

  group('No data is never green (rule 5)', () {
    for (final preset in [MockPreset.noData, MockPreset.oneFootMissing]) {
      testWidgets(preset.name, (tester) async {
        await pumpHome(tester, preset);
        final bg = statusBackground(tester);
        expect(bg, StatusColors.noData.background);
        expect(greens, isNot(contains(bg)));
        await unmount(tester);
      });
    }

    testWidgets('no insole at all (real BLE stack, nothing connected)', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('ยังไม่ได้รับข้อมูล'), findsOneWidget);
      expect(statusBackground(tester), StatusColors.noData.background);
      expect(find.text('ไม่ได้เชื่อมต่อ'), findsNWidgets(2));
    });
  });

  group('two-foot values need both feet (rule 4)', () {
    testWidgets('one foot missing: "—" and "ต้องเชื่อมต่อทั้งสองข้าง"', (
      tester,
    ) async {
      await pumpHome(tester, MockPreset.oneFootMissing);
      for (final card in ['temp-card', 'balance-card']) {
        expect(inCard(card, find.text('—')), findsOneWidget, reason: card);
        expect(inCard(card, find.text(needBothFeet)), findsOneWidget);
      }
      // The connected foot still shows its own data.
      expect(inCard('foot-left', find.text('แบต 92%')), findsOneWidget);
      expect(
        inCard('foot-right', find.text('ไม่ได้เชื่อมต่อ')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('เท้าซ้าย แรงกดกระจายดี'), findsOneWidget);
      expect(find.bySemanticsLabel('เท้าขวา ยังไม่มีข้อมูล'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('both feet: ΔT and balance shown', (tester) async {
      await pumpHome(tester, MockPreset.safe);
      expect(inCard('temp-card', find.text('—')), findsNothing);
      expect(inCard('temp-card', find.text('0.3°')), findsOneWidget);
      expect(
        inCard('temp-card', find.text('สองข้างอุ่นใกล้เคียงกัน')),
        findsOneWidget,
      );
      expect(inCard('balance-card', find.text('50 : 50')), findsOneWidget);
      expect(
        inCard('balance-card', find.text('ซ้ายและขวาพอ ๆ กัน')),
        findsOneWidget,
      );
      await unmount(tester);
    });
  });

  testWidgets('rest: the warmer foot is named, the note warns', (tester) async {
    await pumpHome(tester, MockPreset.rest);
    expect(inCard('temp-card', find.text('2.6°')), findsOneWidget);
    expect(
      inCard('temp-card', find.text('เท้าขวาอุ่นกว่าปกติ')),
      findsOneWidget,
    );
    expect(
      inCard('temp-card', find.byIcon(LucideIcons.octagon_alert)),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('watch: the heavier foot is named, in the Be-careful style', (
    tester,
  ) async {
    await pumpHome(tester, MockPreset.watch);
    expect(
      inCard('balance-card', find.text('ลงน้ำหนักเท้าซ้ายมากกว่า')),
      findsOneWidget,
    );
    expect(
      inCard('balance-card', find.byIcon(LucideIcons.triangle_alert)),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('safeOrangeDot: Safe card, orange dot on the left map', (
    tester,
  ) async {
    await pumpHome(tester, MockPreset.safeOrangeDot);
    expect(statusBackground(tester), StatusColors.safe.background);
    expect(
      find.bySemanticsLabel('เท้าซ้าย ปลายเท้ารับน้ำหนักปานกลาง'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('เท้าขวา แรงกดกระจายดี'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('lowBattery: amber text and battery icon on that chip only', (
    tester,
  ) async {
    await pumpHome(tester, MockPreset.lowBattery);
    expect(
      inCard('foot-left', find.byIcon(LucideIcons.battery_low)),
      findsOneWidget,
    );
    expect(
      inCard('foot-right', find.byIcon(LucideIcons.battery_low)),
      findsNothing,
    );
    final text = tester.widget<Text>(inCard('foot-left', find.text('แบต 10%')));
    expect(text.style!.color, StatusColors.careful.text);
    await unmount(tester);
  });

  group('accessibility (DESIGN-SPEC §13)', () {
    testWidgets('the status card is a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      final node = tester.getSemantics(byKey('status-card'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });

    testWidgets('icon-only settings button has its Thai label', (tester) async {
      await pumpApp(tester);
      expect(find.byTooltip('ตั้งค่า'), findsOneWidget);
    });

    testWidgets('TalkBack can activate every tab', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      for (final tab in ['myFeet', 'footCheck', 'alerts', 'today']) {
        // Performs the semantics tap action; throws if there is none.
        tester.semantics.tap(
          find.semantics.byPredicate(
            (n) => n.label == tester.getSemantics(byKey('tab-$tab')).label,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(byKey('tab-$tab')),
          isSemantics(isSelected: true, hasTapAction: true),
          reason: tab,
        );
      }
      semantics.dispose();
    });

    for (final (count, label) in [
      (0, 'แจ้งเตือน'),
      (3, 'แจ้งเตือน มี 3 รายการที่ยังไม่ได้อ่าน'),
    ]) {
      testWidgets('Alerts tab with $count unread', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpApp(
          tester,
          overrides: [unreadAlertCountProvider.overrideWithValue(count)],
        );
        expect(find.bySemanticsLabel(label), findsOneWidget);
        expect(
          byKey('alerts-badge'),
          count == 0 ? findsNothing : findsOneWidget,
        );
        // The badge number is not read on its own.
        expect(find.bySemanticsLabel('$count'), findsNothing);
        semantics.dispose();
      });
    }

    for (final preset in MockPreset.values) {
      testWidgets('nothing overflows at 200 % text: ${preset.name}', (
        tester,
      ) async {
        await pumpHome(tester, preset, textScale: 2);
        // A RenderFlex overflow would have failed the test already.
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(byKey('balance-card'), 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  });

  group('motion', () {
    testWidgets('reduce motion: Home appears without the entrance', (
      tester,
    ) async {
      await pumpApp(tester, settle: false, reduceMotion: true);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      final opacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities, isNotEmpty);
      expect(opacities.every((o) => o.opacity == 1), isTrue);
    });

    testWidgets('with motion: the entrance plays', (tester) async {
      await pumpApp(tester, settle: false);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('10 Hz snapshots do not rebuild Home while nothing visible '
        'changes', (tester) async {
      await pumpHome(tester, MockPreset.safe);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      var changes = 0;
      final sub = container.listen(homeViewProvider, (_, _) => changes++);
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 50 ticks of steady walking: at most the odd rounding change.
      expect(changes, lessThanOrEqualTo(2));
      sub.close();
      await unmount(tester);
    });
  });
}

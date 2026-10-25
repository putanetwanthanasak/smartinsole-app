import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/gait/demo_model_runner.dart';
import 'package:smartinsole/gait/gait_providers.dart';
import 'package:smartinsole/gait/model_classifier.dart';
import 'package:smartinsole/rules/alert_providers.dart';
import 'package:smartinsole/ui/screens/connection_screen.dart';
import 'package:smartinsole/ui/screens/my_feet/gait_model.dart';
import 'package:smartinsole/ui/shell/app_shell.dart' show MyFeetTab;
import 'package:smartinsole/ui/theme/colors.dart';
import 'package:smartinsole/ui/widgets/balance_bar.dart';
import 'package:smartinsole/ui/widgets/confidence_segments.dart';

import '../alerts/alerts_rig.dart' show containerOf;
import '../gait/gait_rig.dart';
import '../helpers/pump_app.dart';
import 'my_feet_rig.dart';

Finder _in(String key, Finder f) =>
    find.descendant(of: byKey(key), matching: f);

/// A model in the slot that always answers [probs].
Override modelAnswering(List<double> probs) => modelSlotProvider.overrideWith(
  (ref) async => ModelReady(
    'test',
    ModelClassifier(
      runner: FakeRunner(probs),
      normalization: demoNormalization(testModelInput),
    ),
  ),
);

final demoToe = gaitModelChoiceProvider.overrideWithValue(
  GaitModelChoice.demoToe,
);

Future<void> pumpGait(
  WidgetTester tester,
  MockPreset preset, {
  List<Override> overrides = const [],
  bool reduceMotion = false,
  double textScale = 1.0,
  Size size = const Size(390, 2300),
}) => pumpMyFeet(
  tester,
  preset,
  tab: MyFeetTab.gait,
  overrides: overrides,
  reduceMotion: reduceMotion,
  textScale: textScale,
  size: size,
);

/// My feet › "การเดิน" (DESIGN-SPEC §8.3) on the mock presets, with no
/// model (rules), the demo model and a model below `minConfidence`.
void main() {
  group('no model: the rules', () {
    testWidgets('safe walk: walking, normal, the rule-based line', (
      tester,
    ) async {
      await pumpGait(tester, MockPreset.safe);
      expect(_in('gait-now-card', find.text('กำลังเดิน')), findsOneWidget);
      expect(_in('gait-estimate-card', find.text('เดินปกติ')), findsOneWidget);
      expect(find.text('เดินตามธรรมชาติ'), findsOneWidget);
      expect(
        find.text('ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม'),
        findsOneWidget,
      );
      expect(find.text('ค่าประมาณ ไม่ใช่การวินิจฉัย'), findsOneWidget);
      expect(
        find.text(
          'ท่าเดินใช้ประกอบคำแนะนำเท่านั้น ไม่ได้ใช้ตัดสินว่าเท้าปลอดภัยหรือไม่',
        ),
        findsOneWidget,
      );
      expect(byKey('gait-confidence'), findsNothing);
      // ~62 s at a 1.1 s stride, both feet.
      final steps = containerOf(tester).read(gaitViewProvider).stepsToday;
      expect(steps, inInclusiveRange(100, 120));
      expect(find.text('การลงน้ำหนักซ้าย–ขวา'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('toeWalk: toe walking', (tester) async {
      await pumpGait(tester, MockPreset.toeWalk);
      expect(find.text('เดินเขย่งปลายเท้า'), findsOneWidget);
      expect(find.text('ส้นเท้าแตะพื้นน้อยหรือไม่แตะ'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('details: PAI, PTI asymmetry, source, window, CoP', (
      tester,
    ) async {
      await pumpGait(tester, MockPreset.safe);
      await openDetails(tester);
      expect(find.textContaining('(เฝ้าระวังเมื่อเกิน 15%)'), findsOneWidget);
      expect(
        find.textContaining('(ค่าอ้างอิง 20% · ยังไม่ใช้แจ้งเตือน)'),
        findsOneWidget,
      );
      expect(find.text('กฎพื้นฐาน (โมเดล AI ยังไม่พร้อม)'), findsOneWidget);
      expect(find.text('ช่วงละ 2 วินาที ประเมินทุก 1 วินาที'), findsOneWidget);
      expect(byKey('gait-probabilities'), findsNothing);
      expect(byKey('gait-cop'), findsOneWidget);
      final v = containerOf(tester).read(gaitViewProvider);
      expect(v.copLeft, isNotEmpty);
      expect(v.copRight, isNotEmpty);
      await unmount(tester);
    });
  });

  testWidgets('standing: still, no result now, standing balance', (
    tester,
  ) async {
    await pumpGait(tester, MockPreset.standing);
    expect(_in('gait-now-card', find.text('ยืนหรือนั่งอยู่')), findsOneWidget);
    expect(find.text('ยังไม่มีผลตอนนี้'), findsOneWidget);
    expect(
      find.text('ระบบจะประเมินท่าเดินเมื่อคุณเดินต่อเนื่องสักครู่'),
      findsOneWidget,
    );
    // Never walked in this run: no last result.
    expect(byKey('gait-last'), findsNothing);
    expect(find.text('การลงน้ำหนักซ้าย–ขวา ขณะยืน'), findsOneWidget);
    expect(_in('gait-balance-card', find.text('47 : 53')), findsOneWidget);
    expect(find.text('ซ้ายและขวาพอ ๆ กัน'), findsOneWidget);
    await openDetails(tester);
    // PAI(142, 162) = 13 %.
    expect(find.text('13%'), findsOneWidget);
    expect(byKey('gait-cop'), findsNothing);
    await unmount(tester);
  });

  testWidgets('after walking: "ผลล่าสุด" with the time and class', (
    tester,
  ) async {
    await pumpGait(tester, MockPreset.safe);
    final container = containerOf(tester);
    container.read(mockInsolesProvider)!.preset = MockPreset.standing;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('ยังไม่มีผลตอนนี้'), findsOneWidget);
    expect(
      tester.widget<Text>(byKey('gait-last')).data,
      matches(RegExp(r'^ผลล่าสุด \d\d:\d\d · เดินปกติ$')),
    );
    await openDetails(tester);
    expect(find.textContaining('· เดินปกติ (กฎพื้นฐาน)'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'PAI detail: the step PAI only while walking, else the standing one',
    (tester) async {
      await pumpGait(tester, MockPreset.safe);
      await openDetails(tester);
      expect(find.text('ความไม่สมดุลของแรงกด (PAI)'), findsOneWidget);
      final container = containerOf(tester);
      expect(container.read(gaitViewProvider).walkingPaiPct, isNotNull);

      // Stopped: no walking step within steps.maxStanceMs. The engine
      // still holds its last step-pair PAI, but it is not shown.
      container.read(mockInsolesProvider)!.preset = MockPreset.standing;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(container.read(alertEngineProvider).latestPaiPct, isNotNull);
      final v = container.read(gaitViewProvider);
      expect(v.activity, GaitActivity.still);
      expect(v.walkingPaiPct, isNull);
      expect(find.text('ความไม่สมดุลของแรงกด (PAI)'), findsNothing);
      expect(find.text('ความไม่สมดุลของแรงกดขณะยืน'), findsOneWidget);
      expect(find.text('${v.standingPaiPct}%'), findsOneWidget);

      // One foot gone: "—" with the reason (rule 4).
      container.read(mockInsolesProvider)!.preset = MockPreset.oneFootMissing;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        find.text('— (ต้องเชื่อมต่อทั้งสองข้าง)'),
        findsAtLeastNWidgets(1),
      );
      await unmount(tester);
    },
  );

  testWidgets('no data shows no data: no "ผลล่าสุด" once a foot is gone', (
    tester,
  ) async {
    await pumpGait(tester, MockPreset.safe);
    final container = containerOf(tester);
    container.read(mockInsolesProvider)!.preset = MockPreset.oneFootMissing;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(container.read(gaitEstimatorProvider).last, isNotNull);
    expect(byKey('gait-no-data'), findsOneWidget);
    expect(byKey('gait-last'), findsNothing);
    await openDetails(tester);
    expect(find.textContaining('ผลประเมินล่าสุด'), findsNothing);
    await unmount(tester);
  });

  group('two feet needed (rule 4)', () {
    for (final preset in [MockPreset.noData, MockPreset.oneFootMissing]) {
      testWidgets('${preset.name}: no estimate, connect, balance "—"', (
        tester,
      ) async {
        await pumpGait(tester, preset);
        expect(byKey('gait-no-data'), findsOneWidget);
        expect(
          find.text('ต้องเชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน'),
          findsOneWidget,
        );
        expect(byKey('gait-class'), findsNothing);
        expect(byKey('gait-balance-none'), findsOneWidget);
        expect(
          _in('gait-balance-card', find.text('ต้องเชื่อมต่อทั้งสองข้าง')),
          findsOneWidget,
        );
        final now = tester.widget<Text>(byKey('gait-now'));
        if (preset == MockPreset.noData) {
          expect(now.data, '—');
          expect(now.style!.color, AppColors.inkMuted);
        } else {
          expect(now.data, 'กำลังเดิน');
        }
        await tester.tap(byKey('gait-connect'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ConnectionScreen), findsOneWidget);
        await unmount(tester);
      });
    }
  });

  group('model', () {
    testWidgets('demo-toe: model result, 2 segments "ปานกลาง", probabilities', (
      tester,
    ) async {
      await pumpGait(tester, MockPreset.safe, overrides: [demoToe]);
      expect(find.text('เดินเขย่งปลายเท้า'), findsOneWidget);
      expect(byKey('gait-rules-line'), findsNothing);
      final segments = tester.widget<ConfidenceSegments>(
        find.byType(ConfidenceSegments),
      );
      expect(segments.filled, 2);
      expect(_in('gait-confidence', find.text('ปานกลาง')), findsOneWidget);
      await openDetails(tester);
      expect(find.text('78% (ใช้ผลเมื่อ 60% ขึ้นไป)'), findsOneWidget);
      expect(find.text('โมเดล AI (Model A)'), findsOneWidget);
      expect(byKey('gait-probabilities'), findsOneWidget);
      expect(_in('gait-probabilities', find.text('78%')), findsOneWidget);
      expect(_in('gait-probabilities', find.text('6%')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('high confidence: 3 segments "สูง"', (tester) async {
      await pumpGait(
        tester,
        MockPreset.safe,
        overrides: [
          modelAnswering([0.9, 0.04, 0.02, 0.02, 0.02]),
        ],
      );
      expect(find.text('เดินปกติ'), findsOneWidget);
      expect(
        tester
            .widget<ConfidenceSegments>(find.byType(ConfidenceSegments))
            .filled,
        3,
      );
      expect(_in('gait-confidence', find.text('สูง')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('below minConfidence: the rules, saying the model is unsure', (
      tester,
    ) async {
      await pumpGait(
        tester,
        MockPreset.toeWalk,
        overrides: [
          modelAnswering([0.5, 0.2, 0.1, 0.1, 0.1]),
        ],
      );
      expect(find.text('เดินเขย่งปลายเท้า'), findsOneWidget);
      expect(
        find.text('ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่มั่นใจพอ'),
        findsOneWidget,
      );
      expect(byKey('gait-confidence'), findsNothing);
      await openDetails(tester);
      expect(find.text('กฎพื้นฐาน (โมเดล AI ยังไม่มั่นใจพอ)'), findsOneWidget);
      expect(byKey('gait-probabilities'), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('ASYMMETRY_PEAK: balance number and note in Be-careful colours', (
    tester,
  ) async {
    await pumpGait(tester, MockPreset.watch);
    expect(byKey('gait-balance-warning'), findsOneWidget);
    expect(
      _in('gait-balance-card', find.byIcon(LucideIcons.triangle_alert)),
      findsOneWidget,
    );
    final note = tester.widget<Text>(
      _in('gait-balance-card', find.text('ลงน้ำหนักเท้าซ้ายมากกว่า')),
    );
    expect(note.style!.color, StatusColors.careful.text);
    await unmount(tester);
  });

  testWidgets('10 Hz snapshots rebuild the tab only when something changes', (
    tester,
  ) async {
    await pumpGait(tester, MockPreset.standing);
    final container = containerOf(tester);
    var changes = 0;
    final sub = container.listen(gaitViewProvider, (_, _) => changes++);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(changes, 0);
    sub.close();
    await unmount(tester);
  });

  group('motion (§12.2, rule 16)', () {
    double barLeft(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(BalanceBar),
          matching: find.byType(CustomPaint),
        ),
      );
      return (paint.painter! as dynamic).left as double;
    }

    for (final reduce in [false, true]) {
      testWidgets(
        reduce
            ? 'reduce motion: the balance bar is at its value at once'
            : 'the balance bar grows from 50 : 50 when the tab opens',
        (tester) async {
          await pumpMyFeet(tester, MockPreset.standing, reduceMotion: reduce);
          await tester.tap(byKey('my-feet-tab-gait'));
          await tester.pump();
          await tester.pump();
          expect(barLeft(tester), reduce ? closeTo(0.47, 1e-9) : 0.5);
          await tester.pump(const Duration(seconds: 1));
          expect(barLeft(tester), closeTo(0.47, 1e-9));
          await unmount(tester);
        },
      );
    }
  });
}

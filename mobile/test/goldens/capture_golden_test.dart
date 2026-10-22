@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/capture/capture_protocol.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/capture/capture_flow_screen.dart';

import '../capture/widget_rig.dart';
import '../helpers/pump_app.dart';

/// Research capture screens (S4C). Regenerate with:
///   flutter test --update-goldens test/goldens
void main() {
  late WidgetRig rig;
  setUp(() => rig = WidgetRig());
  tearDown(() => rig.dispose());

  // One display tick and the text fields' label animation first.
  Future<void> golden(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screens/$name.png'),
    );
  }

  group('capture', () {
    testWidgets('capture_home', (tester) async {
      await pumpApp(
        tester,
        initialRoute: Routes.capture,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(byKey('capture-code'), 'SI-001');
      await tester.pump();
      await golden(tester, 'capture_home');
    });

    testWidgets('capture_home_foot_ineligible', (tester) async {
      await pumpApp(
        tester,
        initialRoute: Routes.capture,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(byKey('capture-code'), 'SI-001');
      await tester.enterText(byKey('capture-foot-l'), '26.0');
      await tester.enterText(byKey('capture-foot-r'), '25.0');
      await tester.pump();
      // The fields and the message mid-screen (the list clamps at its end).
      Scrollable.ensureVisible(
        tester.element(byKey('capture-foot-l')),
        alignment: 0.3,
      );
      await tester.pump();
      await golden(tester, 'capture_home_foot_ineligible');
    });

    testWidgets('capture_home_precheck_fail', (tester) async {
      rig = WidgetRig(rightBattery: 79);
      rig.left.set(const LinkSearching(deviceId: 'X'));
      await pumpApp(
        tester,
        initialRoute: Routes.capture,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await golden(tester, 'capture_home_precheck_fail');
    });

    testWidgets('capture_ready_calibration', (tester) async {
      await pumpCapture(
        tester,
        rig,
        CaptureFlowScreen(session: rig.newSession()),
      );
      await golden(tester, 'capture_ready_calibration');
    });

    testWidgets('capture_ready_rotated', (tester) async {
      final s = rig.newSession(seed: seedWith(GaitClass.rotatedFoot));
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await finishTrial(tester, rig);
      await finishTrial(tester, rig);
      expect(s.current.plan.gait, GaitClass.rotatedFoot);
      await golden(tester, 'capture_ready_rotated');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('capture_practice', (tester) async {
      final s = rig.newSession(code: 'TEST-002');
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await finishTrial(tester, rig);
      await tapScrolled(tester, 'capture-practice');
      await rig.walk(tester, const Duration(seconds: 2));
      await golden(tester, 'capture_practice');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('capture_recording', (tester) async {
      final s = rig.newSession(seed: seedWith(GaitClass.antalgic));
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await finishTrial(tester, rig);
      await finishTrial(tester, rig);
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 5));
      await golden(tester, 'capture_recording');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('capture_recording_link_lost_marked', (tester) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await finishTrial(tester, rig);
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 2));
      await hold(tester, 'capture-mark', const Duration(seconds: 3));
      rig
        ..rightOn = false
        ..right.set(const LinkSearching(deviceId: 'X'));
      await rig.walk(tester, const Duration(seconds: 1));
      await golden(tester, 'capture_recording_link_lost_marked');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('capture_saved', (tester) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 3));
      rig.left.seq += 3;
      rig.left.packet(missingBefore: 3);
      await rig.walk(tester, const Duration(seconds: 9));
      rig.t = rig.t.add(const Duration(seconds: 83));
      await tester.pump(const Duration(seconds: 1));
      await golden(tester, 'capture_saved');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('capture_summary', (tester) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await finishTrial(tester, rig);
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 31));
      await tapScrolled(tester, 'capture-redo');
      await tester.tap(byKey('capture-redo-confirm'));
      await tester.pump();
      await tester.tap(byKey('capture-summary-button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await golden(tester, 'capture_summary');
      await tester.pumpWidget(const SizedBox());
    });
  });
}

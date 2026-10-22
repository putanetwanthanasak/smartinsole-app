import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/capture/capture_files.dart';
import 'package:smartinsole/capture/capture_session.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/capture/capture_flow_screen.dart';

import '../helpers/pump_app.dart';
import 'widget_rig.dart';

void main() {
  late WidgetRig rig;
  setUp(() => rig = WidgetRig());
  tearDown(() => rig.dispose());

  group('home', () {
    testWidgets('Settings opens research capture', (tester) async {
      await pumpApp(
        tester,
        initialRoute: Routes.settings,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.tap(byKey('capture-button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Research capture'), findsOneWidget);
    });

    testWidgets('a name is never accepted as a code', (tester) async {
      await pumpApp(
        tester,
        initialRoute: Routes.capture,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(byKey('capture-code'), 'Somchai');
      await tester.pump();
      expect(find.text('Use SI-nnn or TEST-nnn'), findsOneWidget);
      final start = tester.widget<FilledButton>(byKey('capture-start'));
      expect(start.onPressed, isNull);
    });

    testWidgets('start: creates the session and opens calibration', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: Routes.capture,
        now: rig.now,
        overrides: rig.overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(byKey('capture-code'), 'si-003');
      await tester.pump();
      expect(find.textContaining('Antalgic pain side: left'), findsOneWidget);
      await tester.ensureVisible(byKey('capture-start'));
      await tester.pump();
      await tester.tap(byKey('capture-start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Standing still'), findsOneWidget);
      expect(rig.wakelock, [true]);
      expect(
        File('${rig.research.path}/SI-003_20261110-090000/session.json')
            .existsSync(),
        isTrue,
      );
      // Leaving the flow lets the screen sleep again.
      await tester.tap(find.byTooltip('กลับ'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.wakelock, [true, false]);
      expect(
        find.byKey(const ValueKey('capture-session-SI-003_20261110-090000')),
        findsOneWidget,
      );
    });

    testWidgets('pre-check blocks a 79 % battery', (tester) async {
      rig = WidgetRig(rightBattery: 79);
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
      expect(find.textContaining('battery 79 % < 80 %'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(byKey('capture-start')).onPressed,
        isNull,
      );
    });
  });

  group('flow', () {
    testWidgets('recording: Back is blocked; a short touch does nothing; '
        'a 2 s hold stops', (tester) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await tapScrolled(tester, 'capture-record');
      expect(s.phase, CapturePhase.recording);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CaptureFlowScreen), findsOneWidget);

      await tester.tap(byKey('capture-stop'));
      await hold(tester, 'capture-stop', const Duration(seconds: 1));
      expect(s.phase, CapturePhase.recording);
      await hold(
        tester,
        'capture-stop',
        const Duration(seconds: 2, milliseconds: 50),
      );
      expect(s.phase, CapturePhase.saving);
      await tester.pump(const Duration(seconds: 1));
      expect(s.phase, CapturePhase.saved);
      expect(s.attempt!.endReason, EndReason.stoppedEarly);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('redo asks first, then keeps a1 and records a2', (
      tester,
    ) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 11));
      await tapScrolled(tester, 'capture-redo');
      await tester.tap(byKey('capture-redo-confirm'));
      await tester.pump();
      expect(s.phase, CapturePhase.ready);
      final a1 = readJson(
        File('${s.dir.path}/TEST-001_00_calibration_a1.json'),
      );
      expect(a1['invalidReason'], 'redo');
      expect(find.textContaining('attempt 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a foot dropping mid-recording shows a banner and cues', (
      tester,
    ) async {
      final s = rig.newSession();
      await pumpCapture(tester, rig, CaptureFlowScreen(session: s));
      await tapScrolled(tester, 'capture-record');
      await rig.walk(tester, const Duration(seconds: 2));
      rig
        ..rightOn = false
        ..right.set(const LinkSearching(deviceId: 'X'));
      await rig.walk(tester, const Duration(seconds: 1));
      expect(byKey('capture-link-lost-right'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

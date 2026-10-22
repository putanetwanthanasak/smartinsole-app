import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_protocol.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/capture/capture_session.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/ui/screens/capture/capture_flow_screen.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/theme/app_theme.dart';

import '../device/fake_source.dart';
import '../helpers/pump_app.dart';
import 'capture_rig.dart';

/// [CaptureRig] for widget tests: the tester's fake timers drive the
/// session; the wall clock [t] moves with every [walk].
class WidgetRig {
  WidgetRig({int leftBattery = 90, int rightBattery = 85}) {
    left = FakeSource(FootSide.left, now: now)
      ..calibration = fakeCalibration('L-001');
    right = FakeSource(FootSide.right, now: now)
      ..calibration = fakeCalibration('R-001');
    manager = DeviceManager(left: left, right: right, now: now);
    root = Directory.systemTemp.createTempSync('capture_widget_');
    left
      ..stream()
      ..status(battery: leftBattery)
      ..packet();
    right
      ..stream()
      ..status(battery: rightBattery)
      ..packet();
  }

  DateTime t = DateTime(2026, 11, 10, 9);
  DateTime now() => t;
  late final FakeSource left;
  late final FakeSource right;
  late final DeviceManager manager;
  late final Directory root;
  final cues = FakeCues();
  final wakelock = <bool>[];
  bool rightOn = true;

  Directory get research => Directory('${root.path}/research');
  Directory get export => Directory('${root.path}/export');

  CaptureDeps get deps => CaptureDeps(
    manager: manager,
    sources: {FootSide.left: left, FootSide.right: right},
    cues: cues,
    now: now,
    appVersion: '1.0.0+1',
  );

  CaptureSession newSession({String code = 'TEST-001', int seed = 7}) =>
      CaptureSession.create(
        deps: deps,
        researchRoot: research,
        subject: SubjectInfo(code: SubjectCode.parse(code)!),
        roomTempC: 25.5,
        seed: seed,
      );

  List<Override> get overrides => [
    deviceManagerProvider.overrideWithValue(manager),
    insoleDataSourceProvider.overrideWith(
      (ref, side) => side == FootSide.left ? left : right,
    ),
    captureCuesProvider.overrideWithValue(cues),
    wakelockProvider.overrideWithValue((on) async => wakelock.add(on)),
    researchRootProvider.overrideWithValue(Future.value(research)),
    exportRootProvider.overrideWithValue(Future.value(export)),
    appVersionProvider.overrideWithValue(Future.value('1.0.0+1')),
  ];

  /// Packets every 160 ms on both feet while fake time passes.
  Future<void> walk(WidgetTester tester, Duration d) async {
    for (var k = 0; k < d.inMilliseconds ~/ 160; k++) {
      t = t.add(const Duration(milliseconds: 153));
      await tester.pump(const Duration(milliseconds: 153));
      left.packet();
      t = t.add(const Duration(milliseconds: 7));
      await tester.pump(const Duration(milliseconds: 7));
      if (rightOn) right.packet();
    }
  }

  void dispose() {
    manager.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// A capture screen on its own, at the reference size.
Future<void> pumpCapture(
  WidgetTester tester,
  WidgetRig rig,
  Widget screen,
) async {
  tester.view.physicalSize = referenceSize * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clockProvider.overrideWithValue(rig.now), ...rig.overrides],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('th', 'TH'),
        supportedLocales: const [Locale('th', 'TH')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Seed whose order puts [g] second (right after normal).
int seedWith(GaitClass g) {
  for (var s = 0; ; s++) {
    if (trialOrder(s)[1] == g) return s;
  }
}

/// Scrolls the page until [key] is built and visible, then taps it.
Future<void> tapScrolled(WidgetTester tester, String key) async {
  // One display tick, so a freshly shown screen has its foot status.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.scrollUntilVisible(
    byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(byKey(key));
  await tester.pump();
}

/// Holds a hold-to-act button for [d], then lets go.
Future<void> hold(WidgetTester tester, String key, Duration d) async {
  final g = await tester.startGesture(tester.getCenter(byKey(key)));
  await tester.pump(d);
  await g.up();
  await tester.pump();
}

/// Records the current trial to its end and moves on.
Future<void> finishTrial(WidgetTester tester, WidgetRig rig) async {
  await tapScrolled(tester, 'capture-record');
  final s = (tester.widget(
    find.byType(CaptureFlowScreen),
  ) as CaptureFlowScreen).session;
  await rig.walk(tester, s.plannedDuration + const Duration(seconds: 1));
  await tapScrolled(tester, 'capture-next');
  await tester.pump();
}

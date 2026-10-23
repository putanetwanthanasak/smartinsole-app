import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/config/thresholds.dart';
import 'package:smartinsole/ui/app.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/routes.dart';

import '../ble/fake_ble_central.dart';

/// Fixed time so the Home date line never changes between golden runs.
final fixedNow = DateTime(2026, 10, 18, 9, 30);

/// The app's bundled thresholds file (identical to shared/thresholds.json,
/// checked by test/config/thresholds_test.dart).
final testThresholds = Thresholds.parse(
  File(Thresholds.assetPath).readAsStringSync(),
);

/// A wall clock that starts at [start] and moves with the tester's fake
/// time, so mock insoles and the 10 Hz ticker see time pass in step.
DateTime Function() fakeTimeClock(WidgetTester tester, [DateTime? start]) {
  final origin = tester.binding.clock.now();
  final base = start ?? fixedNow;
  return () => base.add(tester.binding.clock.now().difference(origin));
}

/// DESIGN-SPEC reference screen, in logical pixels.
const referenceSize = Size(390, 844);

/// Pumps the whole app at the reference screen size. BLE always runs on a
/// fake stack ([central], [permissions]); no test reaches the real plugins.
/// Pass [settle] false for screens with a periodic display tick (the BLE
/// debug screen), which `pumpAndSettle` would wait on forever.
Future<void> pumpApp(
  WidgetTester tester, {
  String initialRoute = Routes.shell,
  bool reduceMotion = false,
  double textScale = 1.0,
  FakeBleCentral? central,
  FakePermissions? permissions,
  Size size = referenceSize,
  bool settle = true,
  DateTime Function()? now,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(now ?? () => fixedNow),
        thresholdsProvider.overrideWithValue(testThresholds),
        bleCentralProvider.overrideWithValue(central ?? FakeBleCentral()),
        blePermissionsProvider.overrideWithValue(
          permissions ?? FakePermissions(),
        ),
        ...overrides,
      ],
      child: SmartInsoleApp(initialRoute: initialRoute),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder byKey(String key) => find.byKey(ValueKey(key));

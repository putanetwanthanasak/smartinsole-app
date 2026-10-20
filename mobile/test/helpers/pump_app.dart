import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/ui/app.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/routes.dart';

import '../ble/fake_ble_central.dart';

/// Fixed time so the Home date line never changes between golden runs.
final fixedNow = DateTime(2026, 10, 18, 9, 30);

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
  FakeBleCentral? central,
  FakePermissions? permissions,
  Size size = referenceSize,
  bool settle = true,
  DateTime Function()? now,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(now ?? () => fixedNow),
        bleCentralProvider.overrideWithValue(central ?? FakeBleCentral()),
        blePermissionsProvider.overrideWithValue(
          permissions ?? FakePermissions(),
        ),
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

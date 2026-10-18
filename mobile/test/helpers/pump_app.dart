import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/app.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/routes.dart';

/// Fixed time so the Home date line never changes between golden runs.
final fixedNow = DateTime(2026, 10, 18, 9, 30);

/// DESIGN-SPEC reference screen, in logical pixels.
const referenceSize = Size(390, 844);

/// Pumps the whole app at the reference screen size.
Future<void> pumpApp(
  WidgetTester tester, {
  String initialRoute = Routes.shell,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = referenceSize * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [clockProvider.overrideWithValue(() => fixedNow)],
      child: SmartInsoleApp(initialRoute: initialRoute),
    ),
  );
  await tester.pumpAndSettle();
}

Finder byKey(String key) => find.byKey(ValueKey(key));

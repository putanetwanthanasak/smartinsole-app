import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/config/thresholds.dart';
import 'package:smartinsole/footcheck/foot_check_flow.dart';
import 'package:smartinsole/footcheck/footcheck_providers.dart';
import 'package:smartinsole/footcheck/photo_processor.dart';
import 'package:smartinsole/gait/gait_providers.dart';
import 'package:smartinsole/gait/model_spec.dart';
import 'package:smartinsole/notify/reminder_providers.dart';
import 'package:smartinsole/settings/settings_providers.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/app.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/routes.dart';

import '../ble/fake_ble_central.dart';
import 'fake_foot_camera.dart';
import 'fake_reminder_notifier.dart';

/// Fixed time so the Home date line never changes between golden runs.
final fixedNow = DateTime(2026, 10, 18, 9, 30);

/// The app's bundled thresholds file (identical to shared/thresholds.json,
/// checked by test/config/thresholds_test.dart).
final testThresholds = Thresholds.parse(
  File(Thresholds.assetPath).readAsStringSync(),
);

/// The app's bundled Model A input spec (identical to
/// shared/model_input.json, checked by test/gait/model_spec_test.dart).
final testModelInput = ModelInputSpec.parse(
  File(ModelInputSpec.assetPath).readAsStringSync(),
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
/// fake stack ([central], [permissions]) and storage on an in-memory
/// database; no test reaches the real plugins or the phone's file.
/// Pass [settle] false for screens with a periodic display tick (the BLE
/// debug screen), which `pumpAndSettle` would wait on forever. Pass
/// [database] to start with rows already stored (write them before this
/// call: with the app's watchers running, several writes in one
/// `tester.runAsync` deadlock). Settings start at their defaults in memory;
/// pass [settings] to start from a stored state (e.g. a text size).
/// The foot check runs on [camera] and [reminders] fakes, with photos in
/// [photoDir] (a fresh temp folder by default) and the photo processor
/// called directly (no isolate under fake time).
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
  AppDatabase? database,
  SettingsStore? settings,
  FakeFootCamera? camera,
  FakeReminderNotifier? reminders,
  Directory? photoDir,
  List<Override> overrides = const [],
}) async {
  final photos = photoDir ?? Directory.systemTemp.createTempSync('foot_photos');
  final cache = Directory.systemTemp.createTempSync('cache');
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
        modelInputSpecProvider.overrideWithValue(testModelInput),
        // No LiteRT on the test host: a model in the slot would fail here.
        modelRunnerFactoryProvider.overrideWithValue(
          (_, _) => throw UnsupportedError('no TFLite in widget tests'),
        ),
        bleCentralProvider.overrideWithValue(central ?? FakeBleCentral()),
        blePermissionsProvider.overrideWithValue(
          permissions ?? FakePermissions(),
        ),
        databaseProvider.overrideWith((ref) {
          final db = database ?? AppDatabase.memory();
          ref.onDispose(db.close);
          return db;
        }),
        settingsStoreProvider.overrideWithValue(
          settings ?? MemorySettingsStore(),
        ),
        footCameraProvider.overrideWithValue(() => camera ?? FakeFootCamera()),
        reminderNotifierProvider.overrideWithValue(
          reminders ?? FakeReminderNotifier(),
        ),
        footPhotoDirProvider.overrideWithValue(() async => photos),
        cameraCacheDirProvider.overrideWithValue(() async => cache),
        photoProcessorProvider.overrideWithValue(
          (jpeg, {required aspect}) async =>
              processFootPhoto(jpeg, aspect: aspect),
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

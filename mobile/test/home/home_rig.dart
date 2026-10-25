import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/database.dart';

import '../helpers/pump_app.dart';

/// How long each preset streams before Home is checked. `rest` needs two
/// temperature reading pairs after both feet stream (rule 6): the mock
/// sends one at START (feet not yet usable) and then every 30 s.
const warmUp = Duration(seconds: 61);

/// Pumps the app with [preset] on both mock insoles and fake time that
/// moves the wall clock (from [start], default [fixedNow]), streams for
/// [warmUp], then lets animations end. [database] holds rows written
/// before the app runs (see [pumpApp]).
Future<void> pumpHome(
  WidgetTester tester,
  MockPreset preset, {
  double textScale = 1.0,
  bool reduceMotion = false,
  Size size = referenceSize,
  DateTime? start,
  AppDatabase? database,
  SettingsStore? settings,
  List<Override> overrides = const [],
}) async {
  await pumpApp(
    tester,
    now: fakeTimeClock(tester, start),
    database: database,
    settings: settings,
    textScale: textScale,
    reduceMotion: reduceMotion,
    size: size,
    settle: false,
    overrides: [mockPresetProvider.overrideWithValue(preset), ...overrides],
  );
  // Small steps, so the 50 Hz path and the 10 Hz ticker interleave as on a
  // phone.
  for (var t = Duration.zero; t < warmUp; t += const Duration(seconds: 1)) {
    await tester.pump(const Duration(seconds: 1));
  }
  // Not pumpAndSettle: a high dot pulses for as long as it is high.
  await tester.pump(const Duration(seconds: 1));
}

/// Disposes the mock insoles' timers before the test ends.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

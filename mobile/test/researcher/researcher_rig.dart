import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/researcher_screen.dart';

import '../connection/connection_rig.dart' show pumpFor;
import '../helpers/pump_app.dart';

/// Opens Researcher with both feet on the mock [preset], under fake time.
Future<ProviderContainer> pumpResearcher(
  WidgetTester tester, {
  MockPreset preset = MockPreset.safe,
  Size size = const Size(390, 2200),
  double textScale = 1.0,
  SettingsStore? settings,
}) async {
  await pumpApp(
    tester,
    initialRoute: Routes.researcher,
    textScale: textScale,
    settings: settings,
    now: fakeTimeClock(tester),
    settle: false,
    size: size,
    overrides: [
      mockPresetProvider.overrideWithValue(preset),
      appVersionProvider.overrideWithValue(Future.value('1.0.0+1')),
    ],
  );
  await pumpFor(tester, const Duration(seconds: 1));
  return ProviderScope.containerOf(
    tester.element(find.byType(ResearcherScreen)),
  );
}

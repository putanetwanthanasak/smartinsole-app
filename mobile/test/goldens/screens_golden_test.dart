@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/ui/routes.dart';

import '../helpers/pump_app.dart';

/// One golden per screen. Regenerate with:
///   flutter test --update-goldens test/goldens
void main() {
  Future<void> expectScreen(String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
  );

  group('tabs', () {
    for (final (tab, name) in [
      ('home', 'home'),
      ('gait', 'gait'),
      ('temperature', 'temperature'),
      ('alerts', 'alerts'),
    ]) {
      testWidgets(name, (tester) async {
        await pumpApp(tester);
        await tester.tap(byKey('tab-$tab'));
        await tester.pumpAndSettle();
        await expectScreen(name);
      });
    }
  });

  group('pushed screens', () {
    for (final (route, name) in [
      (Routes.connection, 'connection'),
      (Routes.settings, 'settings'),
      (Routes.footCheck, 'foot_check'),
    ]) {
      testWidgets(name, (tester) async {
        await pumpApp(tester, initialRoute: route);
        await expectScreen(name);
      });
    }
  });

  testWidgets('settings with the debug mock preset button', (tester) async {
    await pumpApp(
      tester,
      initialRoute: Routes.settings,
      overrides: [mockPresetProvider.overrideWithValue(MockPreset.watch)],
    );
    await expectScreen('settings_mock');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/settings_screen.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('no mock: Settings has no preset button', (tester) async {
    await pumpApp(tester, initialRoute: Routes.settings);
    expect(byKey('mock-preset-button'), findsNothing);
  });

  testWidgets('mock: the preset button switches the preset live', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialRoute: Routes.settings,
      overrides: [mockPresetProvider.overrideWithValue(MockPreset.safe)],
    );
    expect(find.text('Mock preset (debug): safe'), findsOneWidget);
    await tester.tap(byKey('mock-preset-button'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('mock-preset-rest'));
    await tester.pumpAndSettle();
    expect(find.text('Mock preset (debug): rest'), findsOneWidget);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(c.read(mockInsolesProvider)!.preset, MockPreset.rest);
    await tester.pumpWidget(const SizedBox());
  });
}

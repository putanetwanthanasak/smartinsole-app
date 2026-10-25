@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/routes.dart';

import '../connection/connection_rig.dart' show pumpFor;
import '../helpers/pump_app.dart';
import '../researcher/researcher_rig.dart';

/// Settings (DESIGN-SPEC §10.1, boards SettingsD) and Researcher (§10.2,
/// SettingsDResearch, SettingsDTare), with the S8B sheets that are not on
/// the boards (§14). Full-height surfaces so each golden shows the whole
/// page. Regenerate:
///   flutter test --update-goldens test/goldens/settings_golden_test.dart
void main() {
  Future<void> expectScreen(String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
  );

  Future<void> pumpSettings(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    double textScale = 1.0,
    double height = 2100,
  }) => pumpApp(
    tester,
    initialRoute: Routes.settings,
    textScale: textScale,
    size: Size(390, height),
    settings: MemorySettingsStore(settings: settings),
    overrides: [
      appVersionProvider.overrideWithValue(Future.value('1.0.0+1')),
      footPhotoCountProvider.overrideWith((ref) async => 28),
    ],
  );

  const named = AppSettings(name: 'สมชาย');

  testWidgets('settings_100', (tester) async {
    await pumpSettings(tester, settings: named);
    await expectScreen('settings_100');
  });

  testWidgets('settings_switch_off_100', (tester) async {
    await pumpSettings(
      tester,
      settings: named.copyWith(sound: false, textSize: TextSizeOption.large),
    );
    await expectScreen('settings_switch_off_100');
  });

  testWidgets('settings_130xl', (tester) async {
    await pumpSettings(
      tester,
      settings: named.copyWith(textSize: TextSizeOption.extraLarge),
      textScale: 1.3,
      height: 4200,
    );
    await expectScreen('settings_130xl');
  });

  for (final (key, name) in [
    ('settings-name', 'sheet_name'),
    ('settings-delete-photos', 'sheet_delete_photos'),
  ]) {
    testWidgets(name, (tester) async {
      await pumpSettings(tester, settings: named, height: 844);
      await tester.scrollUntilVisible(byKey(key), 300);
      await tester.pumpAndSettle();
      await tester.tap(byKey(key));
      await tester.pumpAndSettle();
      // The keyboard is not shown in a widget test.
      await expectScreen(name);
    });
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('researcher_ready_100', (tester) async {
    await pumpResearcher(tester, size: const Size(390, 1900));
    await pumpFor(tester, const Duration(seconds: 10));
    await expectScreen('researcher_ready_100');
    await unmount(tester);
  });

  testWidgets('researcher_capture_open_100', (tester) async {
    final c = await pumpResearcher(tester, size: const Size(390, 1900));
    c.read(activeCaptureProvider.notifier).open('S01_20261018_0930');
    await pumpFor(tester, const Duration(seconds: 2));
    await expectScreen('researcher_capture_open_100');
    await unmount(tester);
  });

  testWidgets('researcher_130xl', (tester) async {
    await pumpResearcher(
      tester,
      size: const Size(390, 3600),
      textScale: 1.3,
      settings: MemorySettingsStore(
        settings: const AppSettings(textSize: TextSizeOption.extraLarge),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 10));
    await expectScreen('researcher_130xl');
    await unmount(tester);
  });

  for (final (phase, name) in [
    (0, 'sheet_tare'),
    (1, 'sheet_tare_running'),
    (2, 'sheet_tare_done'),
  ]) {
    testWidgets(name, (tester) async {
      await pumpResearcher(tester, size: const Size(390, 844));
      await pumpFor(tester, const Duration(seconds: 10));
      await tester.tap(byKey('researcher-tare'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      if (phase >= 1) {
        await tester.tap(byKey('sheet-confirm'));
        await tester.pump();
        // Reduce motion is off: let the spinner reach a fixed frame.
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (phase >= 2) await pumpFor(tester, const Duration(seconds: 2));
      await expectScreen(name);
      // Let a running TARE finish, so its timeout timer ends.
      await pumpFor(tester, const Duration(seconds: 2));
      await unmount(tester);
    });
  }

  testWidgets('sheet_reboot', (tester) async {
    await pumpResearcher(tester, size: const Size(390, 844));
    await tester.tap(byKey('researcher-reboot'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await expectScreen('sheet_reboot');
    await unmount(tester);
  });
}

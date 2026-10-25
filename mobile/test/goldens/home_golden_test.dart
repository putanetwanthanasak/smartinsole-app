@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/settings_store.dart';

import '../home/home_rig.dart';

/// Gait-tab presets: no Home state of their own.
const _gaitOnly = {MockPreset.standing, MockPreset.toeWalk};

/// Home in every mock preset at 100 % and 200 % text (DESIGN-SPEC §6),
/// except the S8A gait presets, which add no Home state.
/// The surface is 390 wide (the reference width) and tall enough for the
/// whole scrolling page, so each golden shows every section. Regenerate:
///   flutter test --update-goldens test/goldens/home_golden_test.dart
void main() {
  for (final (scale, height) in [(1.0, 1640.0), (2.0, 3700.0)]) {
    for (final preset in MockPreset.values.where(
      (p) => !_gaitOnly.contains(p),
    )) {
      final name = 'home_${preset.name}_${(scale * 100).round()}';
      testWidgets(name, (tester) async {
        await pumpHome(
          tester,
          preset,
          textScale: scale,
          size: Size(390, height),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('screens/$name.png'),
        );
        await unmount(tester);
      });
    }
  }

  // S8B: the Note 10's phone scale 1.3 with "ใหญ่มาก" (26/18, ≈ 1.88), and
  // a greeting name.
  for (final preset in [MockPreset.safe, MockPreset.rest]) {
    final name = 'home_${preset.name}_130xl';
    testWidgets(name, (tester) async {
      await pumpHome(
        tester,
        preset,
        textScale: 1.3,
        size: const Size(390, 3600),
        settings: MemorySettingsStore(
          settings: const AppSettings(
            name: 'สมชาย',
            textSize: TextSizeOption.extraLarge,
          ),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/$name.png'),
      );
      await unmount(tester);
    });
  }
}

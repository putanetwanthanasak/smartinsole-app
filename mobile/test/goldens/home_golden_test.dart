@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';

import '../home/home_rig.dart';

/// Home in every mock preset at 100 % and 200 % text (DESIGN-SPEC §6).
/// The surface is 390 wide (the reference width) and tall enough for the
/// whole scrolling page, so each golden shows every section. Regenerate:
///   flutter test --update-goldens test/goldens/home_golden_test.dart
void main() {
  for (final (scale, height) in [(1.0, 1640.0), (2.0, 3700.0)]) {
    for (final preset in MockPreset.values) {
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
}

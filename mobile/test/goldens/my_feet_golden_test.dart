@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../my_feet/my_feet_rig.dart';

/// My feet (DESIGN-SPEC §8) in the boards' states at 100 % and 200 % text,
/// on a surface tall enough for the whole page. The temperature states run
/// on the preset's sample day. Regenerate:
///   flutter test --update-goldens test/goldens/my_feet_golden_test.dart
void main() {
  // (name, preset, tab, seed day, details open), with the board each one
  // is compared with: FeetD, —, FeetDPressureWatch, FeetDNoData, —,
  // FeetDTemp, FeetDTempRest, FeetDTempMissing.
  const states = [
    ('safe', MockPreset.safe, MyFeetTab.pressure, false, false),
    ('orange_dot', MockPreset.safeOrangeDot, MyFeetTab.pressure, false, false),
    ('watch', MockPreset.watch, MyFeetTab.pressure, false, true),
    ('no_data', MockPreset.noData, MyFeetTab.pressure, false, false),
    ('one_foot', MockPreset.oneFootMissing, MyFeetTab.pressure, false, false),
    ('temp', MockPreset.safe, MyFeetTab.temperature, true, false),
    ('temp_rest', MockPreset.rest, MyFeetTab.temperature, true, true),
    (
      'temp_missing',
      MockPreset.oneFootMissing,
      MyFeetTab.temperature,
      true,
      false,
    ),
  ];
  for (final (scale, height) in [(1.0, 2300.0), (2.0, 5200.0)]) {
    for (final (state, preset, tab, seed, open) in states) {
      final name = 'my_feet_${state}_${(scale * 100).round()}';
      testWidgets(name, (tester) async {
        await pumpMyFeet(
          tester,
          preset,
          tab: tab,
          seedDay: seed,
          textScale: scale,
          size: Size(390, height),
        );
        if (open) await openDetails(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('screens/$name.png'),
        );
        await unmount(tester);
      });
    }
  }
}

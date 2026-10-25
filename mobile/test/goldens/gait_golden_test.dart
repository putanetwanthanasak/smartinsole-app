@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';

import '../alerts/alerts_rig.dart' show containerOf;
import '../my_feet/gait_tab_test.dart' show demoToe, modelAnswering, pumpGait;
import '../my_feet/my_feet_rig.dart';

/// My feet › "การเดิน" (DESIGN-SPEC §8.3) at 100 % and 200 % text, on a
/// surface tall enough for the whole page. Regenerate:
///   flutter test --update-goldens test/goldens/gait_golden_test.dart
void main() {
  // (name, preset, overrides, details open, then stand still), with the
  // board each one is compared with: FeetDGait, FeetDGaitToe,
  // FeetDGaitIdle, and states not on the boards.
  final states = <(String, MockPreset, List<Override>, bool, bool)>[
    ('walk_rules', MockPreset.safe, [], false, false),
    ('toe_model', MockPreset.safe, [demoToe], true, false),
    ('idle', MockPreset.safe, [], true, true),
    (
      'below_min',
      MockPreset.toeWalk,
      [
        modelAnswering([0.5, 0.2, 0.1, 0.1, 0.1]),
      ],
      false,
      false,
    ),
    ('balance_warning', MockPreset.watch, [], false, false),
    ('one_foot', MockPreset.oneFootMissing, [], false, false),
    ('no_data', MockPreset.noData, [], false, false),
  ];
  for (final (scale, height) in [(1.0, 2300.0), (2.0, 5600.0)]) {
    for (final (state, preset, overrides, open, stand) in states) {
      final name = 'gait_${state}_${(scale * 100).round()}';
      testWidgets(name, (tester) async {
        await pumpGait(
          tester,
          preset,
          overrides: overrides,
          textScale: scale,
          size: Size(390, height),
        );
        if (stand) {
          containerOf(tester).read(mockInsolesProvider)!.preset =
              MockPreset.standing;
          // Past the 10 s balance window, so it shows the standing loads.
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
        }
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

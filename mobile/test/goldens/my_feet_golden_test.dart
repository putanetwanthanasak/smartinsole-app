@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/storage/temperature_recorder.dart';
import 'package:smartinsole/storage/temperature_repository.dart';
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

  // User check (S8D-2 approval): the max-of-8 line with two readings in a
  // row above the band from different sites (MTH1, then the lateral heel)
  // and no TEMP_DELTA, so the note "จุดเดียวกัน…" and the end label can be
  // judged together. A hand-made hour, 12:00–13:00, on the safe preset.
  for (final scale in [1.0, 1.3]) {
    final name = 'my_feet_temp_two_sites_${(scale * 100).round()}';
    testWidgets(name, (tester) async {
      final db = AppDatabase.memory();
      await tester.runAsync(() async {
        final repo = DriftTemperatureRepository(db);
        final period = TempLayout.notifyPeriod.inMilliseconds;
        final from = myFeetStart
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        final n = Duration.millisecondsPerHour ~/ period;
        const base = MockFootProfile.baseSiteC;
        final normal = List.filled(base.length, TempQuality.normal);
        for (var i = 0; i < n; i++) {
          final over = switch (n - i) {
            2 => 1, // MTH1 +2.6 °C
            1 => 7, // lateral heel +2.5 °C
            _ => null,
          };
          await repo.add(
            side: FootSide.left,
            atMs: from + i * period,
            celsius: base,
            quality: normal,
            timeFromArrival: false,
          );
          await repo.add(
            side: FootSide.right,
            atMs: from + i * period + period ~/ 4,
            celsius: [
              for (var s = 0; s < base.length; s++)
                base[s] +
                    (s == over
                        ? (over == 1 ? 2.6 : 2.5)
                        : s == 1
                        ? 0.3
                        : 0.1),
            ],
            quality: normal,
            timeFromArrival: false,
          );
        }
      });
      await pumpMyFeet(
        tester,
        MockPreset.safe,
        tab: MyFeetTab.temperature,
        database: db,
        // The live mock's readings are not stored, so the two readings
        // above stay the line's last points.
        overrides: [
          temperatureRecorderProvider.overrideWith(
            (ref) => TemperatureRecorder(
              manager: ref.watch(deviceManagerProvider),
              temperatures: ref.watch(temperatureRepositoryProvider),
              summaries: ref.watch(dailySummaryRepositoryProvider),
            ),
          ),
        ],
        textScale: scale,
        size: Size(390, scale == 1.0 ? 2300 : 3200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/$name.png'),
      );
      await unmount(tester);
    });
  }
}

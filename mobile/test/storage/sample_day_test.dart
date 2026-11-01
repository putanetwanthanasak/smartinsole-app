import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/local_date.dart';
import 'package:smartinsole/storage/sample_day.dart';
import 'package:smartinsole/storage/temperature_repository.dart';
import 'package:smartinsole/ui/screens/my_feet/temp_chart_model.dart';

import '../helpers/pump_app.dart' show testThresholds;

// The seed and the chart both use the machine's local day, as on a phone.
const _dates = LocalDates();
final _now = DateTime(2026, 10, 25, 13);

Future<(DriftTemperatureRepository, int)> _seed(
  MockPreset preset, {
  DateTime? now,
}) async {
  final db = AppDatabase.memory();
  addTearDown(db.close);
  final repo = DriftTemperatureRepository(db, _dates);
  final n = await seedSampleDay(
    temperatures: repo,
    dates: _dates,
    thresholds: testThresholds,
    preset: preset,
    now: now ?? _now,
  );
  return (repo, n);
}

void main() {
  final today = _dates.of(_now.millisecondsSinceEpoch);

  for (final (preset, sites, openGap) in [
    (MockPreset.safe, [5], false),
    (MockPreset.watch, [5], false),
    (MockPreset.rest, [5, 7], false),
    (MockPreset.oneFootMissing, [5], true),
  ]) {
    test('${preset.name}: one period above deltaC at sites $sites, one '
        'right-foot gap', () async {
      final (repo, n) = await _seed(preset);
      final rows = await repo.watchDay(today).first;
      expect(rows, hasLength(n));
      expect(
        DateTime.fromMillisecondsSinceEpoch(rows.first.atMs),
        DateTime(2026, 10, 25, sampleDayStartHour),
      );
      expect(rows.last.atMs, lessThan(_now.millisecondsSinceEpoch));

      // Draw it as the screen does, with the right foot gone when the
      // preset has it gone.
      final chart = tempChartOf(
        rows,
        now: _now,
        usable: {FootSide.left: true, FootSide.right: !openGap},
      );
      // The one line (largest |ΔT| of the 8 sites): its points above the
      // threshold come from these sites, in one period.
      final points = [for (final r in chart.runs) ...r];
      final above = points.where((p) => p.deltaC > testThresholds.deltaC);
      expect(above, isNotEmpty);
      expect(
        above.map((p) => p.site).toSet().difference(sites.toSet()),
        isEmpty,
      );
      final first = points.indexOf(above.first);
      final last = points.indexOf(above.last);
      expect(last - first + 1, above.length);

      final gaps = chart.gaps.where((g) => g.side == FootSide.right);
      expect(gaps, hasLength(1));
      expect(gaps.single.ongoing, openGap);
      if (preset == MockPreset.rest) {
        // Above up to the end, joining the live mock's 2.6 °C.
        expect(chart.last!.deltaC, greaterThan(testThresholds.deltaC));
      }
    });
  }

  test('stops a period before the first live reading of today', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final repo = DriftTemperatureRepository(db, _dates);
    final live = DateTime(2026, 10, 25, 12).millisecondsSinceEpoch;
    await repo.add(
      side: FootSide.left,
      atMs: live,
      celsius: List.filled(TempLayout.siteCount, 31),
      quality: List.filled(TempLayout.siteCount, TempQuality.normal),
      timeFromArrival: false,
    );
    await seedSampleDay(
      temperatures: repo,
      dates: _dates,
      thresholds: testThresholds,
      preset: MockPreset.safe,
      now: _now,
    );
    final rows = await repo.watchDay(today).first;
    final seeded = rows.where((r) => r.atMs != live);
    expect(
      seeded.map((r) => r.atMs).reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(live - TempLayout.notifyPeriod.inMilliseconds),
    );
  });

  test('early in the morning: the day so far, from midnight', () async {
    final (repo, n) = await _seed(
      MockPreset.safe,
      now: DateTime(2026, 10, 25, 8, 10),
    );
    expect(n, greaterThan(0));
    final rows = await repo.watchDay(today).first;
    expect(
      DateTime.fromMillisecondsSinceEpoch(rows.first.atMs),
      DateTime(2026, 10, 25),
    );
  });
}

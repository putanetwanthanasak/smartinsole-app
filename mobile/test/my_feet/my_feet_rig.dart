import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/local_date.dart';
import 'package:smartinsole/storage/sample_day.dart';
import 'package:smartinsole/storage/temperature_repository.dart';
import 'package:smartinsole/ui/shell/app_shell.dart' show MyFeetTab;
import 'package:smartinsole/ui/widgets/temp_delta_chart.dart';

import '../helpers/pump_app.dart';
import '../home/home_rig.dart';

export '../home/home_rig.dart' show unmount;

/// 13:00 on the boards' Sunday, so a seeded day runs 08:00–13:00 as on
/// boards FeetDTemp, FeetDTempRest and FeetDTempMissing.
final myFeetStart = DateTime(2026, 10, 18, 13);

/// A new in-memory database holding [preset]'s sample day at
/// [myFeetStart] ([seedSampleDay]), written before the app runs.
Future<AppDatabase> sampleDayDatabase(
  WidgetTester tester,
  MockPreset preset,
) async {
  final db = AppDatabase.memory();
  await tester.runAsync(
    () => seedSampleDay(
      temperatures: DriftTemperatureRepository(db),
      dates: const LocalDates(),
      thresholds: testThresholds,
      preset: preset,
      now: myFeetStart,
    ),
  );
  return db;
}

/// Pumps the app on [preset] (streamed for `warmUp`, as Home's tests),
/// optionally on its sample day, and opens My feet › [tab].
Future<void> pumpMyFeet(
  WidgetTester tester,
  MockPreset preset, {
  MyFeetTab tab = MyFeetTab.pressure,
  bool seedDay = false,
  double textScale = 1.0,
  bool reduceMotion = false,
  Size size = referenceSize,
  List<Override> overrides = const [],
}) async {
  final db = seedDay ? await sampleDayDatabase(tester, preset) : null;
  await pumpHome(
    tester,
    preset,
    start: myFeetStart,
    database: db,
    textScale: textScale,
    reduceMotion: reduceMotion,
    size: size,
    overrides: overrides,
  );
  await tester.tap(byKey('tab-myFeet'));
  await tester.pump(const Duration(seconds: 1));
  if (tab != MyFeetTab.pressure) await openSubTab(tester, tab);
}

/// Taps the sub-tab and lets the panel fade and the chart draw in.
Future<void> openSubTab(WidgetTester tester, MyFeetTab tab) async {
  await tester.tap(byKey('my-feet-tab-${tab.name}'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Opens "ดูตัวเลขละเอียด" on the current tab.
Future<void> openDetails(WidgetTester tester) async {
  final header = byKey('details-expander');
  await tester.scrollUntilVisible(
    header,
    200,
    scrollable: find.descendant(
      of: byKey('my-feet-scroll'),
      matching: find.byType(Scrollable),
    ),
  );
  // The list lays out at its new offset on the next frame.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(header);
  await tester.pump(const Duration(seconds: 1));
}

double chartProgress(WidgetTester tester) =>
    tester.state<TempDeltaChartState>(find.byType(TempDeltaChart)).drawProgress;

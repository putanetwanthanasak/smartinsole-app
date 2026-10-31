import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/screens/alerts/alert_view.dart';

import '../alerts/alerts_rig.dart';
import '../helpers/pump_app.dart';

/// Home's date line and the Alerts day titles follow the day
/// (`todayProvider`), not the clock at the last rebuild: they roll over at
/// midnight and on resume with no data event (BACKLOG 68).
void main() {
  final day1 = DateTime(2026, 10, 18);
  final day2 = DateTime(2026, 10, 19);

  testWidgets('Home: the date line rolls over at midnight', (t) async {
    await pumpApp(t, now: fakeTimeClock(t, DateTime(2026, 10, 18, 23, 59, 30)));
    expect(find.text(thaiLongDate(day1)), findsOneWidget);

    await t.pump(const Duration(seconds: 31));
    await t.pump();
    expect(find.text(thaiLongDate(day2)), findsOneWidget);
    expect(find.text(thaiLongDate(day1)), findsNothing);
  });

  testWidgets('Home: a day that passed while timers were starved shows '
      'on resume', (t) async {
    var skipped = Duration.zero;
    final clock = fakeTimeClock(t, DateTime(2026, 10, 18, 12));
    await pumpApp(t, now: () => clock().add(skipped));
    expect(find.text(thaiLongDate(day1)), findsOneWidget);

    // The phone slept past midnight; the midnight timer has not run.
    skipped = const Duration(days: 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.text(thaiLongDate(day2)), findsOneWidget);
  });

  testWidgets('Alerts: "วันนี้" becomes "เมื่อวาน" at midnight', (t) async {
    final (db, _) = await seededDatabase(t);
    await pumpApp(
      t,
      database: db,
      now: fakeTimeClock(t, DateTime(2026, 10, 18, 23, 59, 30)),
    );
    await t.tap(byKey('tab-alerts'));
    await t.pumpAndSettle();
    expect(find.text('วันนี้'), findsWidgets);
    final yesterdayTitle = groupTitle('2026-10-18', day2);
    expect(find.text(yesterdayTitle), findsNothing);

    await t.pump(const Duration(seconds: 31));
    await t.pump();
    expect(find.text(yesterdayTitle), findsOneWidget);
  });
}

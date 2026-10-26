import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/notify/reminder_plan.dart';
import 'package:smartinsole/notify/time_zone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  List<DateTime> plan(
    DateTime now, {
    bool enabled = true,
    bool todayDone = false,
    int hour = 19,
    int minute = 0,
  }) => reminderTimes(
    now: now,
    enabled: enabled,
    hour: hour,
    minute: minute,
    todayDone: todayDone,
  );

  test('before the time, not done: today and the next 13 evenings', () {
    final times = plan(DateTime(2026, 10, 26, 9));
    expect(times, hasLength(reminderDaysAhead));
    expect(times.first, DateTime(2026, 10, 26, 19));
    expect(times.last, DateTime(2026, 11, 8, 19));
  });

  test('today is left out once its check is saved', () {
    final times = plan(DateTime(2026, 10, 26, 9), todayDone: true);
    expect(times.first, DateTime(2026, 10, 27, 19));
    expect(times, hasLength(reminderDaysAhead - 1));
  });

  test('today is left out once the time has passed', () {
    expect(plan(DateTime(2026, 10, 26, 19)).first, DateTime(2026, 10, 27, 19));
    expect(
      plan(DateTime(2026, 10, 26, 18, 59)).first,
      DateTime(2026, 10, 26, 19),
    );
  });

  test('switch off: nothing', () {
    expect(plan(DateTime(2026, 10, 26, 9), enabled: false), isEmpty);
  });

  test('a changed time moves every reminder', () {
    final times = plan(DateTime(2026, 10, 26, 21), hour: 21, minute: 30);
    expect(times.first, DateTime(2026, 10, 26, 21, 30));
    expect(times.every((t) => t.hour == 21 && t.minute == 30), isTrue);
  });

  test('months roll over', () {
    expect(plan(DateTime(2026, 10, 31, 20))[0], DateTime(2026, 11, 1, 19));
  });

  test('one id per day', () {
    expect(reminderIdOf(DateTime(2026, 10, 26, 19)), 20261026);
    expect(reminderIdOf(DateTime(2026, 10, 26)), 20261026);
  });

  group('time zone (user addition 5)', () {
    setUpAll(tzdata.initializeTimeZones);

    test('19:00 in Asia/Bangkok is scheduled at 19:00 local = 12:00 UTC', () {
      final bangkok = tz.getLocation('Asia/Bangkok');
      final at = zonedTimeOf(DateTime(2026, 10, 26, 19), bangkok);
      expect([at.hour, at.minute], [19, 0]);
      expect(at.location.name, 'Asia/Bangkok');
      expect(at.toUtc(), DateTime.utc(2026, 10, 26, 12));
    });

    test('tz.local becomes the phone zone, never the UTC default', () async {
      tz.setLocalLocation(tz.UTC);
      final loc = await initLocalTimeZone(
        zoneName: () async => 'Asia/Bangkok',
        offset: const Duration(hours: 7),
      );
      expect(loc.name, 'Asia/Bangkok');
      expect(tz.local.name, 'Asia/Bangkok');
      final at = zonedTimeOf(DateTime(2026, 10, 26, 19), tz.local);
      expect(at.toUtc(), DateTime.utc(2026, 10, 26, 12));
    });

    test('an unknown zone name falls back to the phone offset', () async {
      final loc = await initLocalTimeZone(
        zoneName: () async => 'Not/AZone',
        offset: const Duration(hours: 7),
      );
      expect(loc.name, 'Fixed+0700');
      expect(
        zonedTimeOf(DateTime(2026, 10, 26, 19), tz.local).toUtc(),
        DateTime.utc(2026, 10, 26, 12),
      );
    });

    test('a failing lookup falls back too', () async {
      final loc = await initLocalTimeZone(
        zoneName: () async => throw StateError('no plugin'),
        offset: const Duration(hours: 7),
      );
      expect(loc.name, 'Fixed+0700');
    });

    test('a half-hour offset is kept, never UTC', () async {
      final loc = await initLocalTimeZone(
        zoneName: () async => 'Not/AZone',
        offset: const Duration(hours: 5, minutes: 30),
      );
      expect(loc.name, 'Fixed+0530');
      expect(
        zonedTimeOf(DateTime(2026, 10, 26, 19), tz.local).toUtc(),
        DateTime.utc(2026, 10, 26, 13, 30),
      );
    });
  });
}

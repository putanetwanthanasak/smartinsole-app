import 'package:timezone/timezone.dart' as tz;

/// How many evenings ahead are scheduled. Each is a one-shot, so a day whose
/// check is already saved can be left out (user decision 2, 2026-10-26: it
/// fires only while today's check is not saved). Recomputed at every start,
/// save and settings change, so the window keeps moving while the app is in
/// use.
const reminderDaysAhead = 14;

/// The evening-reminder times, as local wall-clock times, oldest first:
/// today at [hour]:[minute] when that is still ahead and today's check is
/// not saved, then each following day, [reminderDaysAhead] days in all.
/// Empty while the reminder is off.
List<DateTime> reminderTimes({
  required DateTime now,
  required bool enabled,
  required int hour,
  required int minute,
  required bool todayDone,
  int days = reminderDaysAhead,
}) {
  if (!enabled) return const [];
  final out = <DateTime>[];
  for (var d = 0; d < days; d++) {
    final at = DateTime(now.year, now.month, now.day + d, hour, minute);
    if (d == 0 && (todayDone || !at.isAfter(now))) continue;
    out.add(at);
  }
  return out;
}

/// One id per calendar day (`yyyymmdd`), so today's reminder can be
/// cancelled, and cleared from the tray, after a save.
int reminderIdOf(DateTime localDay) =>
    localDay.year * 10000 + localDay.month * 100 + localDay.day;

/// The wall-clock [local] time in [location] (the phone's zone, never UTC:
/// user addition 5): 19:00 in Asia/Bangkok is 12:00 UTC.
tz.TZDateTime zonedTimeOf(DateTime local, tz.Location location) =>
    tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );

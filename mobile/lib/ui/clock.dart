import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The current wall-clock time. Overridden in tests so goldens do not change
/// from day to day.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Home header date, e.g. "วันศุกร์ 16 ตุลาคม". Thai date symbols are loaded
/// by `GlobalMaterialLocalizations`, so call this below `MaterialApp`.
String thaiLongDate(DateTime d) => DateFormat('EEEE d MMMM', 'th').format(d);

/// Buddhist Era = Gregorian year + 543 (Thai calendar years, as on the
/// boards: "21 ต.ค. 2569").
const buddhistEraOffset = 543;

/// "14:32".
String hhmm(DateTime d) => DateFormat('HH:mm').format(d);

/// "14:30:20".
String hhmmss(DateTime d) => DateFormat('HH:mm:ss').format(d);

/// "อังคาร 20 ต.ค.": weekday without the "วัน" prefix, day, short month
/// (DESIGN-SPEC §7.2 group titles).
String thaiWeekdayDayMonth(DateTime d) {
  final weekday = DateFormat('EEEE', 'th').format(d);
  final short = weekday.startsWith(_dayPrefix)
      ? weekday.substring(_dayPrefix.length)
      : weekday;
  return '$short ${DateFormat('d MMM', 'th').format(d)}';
}

const _dayPrefix = 'วัน';

/// "21 ต.ค. 2569 14:32:10": the detail rows' time stamps, Buddhist year.
String thaiDateTimeBE(DateTime d) =>
    '${DateFormat('d MMM', 'th').format(d)} ${d.year + buddhistEraOffset} '
    '${DateFormat('HH:mm:ss').format(d)}';

/// Whole calendar days from [from]'s date to [to]'s date (local dates; 0 =
/// the same day, 1 = [from] is yesterday). Daylight-saving safe.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// "วันนี้" / "เมื่อวาน" relative to [now], or null for older days.
String? relativeDayTh(DateTime d, DateTime now) =>
    switch (calendarDaysBetween(d, now)) {
      0 => 'วันนี้',
      1 => 'เมื่อวาน',
      _ => null,
    };

/// The phone's UTC offset at a moment. Tests pass a fixed one so day
/// grouping does not depend on the machine's time zone.
typedef UtcOffsetAt = Duration Function(DateTime utc);

Duration deviceUtcOffset(DateTime utc) => utc.toLocal().timeZoneOffset;

/// Times are stored as UTC ms plus this local date, so "วันนี้" /
/// "เมื่อวาน" and the 30-day footer group by the patient's calendar, not
/// by UTC (Bangkok midnight is 17:00 UTC).
class LocalDates {
  const LocalDates([this.offsetAt = deviceUtcOffset]);

  final UtcOffsetAt offsetAt;

  /// `YYYY-MM-DD` for a UTC ms time.
  String of(int utcMs) {
    final utc = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true);
    final local = utc.add(offsetAt(utc));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-'
        '${two(local.month)}-${two(local.day)}';
  }
}

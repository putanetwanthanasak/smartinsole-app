import '../storage/foot_check_repository.dart';

/// Where Compare's left photo comes from (user decision 3, 2026-10-26):
/// the newest photo of the view from an earlier day. Photos taken earlier
/// today are never the comparison.
enum CompareKind {
  /// Taken yesterday: "เมื่อวาน · {d MMM}".
  yesterday,

  /// Taken before yesterday: "ครั้งก่อน · {d MMM}".
  earlier,

  /// No earlier photo: "ยังไม่มีรูปก่อนหน้า".
  none,
}

class CompareSource {
  const CompareSource(this.kind, [this.photo]);

  final CompareKind kind;
  final FootPhotoRef? photo;
}

CompareSource compareSourceOf(FootPhotoRef? photo, String today) {
  if (photo == null) return const CompareSource(CompareKind.none);
  return CompareSource(
    photo.localDate == previousLocalDate(today)
        ? CompareKind.yesterday
        : CompareKind.earlier,
    photo,
  );
}

/// The calendar day before a `YYYY-MM-DD` date.
String previousLocalDate(String date) => shiftLocalDate(date, -1);

/// [date] moved by [days] calendar days (`YYYY-MM-DD`).
String shiftLocalDate(String date, int days) {
  final d = DateTime.utc(
    int.parse(date.substring(0, 4)),
    int.parse(date.substring(5, 7)),
    int.parse(date.substring(8, 10)) + days,
  );
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// A `YYYY-MM-DD` date as a local [DateTime] at midnight (for captions).
DateTime localDateTimeOf(String date) => DateTime(
  int.parse(date.substring(0, 4)),
  int.parse(date.substring(5, 7)),
  int.parse(date.substring(8, 10)),
);

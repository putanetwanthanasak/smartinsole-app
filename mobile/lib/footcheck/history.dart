import '../storage/models.dart';

/// One day of the photo history: its checks, newest first.
class FootCheckDay {
  const FootCheckDay(this.localDate, this.checks);

  final String localDate;
  final List<FootCheck> checks;
}

/// Groups checks (newest first) by day, keeping that order.
List<FootCheckDay> groupByDay(List<FootCheck> newestFirst) {
  final days = <FootCheckDay>[];
  for (final c in newestFirst) {
    if (days.isEmpty || days.last.localDate != c.localDate) {
      days.add(FootCheckDay(c.localDate, [c]));
    } else {
      days.last.checks.add(c);
    }
  }
  return days;
}

/// Each day's result: its latest check counts (user decision 4). Input in
/// any order.
Map<String, FootCheck> latestPerDay(Iterable<FootCheck> checks) {
  final out = <String, FootCheck>{};
  for (final c in checks) {
    final seen = out[c.localDate];
    if (seen == null ||
        c.atMs > seen.atMs ||
        (c.atMs == seen.atMs && c.id > seen.id)) {
      out[c.localDate] = c;
    }
  }
  return out;
}

/// The answers that made a check a finding, in question order (Something
/// found's "คุณตอบว่า" lines).
List<FootCheckQuestion> findingsOf(FootCheck c) => [
  if (c.redness == FootCheckAnswer.yesOrUnsure) FootCheckQuestion.redness,
  if (c.wound == FootCheckAnswer.yesOrUnsure) FootCheckQuestion.wound,
  if (c.swelling == FootCheckAnswer.yesOrUnsure) FootCheckQuestion.swelling,
];

/// The three questions (DESIGN-SPEC §11.3), in screen order.
enum FootCheckQuestion { redness, wound, swelling }

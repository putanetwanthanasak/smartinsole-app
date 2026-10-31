import 'package:flutter/foundation.dart';

import '../../../ble/ble_protocol.dart';
import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../rules/alert_copy.dart';
import '../../../rules/alert_engine.dart' show deltaAbove;
import '../../../storage/models.dart';
import '../../clock.dart';

// The "ความต่างของความอุ่นวันนี้" chart (DESIGN-SPEC §8.2), worked out from
// the stored readings at read time (rule 2). Pure, so it is unit-tested.

/// A foot silent for longer than this is a connection gap: the line
/// breaks and the chart marks where the data stopped. Three reading
/// periods, so one or two missed readings are not a gap. Display only.
final chartGapAfter = TempLayout.notifyPeriod * 3;

/// Two feet's readings this close together make one ΔT point: each foot
/// reports once per period, so its newest reading is never older.
const chartPairWithin = TempLayout.notifyPeriod;

/// Y axis top, °C (§8.2: 0–3.5 °C, labels at whole degrees). Display only;
/// higher values are drawn at the top.
const chartMaxC = 3.5;

/// One point of the chart's line: the largest |ΔT| of the 8 sites at one
/// paired reading, and the site it came from.
@immutable
class ChartPoint {
  const ChartPoint(this.atMs, this.deltaC, this.site);

  final int atMs;

  /// |left − right| in °C at [site].
  final double deltaC;

  /// Zone index of the site with the largest |ΔT| then (the lower index
  /// on a tie).
  final int site;

  @override
  bool operator ==(Object other) =>
      other is ChartPoint &&
      other.atMs == atMs &&
      other.deltaC == deltaC &&
      other.site == site;

  @override
  int get hashCode => Object.hash(atMs, deltaC, site);

  @override
  String toString() => 'ChartPoint($atMs, $deltaC, $site)';
}

/// A stretch with no data from [side], from its last reading.
@immutable
class ChartGap {
  const ChartGap({required this.side, required this.fromMs, this.toMs});

  final FootSide side;
  final int fromMs;

  /// When that foot's data came back; null while the gap is still open.
  final int? toMs;

  bool get ongoing => toMs == null;

  @override
  bool operator ==(Object other) =>
      other is ChartGap &&
      other.side == side &&
      other.fromMs == fromMs &&
      other.toMs == toMs;

  @override
  int get hashCode => Object.hash(side, fromMs, toMs);
}

/// Everything the chart draws.
@immutable
class TempChartData {
  const TempChartData({
    required this.startMs,
    required this.endMs,
    required this.runs,
    required this.gaps,
  });

  static const empty = TempChartData(startMs: 0, endMs: 0, runs: [], gaps: []);

  /// X axis: the first reading of the day to now.
  final int startMs;
  final int endMs;

  /// The one line (S8D-2, layout A: the largest |ΔT| of the 8 sites at
  /// each reading) as runs of points; the line breaks between runs.
  final List<List<ChartPoint>> runs;

  /// Oldest first.
  final List<ChartGap> gaps;

  bool get isEmpty => runs.isEmpty;

  /// The newest point, or null.
  ChartPoint? get last => runs.isEmpty ? null : runs.last.last;

  @override
  bool operator ==(Object other) =>
      other is TempChartData &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      listEquals(other.gaps, gaps) &&
      _runsEqual(other.runs, runs);

  @override
  int get hashCode => Object.hash(
    startMs,
    endMs,
    Object.hashAll(gaps),
    Object.hashAll([for (final r in runs) Object.hashAll(r)]),
  );
}

bool _runsEqual(List<List<ChartPoint>> a, List<List<ChartPoint>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!listEquals(a[i], b[i])) return false;
  }
  return true;
}

/// The chart for [readings] (one day, both feet, oldest first) at [now].
/// [usable] says which feet stream now: a foot that does not has an open
/// gap from its last reading, however recent.
///
/// - A point is the largest |ΔT| over the 8 sites whenever a reading of
///   one foot meets the other foot's newest reading no more than
///   [chartPairWithin] older, the same pairing as the alert engine (each
///   foot's newest reading); a site counts only when both feet read it
///   with normal quality, and a pair with no such site gives no point.
///   The point keeps its site, so two points in a row can come from
///   different sites (the alert counts each site on its own, rule 6).
///   Rows stored before the 8 sites (schema v1) give no points: their
///   sites are not these.
/// - The line breaks where two points are more than [chartGapAfter] apart.
/// - A foot with no row for longer than [chartGapAfter] is a gap, open
///   when it has not come back by [now].
TempChartData tempChartOf(
  List<TemperatureReading> readings, {
  required DateTime now,
  required Map<FootSide, bool> usable,
}) {
  if (readings.isEmpty) return TempChartData.empty;
  final nowMs = now.millisecondsSinceEpoch;
  final gapMs = chartGapAfter.inMilliseconds;
  final pairMs = chartPairWithin.inMilliseconds;

  final points = <ChartPoint>[];
  final newest = <FootSide, TemperatureReading>{};
  for (final r in readings) {
    if (r.isLegacy) continue;
    newest[r.side] = r;
    final left = newest[FootSide.left];
    final right = newest[FootSide.right];
    if (left == null || right == null) continue;
    if ((left.atMs - right.atMs).abs() > pairMs) continue;
    ChartPoint? best;
    for (var site = 0; site < TempLayout.siteCount; site++) {
      final l = left.usableC(site);
      final rr = right.usableC(site);
      if (l == null || rr == null) continue;
      final d = (l - rr).abs();
      if (best == null || d > best.deltaC) best = ChartPoint(r.atMs, d, site);
    }
    if (best == null) continue;
    if (points.isNotEmpty && points.last.atMs == best.atMs) points.removeLast();
    points.add(best);
  }

  final runs = <List<ChartPoint>>[];
  for (final p in points) {
    if (runs.isEmpty || p.atMs - runs.last.last.atMs > gapMs) {
      runs.add([p]);
    } else {
      runs.last.add(p);
    }
  }

  final gaps = <ChartGap>[];
  for (final side in FootSide.values) {
    final rows = [
      for (final r in readings)
        if (r.side == side) r.atMs,
    ];
    if (rows.isEmpty) continue;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i] - rows[i - 1] > gapMs) {
        gaps.add(ChartGap(side: side, fromMs: rows[i - 1], toMs: rows[i]));
      }
    }
    if (!(usable[side] ?? false) || nowMs - rows.last > gapMs) {
      gaps.add(ChartGap(side: side, fromMs: rows.last));
    }
  }
  gaps.sort((a, b) => a.fromMs.compareTo(b.fromMs));

  final start = readings.first.atMs;
  return TempChartData(
    startMs: start,
    endMs: nowMs > readings.last.atMs ? nowMs : readings.last.atMs,
    runs: runs,
    gaps: _merged(gaps, gapMs),
  );
}

/// Both feet dropping together (the phone's Bluetooth, say) is one gap:
/// gaps that start within [gapMs] of an earlier one are folded into it.
List<ChartGap> _merged(List<ChartGap> gaps, int gapMs) {
  final out = <ChartGap>[];
  for (final g in gaps) {
    if (out.isNotEmpty && g.fromMs - out.last.fromMs <= gapMs) {
      final prev = out.last;
      final open = prev.ongoing || g.ongoing;
      out[out.length - 1] = ChartGap(
        side: prev.ongoing || !g.ongoing ? prev.side : g.side,
        fromMs: prev.fromMs,
        toMs: open ? null : (g.toMs! > prev.toMs! ? g.toMs : prev.toMs),
      );
    } else {
      out.add(g);
    }
  }
  return out;
}

String _siteTh(int site) => footLayout.zones[site].nameTh;

String _time(int ms) => hhmm(DateTime.fromMillisecondsSinceEpoch(ms));

/// The second line of the gap label under "ขาดข้อมูล": "ตั้งแต่ HH:mm"
/// while [g] is open, "HH:mm–HH:mm" once data came back (it does not read
/// as still disconnected). [wrapped] breaks the range after the dash, for
/// a chart too narrow for it on one line (large text). **Draft copy**
/// (DESIGN-SPEC Appendix A).
String gapLabelTime(ChartGap g, {bool wrapped = false}) => g.ongoing
    ? 'ตั้งแต่ ${_time(g.fromMs)}'
    : '${_time(g.fromMs)}–${wrapped ? '\n' : ''}${_time(g.toMs!)}';

String _degrees(double c) => '${formatDelta(c)}$nbspองศา';

/// The end label next to the line's last point: its site's name (S8D-2
/// draft, DESIGN-SPEC Appendix A).
String chartEndLabel(ChartPoint p) => _siteTh(p.site);

/// TalkBack summary of the chart (§8.2), e.g. "กราฟความต่างของความอุ่นวันนี้
/// จุดที่ต่างกันมากที่สุดขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 13:45 ตอนนี้
/// 2.6 องศาที่กลางส้นเท้า". **Draft copy** (DESIGN-SPEC Appendix A, S6B;
/// one line of the 8 sites since S8D-2).
String chartSummary(TempChartData d, {required double deltaC}) {
  const title = 'กราฟความต่างของความอุ่นวันนี้';
  if (d.isEmpty) return '$title ยังไม่มีข้อมูล';
  final open = d.gaps.isNotEmpty && d.gaps.last.ongoing;
  final parts = <String>[title, _lineSummary(d.runs, deltaC, open: open)];
  if (d.gaps.isNotEmpty) {
    final g = d.gaps.last;
    final foot = 'เท้า${sideTh(g.side)}';
    parts.add(
      g.ongoing
          ? 'ขาดข้อมูล$footตั้งแต่ ${_time(g.fromMs)}'
          : 'ขาดข้อมูล$footช่วง ${_time(g.fromMs)}–${_time(g.toMs!)}',
    );
  }
  return parts.join(' ');
}

String _lineSummary(
  List<List<ChartPoint>> runs,
  double deltaC, {
  required bool open,
}) {
  const name = 'จุดที่ต่างกันมากที่สุด';
  bool above(ChartPoint p) => deltaAbove(p.deltaC, deltaC);
  final last = runs.last.last;
  final now =
      '${open ? 'ล่าสุด' : 'ตอนนี้'} ${_degrees(last.deltaC)}'
      'ที่${_siteTh(last.site)}';

  if (above(last)) {
    // The start of the current stretch above the threshold.
    final run = runs.last;
    var i = run.length - 1;
    while (i > 0 && above(run[i - 1])) {
      i--;
    }
    return '$nameขึ้นถึงระดับที่ควรระวังตั้งแต่ราว ${_time(run[i].atMs)} $now';
  }
  // The newest earlier stretch above it, if any.
  final all = [for (final r in runs) ...r];
  for (var i = all.length - 1; i >= 0; i--) {
    if (!above(all[i])) continue;
    var j = i;
    while (j > 0 && above(all[j - 1])) {
      j--;
    }
    final period = j == i
        ? 'ราว ${_time(all[i].atMs)}'
        : 'ช่วง ${_time(all[j].atMs)}–${_time(all[i].atMs)}';
    return '$nameเคยขึ้นถึงระดับที่ควรระวัง$period $now';
  }
  final max = all.fold<double>(0, (m, p) => p.deltaC > m ? p.deltaC : m);
  // The next half degree above the highest point ("ต่ำกว่า 0.5 องศาตลอด").
  final bound = ((max * 2).floor() + 1) / 2;
  return '$nameต่ำกว่า ${_degrees(bound)}ตลอด';
}

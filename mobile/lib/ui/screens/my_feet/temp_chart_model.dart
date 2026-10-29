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

/// One |ΔT| point at one site.
@immutable
class ChartPoint {
  const ChartPoint(this.atMs, this.deltaC);

  final int atMs;

  /// |left − right| in °C.
  final double deltaC;

  @override
  bool operator ==(Object other) =>
      other is ChartPoint && other.atMs == atMs && other.deltaC == deltaC;

  @override
  int get hashCode => Object.hash(atMs, deltaC);
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
    required this.sites,
    required this.runs,
    required this.gaps,
  });

  static const empty = TempChartData(
    startMs: 0,
    endMs: 0,
    sites: [],
    runs: {},
    gaps: [],
  );

  /// X axis: the first reading of the day to now.
  final int startMs;
  final int endMs;

  /// INTERIM (S8D-1): the two sites drawn (zone indexes, in zone order):
  /// the first dashed, the second solid. S8D-2 draws one line, the largest
  /// |ΔT| of the 8 sites.
  final List<int> sites;

  /// Per site of [sites], the line as runs of points; the line breaks
  /// between runs.
  final Map<int, List<List<ChartPoint>>> runs;

  /// Oldest first.
  final List<ChartGap> gaps;

  bool get isEmpty => runs.values.every((r) => r.isEmpty);

  List<List<ChartPoint>> runsOf(int site) => runs[site] ?? const [];

  /// The newest point at [site], or null.
  ChartPoint? last(int site) {
    final r = runsOf(site);
    return r.isEmpty ? null : r.last.last;
  }

  @override
  bool operator ==(Object other) =>
      other is TempChartData &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      listEquals(other.sites, sites) &&
      listEquals(other.gaps, gaps) &&
      sites.every((s) => _runsEqual(other.runsOf(s), runsOf(s)));

  @override
  int get hashCode => Object.hash(
    startMs,
    endMs,
    Object.hashAll(sites),
    Object.hashAll(gaps),
    Object.hashAll([
      for (final s in sites)
        for (final r in runsOf(s)) Object.hashAll(r),
    ]),
  );
}

bool _runsEqual(List<List<ChartPoint>> a, List<List<ChartPoint>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!listEquals(a[i], b[i])) return false;
  }
  return true;
}

/// The chart of [sites] for [readings] (one day, both feet, oldest first)
/// at [now]. [usable] says which feet stream now: a foot that does not has
/// an open gap from its last reading, however recent.
///
/// - A point is |ΔT| at a site whenever a reading of one foot meets the
///   other foot's newest reading no more than [chartPairWithin] older, the
///   same pairing as the alert engine (each foot's newest reading), and
///   both read that site with normal quality. Rows stored before the 8
///   sites (schema v1) give no points: their sites are not these.
/// - The line breaks where two points are more than [chartGapAfter] apart.
/// - A foot with no row for longer than [chartGapAfter] is a gap, open
///   when it has not come back by [now].
TempChartData tempChartOf(
  List<TemperatureReading> readings, {
  required DateTime now,
  required Map<FootSide, bool> usable,
  required List<int> sites,
}) {
  if (readings.isEmpty) return TempChartData.empty;
  final nowMs = now.millisecondsSinceEpoch;
  final gapMs = chartGapAfter.inMilliseconds;
  final pairMs = chartPairWithin.inMilliseconds;

  final points = {for (final s in sites) s: <ChartPoint>[]};
  final newest = <FootSide, TemperatureReading>{};
  for (final r in readings) {
    if (r.isLegacy) continue;
    newest[r.side] = r;
    final left = newest[FootSide.left];
    final right = newest[FootSide.right];
    if (left == null || right == null) continue;
    if ((left.atMs - right.atMs).abs() > pairMs) continue;
    for (final site in sites) {
      final l = left.usableC(site);
      final rr = right.usableC(site);
      if (l == null || rr == null) continue;
      final p = ChartPoint(r.atMs, (l - rr).abs());
      final list = points[site]!;
      if (list.isNotEmpty && list.last.atMs == p.atMs) list.removeLast();
      list.add(p);
    }
  }

  List<List<ChartPoint>> split(List<ChartPoint> ps) {
    final out = <List<ChartPoint>>[];
    for (final p in ps) {
      if (out.isEmpty || p.atMs - out.last.last.atMs > gapMs) {
        out.add([p]);
      } else {
        out.last.add(p);
      }
    }
    return out;
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
    sites: sites,
    runs: {for (final s in sites) s: split(points[s]!)},
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

/// TalkBack summary of the chart (§8.2), e.g. "กราฟความต่างของความอุ่นวันนี้
/// ส้นเท้าขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 13:45 ตอนนี้ 2.6 องศา หน้าเท้า
/// ต่ำกว่า 0.5 องศาตลอด". **Draft copy** (DESIGN-SPEC Appendix A, S6B).
String chartSummary(TempChartData d, {required double deltaC}) {
  const title = 'กราฟความต่างของความอุ่นวันนี้';
  if (d.isEmpty) return '$title ยังไม่มีข้อมูล';
  final open = d.gaps.isNotEmpty && d.gaps.last.ongoing;
  final parts = <String>[title];
  for (final site in d.sites.reversed) {
    parts.add(_siteSummary(site, d.runsOf(site), deltaC, open: open));
  }
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

String _siteSummary(
  int site,
  List<List<ChartPoint>> runs,
  double deltaC, {
  required bool open,
}) {
  final name = _siteTh(site);
  if (runs.isEmpty) return '$nameยังไม่มีข้อมูล';
  bool above(ChartPoint p) => deltaAbove(p.deltaC, deltaC);
  final last = runs.last.last;
  final now = '${open ? 'ล่าสุด' : 'ตอนนี้'} ${_degrees(last.deltaC)}';

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

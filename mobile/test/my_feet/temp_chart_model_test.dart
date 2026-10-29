import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/ui/screens/my_feet/temp_chart_model.dart';

final _day = DateTime(2026, 10, 25, 8);
final _period = TempLayout.notifyPeriod.inMilliseconds;
const _deltaC = 2.2;
const _both = {FootSide.left: true, FootSide.right: true};

/// The two sites the chart draws here (INTERIM, S8D-1): MTH1 (the old
/// forefoot site's role) and the heel centre.
const _fore = 1;
const _heel = 5;
const _sites = [_fore, _heel];

/// One reading: [fore] at MTH1, [heel] at the heel centre, 30.5 °C at the
/// other sites; [quality] at every site.
TemperatureReading _r(
  FootSide side,
  int atMs, {
  double? fore = 31,
  double? heel = 30,
  TempQuality quality = TempQuality.normal,
}) => TemperatureReading(
  atMs: atMs,
  localDate: '2026-10-25',
  side: side,
  siteC: [
    for (var i = 0; i < TempLayout.siteCount; i++)
      i == _fore
          ? fore
          : i == _heel
          ? heel
          : 30.5,
  ],
  siteQuality: List.filled(TempLayout.siteCount, quality),
  quality: quality,
  timeFromArrival: false,
);

TempChartData _chart(
  List<TemperatureReading> readings, {
  required DateTime now,
  required Map<FootSide, bool> usable,
}) => tempChartOf(readings, now: now, usable: usable, sites: _sites);

/// Both feet every period from [fromMs] for [n] readings; the right foot
/// 5 s after the left, its forefoot [rightFore] (by index).
List<TemperatureReading> _day2(
  int fromMs,
  int n, {
  double Function(int i)? rightFore,
  bool Function(int i)? rightMissing,
}) => [
  for (var i = 0; i < n; i++) ...[
    _r(FootSide.left, fromMs + i * _period),
    if (!(rightMissing?.call(i) ?? false))
      _r(
        FootSide.right,
        fromMs + i * _period + 5000,
        fore: rightFore?.call(i) ?? 31.3,
      ),
  ],
];

void main() {
  final t0 = _day.millisecondsSinceEpoch;

  test('no readings: empty', () {
    final d = _chart(const [], now: _day, usable: _both);
    expect(d.isEmpty, isTrue);
    expect(chartSummary(d, deltaC: _deltaC), contains('ยังไม่มีข้อมูล'));
  });

  test('pairs the two feet: one point per reading once both have one', () {
    final rs = _day2(t0, 4);
    final d = _chart(
      rs,
      now: DateTime.fromMillisecondsSinceEpoch(rs.last.atMs),
      usable: _both,
    );
    // The first left reading has no right partner yet.
    expect(d.runsOf(_fore).single.length, 7);
    expect(d.last(_fore)!.deltaC, closeTo(0.3, 1e-9));
    expect(d.last(_heel)!.deltaC, 0);
    expect(d.gaps, isEmpty);
    expect(d.startMs, t0);
  });

  test('readings further apart than notifyPeriod are not paired', () {
    final rs = [_r(FootSide.left, t0), _r(FootSide.right, t0 + _period + 1000)];
    final d = _chart(rs, now: _day, usable: _both);
    expect(d.isEmpty, isTrue);
  });

  test('poor-contact and sensor-error readings make no point', () {
    final rs = [
      _r(FootSide.left, t0),
      _r(FootSide.right, t0 + 1000, quality: TempQuality.poorContact),
      _r(FootSide.right, t0 + 2000, quality: TempQuality.sensorFault),
    ];
    expect(_chart(rs, now: _day, usable: _both).isEmpty, isTrue);
  });

  test('a missing site value makes no point at that site only', () {
    final rs = [
      _r(FootSide.left, t0),
      _r(FootSide.right, t0 + 1000, heel: null),
    ];
    final d = _chart(rs, now: _day, usable: _both);
    expect(d.runs[_fore], hasLength(1));
    expect(d.runs[_heel], isEmpty);
  });

  test('a gap that ended: the line breaks and the gap is closed', () {
    // The right foot misses readings 10..19 (5 min).
    final rs = _day2(t0, 30, rightMissing: (i) => i >= 10 && i < 20);
    final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
    final d = _chart(rs, now: end, usable: _both);
    expect(d.runs[_fore], hasLength(2));
    final g = d.gaps.single;
    expect(g.side, FootSide.right);
    expect(g.ongoing, isFalse);
    expect(g.fromMs, t0 + 9 * _period + 5000);
    expect(g.toMs, t0 + 20 * _period + 5000);
  });

  test('one or two missed readings are not a gap', () {
    final rs = _day2(t0, 10, rightMissing: (i) => i == 4 || i == 5);
    final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
    final d = _chart(rs, now: end, usable: _both);
    expect(d.gaps, isEmpty);
    expect(d.runs[_fore], hasLength(1));
  });

  test('a foot that is not usable now has an open gap from its last row', () {
    final rs = _day2(t0, 10);
    final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
    final d = _chart(
      rs,
      now: end,
      usable: const {FootSide.left: true, FootSide.right: false},
    );
    final g = d.gaps.single;
    expect(g.ongoing, isTrue);
    expect(g.side, FootSide.right);
    expect(g.fromMs, rs.last.atMs);
  });

  test('silence longer than the gap time is an open gap, x axis to now', () {
    final rs = _day2(t0, 10);
    final now = DateTime.fromMillisecondsSinceEpoch(
      rs.last.atMs + chartGapAfter.inMilliseconds + 1,
    );
    final d = _chart(rs, now: now, usable: _both);
    // Both feet stopped together: one gap.
    expect(d.gaps.single.ongoing, isTrue);
    expect(d.gaps.single.side, FootSide.left);
    expect(d.endMs, now.millisecondsSinceEpoch);
  });

  group('summary', () {
    test('above now: from when, and the value', () {
      final rs = _day2(t0, 20, rightFore: (i) => i >= 10 ? 33.6 : 31.3);
      final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
      final s = chartSummary(
        _chart(rs, now: end, usable: _both),
        deltaC: _deltaC,
      );
      expect(
        s,
        'กราฟความต่างของความอุ่นวันนี้ '
        'กลางส้นเท้าต่ำกว่า 0.5 องศาตลอด '
        'โคนนิ้วหัวแม่เท้าขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 08:05 '
        'ตอนนี้ 2.6 องศา',
      );
    });

    test('above earlier, and an open gap', () {
      final rs = _day2(t0, 20, rightFore: (i) => i >= 4 && i < 8 ? 33.6 : 31.3);
      final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
      final s = chartSummary(
        _chart(
          rs,
          now: end,
          usable: const {FootSide.left: true, FootSide.right: false},
        ),
        deltaC: _deltaC,
      );
      expect(
        s,
        contains('โคนนิ้วหัวแม่เท้าเคยขึ้นถึงระดับที่ควรระวังช่วง 08:02–08:04'),
      );
      expect(s, contains('ล่าสุด 0.3 องศา'));
      expect(s, endsWith('ขาดข้อมูลเท้าขวาตั้งแต่ 08:09'));
    });
  });

  group('gap label', () {
    final from = DateTime(2026, 10, 18, 11, 25).millisecondsSinceEpoch;
    final to = DateTime(2026, 10, 18, 11, 50).millisecondsSinceEpoch;

    test('open: "ตั้งแต่ HH:mm"', () {
      final g = ChartGap(side: FootSide.right, fromMs: from);
      expect(gapLabelTime(g), 'ตั้งแต่ 11:25');
    });

    test('ended: the range, never "ตั้งแต่"', () {
      final g = ChartGap(side: FootSide.right, fromMs: from, toMs: to);
      expect(gapLabelTime(g), '11:25–11:50');
      expect(gapLabelTime(g, wrapped: true), '11:25–\n11:50');
    });

    test('the spoken summary gives the same range', () {
      // Right foot silent for readings 6–11, then back.
      final rs = _day2(t0, 20, rightMissing: (i) => i > 5 && i < 12);
      final d = _chart(
        rs,
        now: DateTime.fromMillisecondsSinceEpoch(rs.last.atMs),
        usable: _both,
      );
      final g = d.gaps.last;
      expect(g.ongoing, isFalse);
      expect(
        chartSummary(d, deltaC: _deltaC),
        endsWith('ขาดข้อมูลเท้าขวาช่วง ${gapLabelTime(g)}'),
      );
    });
  });
}

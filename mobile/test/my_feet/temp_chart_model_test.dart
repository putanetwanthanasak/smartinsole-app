import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/alert_copy.dart' show nbsp;
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/ui/screens/my_feet/temp_chart_model.dart';

final _day = DateTime(2026, 10, 25, 8);
final _period = TempLayout.notifyPeriod.inMilliseconds;
const _deltaC = 2.2;
const _both = {FootSide.left: true, FootSide.right: true};

const _mth1 = 1;
const _heel = 5;
const _lateralHeel = 7;

/// One reading: 31 °C at every site except [sites] (site → °C, null:
/// could not read); [quality] at every site.
TemperatureReading _r(
  FootSide side,
  int atMs, {
  Map<int, double?> sites = const {},
  TempQuality quality = TempQuality.normal,
}) => TemperatureReading(
  atMs: atMs,
  localDate: '2026-10-25',
  side: side,
  siteC: [
    for (var i = 0; i < TempLayout.siteCount; i++)
      sites.containsKey(i) ? sites[i] : 31,
  ],
  siteQuality: List.filled(TempLayout.siteCount, quality),
  quality: quality,
  timeFromArrival: false,
);

TempChartData _chart(
  List<TemperatureReading> readings, {
  required DateTime now,
  required Map<FootSide, bool> usable,
}) => tempChartOf(readings, now: now, usable: usable);

/// Both feet every period from [fromMs] for [n] readings; the right foot
/// 5 s after the left, with [right] (by index) as its sites (MTH1 0.3 °C
/// warmer by default).
List<TemperatureReading> _day2(
  int fromMs,
  int n, {
  Map<int, double?> Function(int i)? right,
  bool Function(int i)? rightMissing,
}) => [
  for (var i = 0; i < n; i++) ...[
    _r(FootSide.left, fromMs + i * _period),
    if (!(rightMissing?.call(i) ?? false))
      _r(
        FootSide.right,
        fromMs + i * _period + 5000,
        sites: right?.call(i) ?? const {_mth1: 31.3},
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
    expect(d.runs.single.length, 7);
    expect(d.last!.deltaC, closeTo(0.3, 1e-9));
    expect(d.last!.site, _mth1);
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

  test('one line: the largest |ΔT| of the 8 sites, with its site', () {
    final rs = [
      _r(FootSide.left, t0, sites: {_heel: 30}),
      _r(FootSide.right, t0 + 1000, sites: {_mth1: 32.0, _lateralHeel: 33.1}),
    ];
    final d = _chart(rs, now: _day, usable: _both);
    final p = d.runs.single.single;
    expect(p.site, _lateralHeel);
    expect(p.deltaC, closeTo(2.1, 1e-9));
  });

  test('equal |ΔT| at two sites: the lower zone', () {
    final rs = [
      _r(FootSide.left, t0),
      _r(FootSide.right, t0 + 1000, sites: {_heel: 32, _mth1: 30}),
    ];
    expect(_chart(rs, now: _day, usable: _both).last!.site, _mth1);
  });

  test('a site the sensor could not read is left out; the others count', () {
    final rs = [
      _r(FootSide.left, t0),
      _r(FootSide.right, t0 + 1000, sites: {_heel: null, _mth1: 31.4}),
    ];
    final d = _chart(rs, now: _day, usable: _both);
    expect(d.last!.site, _mth1);
    expect(d.last!.deltaC, closeTo(0.4, 1e-9));
  });

  test('no site with a two-foot reading: no point', () {
    final rs = [
      _r(FootSide.left, t0),
      _r(
        FootSide.right,
        t0 + 1000,
        sites: {for (var i = 0; i < TempLayout.siteCount; i++) i: null},
      ),
    ];
    expect(_chart(rs, now: _day, usable: _both).isEmpty, isTrue);
  });

  test('two points above the band in a row from different sites '
      '(no TEMP_DELTA: the rule counts each site, rule 6)', () {
    // Reading 8: MTH1 above; reading 9: lateral heel above; MTH1 back.
    // The alert engine raises nothing for this (alert_engine_test: "per
    // site: two different sites above once each is no alert").
    final rs = _day2(
      t0,
      10,
      right: (i) => switch (i) {
        8 => const {_mth1: 33.6},
        9 => const {_lateralHeel: 33.5},
        _ => const {_mth1: 31.3},
      },
    );
    final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
    final d = _chart(rs, now: end, usable: _both);
    final last2 = d.runs.single.sublist(d.runs.single.length - 2);
    expect([for (final p in last2) p.site], [_mth1, _lateralHeel]);
    expect(last2.every((p) => p.deltaC > _deltaC), isTrue);
    expect(chartEndLabel(d.last!), 'ส้นเท้าด้านนอก');
    // The summary reads as one stretch above the band, named by the last
    // point's site.
    expect(
      chartSummary(d, deltaC: _deltaC),
      'กราฟความต่างของความอุ่นวันนี้ '
      'จุดที่ต่างกันมากที่สุดขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 08:04 '
      'ตอนนี้ 2.5$nbspองศาที่ส้นเท้าด้านนอก',
    );
  });

  test('a gap that ended: the line breaks and the gap is closed', () {
    // The right foot misses readings 10..19 (5 min).
    final rs = _day2(t0, 30, rightMissing: (i) => i >= 10 && i < 20);
    final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
    final d = _chart(rs, now: end, usable: _both);
    expect(d.runs, hasLength(2));
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
    expect(d.runs, hasLength(1));
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
    test('never above: the next half degree', () {
      final rs = _day2(t0, 5);
      final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
      expect(
        chartSummary(
          _chart(rs, now: end, usable: _both),
          deltaC: _deltaC,
        ),
        'กราฟความต่างของความอุ่นวันนี้ '
        'จุดที่ต่างกันมากที่สุดต่ำกว่า 0.5$nbspองศาตลอด',
      );
    });

    test('above now: from when, and the value', () {
      final rs = _day2(t0, 20, right: (i) => {_mth1: i >= 10 ? 33.6 : 31.3});
      final end = DateTime.fromMillisecondsSinceEpoch(rs.last.atMs);
      final s = chartSummary(
        _chart(rs, now: end, usable: _both),
        deltaC: _deltaC,
      );
      expect(
        s,
        'กราฟความต่างของความอุ่นวันนี้ '
        'จุดที่ต่างกันมากที่สุดขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 08:05 '
        'ตอนนี้ 2.6$nbspองศาที่โคนนิ้วหัวแม่เท้า',
      );
    });

    test('above earlier, and an open gap', () {
      final rs = _day2(
        t0,
        20,
        right: (i) => {_mth1: i >= 4 && i < 8 ? 33.6 : 31.3},
      );
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
        contains(
          'จุดที่ต่างกันมากที่สุดเคยขึ้นถึงระดับที่ควรระวังช่วง 08:02–08:04',
        ),
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

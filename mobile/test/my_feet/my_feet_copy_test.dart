import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_copy.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/rules/pressure_level.dart';
import 'package:smartinsole/ui/screens/home/home_model.dart';
import 'package:smartinsole/ui/screens/my_feet/my_feet_copy.dart';
import 'package:smartinsole/ui/screens/my_feet/my_feet_model.dart';

import '../helpers/pump_app.dart' show testThresholds;

const _low = PressureLevel.low;
const _mid = PressureLevel.medium;
const _high = PressureLevel.high;

PressureFootView _foot(
  FootSide side,
  List<int> kpa,
  List<PressureLevel> levels, {
  int? peak,
  int? pti,
  int? conc,
}) => PressureFootView(
  map: FootMapView(side: side, levels: levels),
  kpa: kpa,
  walkingPeakKpa: peak,
  ptiKpaS: pti,
  concentrationPct: conc,
);

PressureFootView _none(FootSide side) =>
    PressureFootView(map: FootMapView(side: side));

final _lows = List.filled(footLayout.zones.length, _low);
final _flat = [40, 45, 50, 30, 25, 60];

TempTabView _temp({
  bool left = true,
  bool right = true,
  double? fore = 0.3,
  double? heel = 0.0,
  Map<TempSite, TempAlertView> alerts = const {},
  TempQuality leftQuality = TempQuality.normal,
}) => TempTabView(
  left: TempFootView(
    side: FootSide.left,
    usable: left,
    forefootC: left ? 31.0 : null,
    heelC: left ? 30.6 : null,
    quality: left ? leftQuality : null,
  ),
  right: TempFootView(
    side: FootSide.right,
    usable: right,
    forefootC: right ? 30.7 : null,
    heelC: right ? 30.6 : null,
    quality: right ? TempQuality.normal : null,
  ),
  minute: DateTime(2026, 10, 25, 13),
  deltaForefootC: left && right ? fore : null,
  deltaHeelC: left && right ? heel : null,
  alerts: alerts,
);

void main() {
  final t = testThresholds;

  group('pressure banner', () {
    test('safe, and level 2 stays safe', () {
      final v = PressureTabView(
        left: _foot(FootSide.left, _flat, [_mid, ..._lows.skip(1)]),
        right: _foot(FootSide.right, _flat, _lows),
      );
      final b = pressureBanner(v);
      expect(b.level, PatientLevel.safe);
      expect(b.title, 'แรงกดกระจายดีทั้งสองข้าง');
      expect(b.linkCode, isNull);
      expect(b.connect, isFalse);
    });

    test('no data: connect button, never safe', () {
      final b = pressureBanner(
        PressureTabView(
          left: _none(FootSide.left),
          right: _none(FootSide.right),
        ),
      );
      expect(b.level, PatientLevel.noData);
      expect(b.title, 'ยังไม่ได้รับข้อมูล');
      expect(b.connect, isTrue);
    });

    test('one foot missing names it', () {
      final b = pressureBanner(
        PressureTabView(
          left: _foot(FootSide.left, _flat, _lows),
          right: _none(FootSide.right),
        ),
      );
      expect(b.level, PatientLevel.noData);
      expect(b.title, 'ยังไม่ได้รับข้อมูลเท้าขวา');
      expect(b.line, 'ต้องเชื่อมต่อแผ่นรองเท้าขวาก่อน');
      expect(b.connect, isTrue);
    });

    test("a level-3 rule wins, with the alert's own copy", () {
      const cause = StatusCause(
        code: AlertCode.pressurePeak,
        side: FootSide.left,
        channel: 1,
      );
      final b = pressureBanner(
        PressureTabView(
          left: _foot(FootSide.left, _flat, _lows),
          right: _none(FootSide.right),
          cause: cause,
        ),
      );
      final copy = alertCopyFor(
        AlertCode.pressurePeak,
        side: FootSide.left,
        channel: 1,
      );
      expect(b.level, PatientLevel.careful);
      expect(b.title, copy.title);
      expect(b.line, copy.detail);
      expect(b.linkCode, AlertCode.pressurePeak);
      expect(b.connect, isFalse);
    });
  });

  group('top zones', () {
    test('ranked by the higher kPa; both sides when the level matches', () {
      final v = PressureTabView(
        left: _foot(
          FootSide.left,
          [40, 210, 50, 30, 25, 60],
          [_low, _high, _low, _low, _low, _low],
        ),
        right: _foot(FootSide.right, _flat, _lows),
      );
      final rows = topZones(v);
      expect(rows, hasLength(topZoneCount));
      expect(rows[0].channel, 1);
      expect(rows[0].side, FootSide.left);
      expect(rows[0].level, _high);
      expect(rows[1].channel, 5);
      expect(rows[1].sideText, 'ทั้งสองข้าง');
      expect(rows[2].channel, 2);
    });

    test('one foot: its side is named; none: empty', () {
      final rows = topZones(
        PressureTabView(
          left: _none(FootSide.left),
          right: _foot(FootSide.right, _flat, _lows),
        ),
      );
      expect(rows.every((r) => r.side == FootSide.right), isTrue);
      expect(topZones(PressureTabView.initial), isEmpty);
    });
  });

  test('pressure detail rows: figures, "—", and thresholds from the file', () {
    final rows = pressureDetailRows(
      PressureTabView(
        left: _foot(FootSide.left, _flat, _lows, peak: 132, pti: 9, conc: 31),
        right: _none(FootSide.right),
      ),
      t,
    );
    expect(rows[0].value, 'ซ้าย 132 · ขวา — kPa');
    expect(rows[1].value, 'ซ้าย 9 · ขวา — kPa·s');
    expect(rows[2].value, 'ซ้าย 31% · ขวา —');
    expect(rows[3].value, contains('${t.alertKpa.round()} kPa'));
    expect(rows[3].value, contains('${t.ptiKpaS.round()} kPa·s'));
  });

  group('temperature banner', () {
    final at = DateTime(2026, 10, 25, 12, 57);
    const noSince = {FootSide.left: null, FootSide.right: null};

    test('safe with the latest time, or waiting', () {
      final b = tempBanner(_temp(), latestAt: at, since: noSince);
      expect(b.level, PatientLevel.safe);
      expect(b.line, 'วัดล่าสุด 12:57');
      expect(
        tempBanner(_temp(), latestAt: null, since: noSince).line,
        'รอผลการวัด',
      );
    });

    test('rest only while TEMP_DELTA holds, the larger site named', () {
      final b = tempBanner(
        _temp(
          fore: -2.6,
          alerts: const {
            TempSite.forefoot: TempAlertView(
              site: TempSite.forefoot,
              warmerSide: FootSide.right,
              deltaC: 2.6,
              consecutive: 3,
            ),
          },
        ),
        latestAt: at,
        since: noSince,
      );
      expect(b.level, PatientLevel.rest);
      expect(b.title, 'หน้าเท้าขวาอุ่นกว่าซ้าย 2.6 องศา');
      expect(b.linkCode, AlertCode.tempDelta);
      // Above once, not yet twice: still safe.
      expect(
        tempBanner(_temp(fore: -2.6), latestAt: at, since: noSince).level,
        PatientLevel.safe,
      );
    });

    test('one foot missing: since when, or not connected today', () {
      final b = tempBanner(
        _temp(right: false),
        latestAt: at,
        since: {FootSide.left: null, FootSide.right: at},
      );
      expect(b.level, PatientLevel.noData);
      expect(b.title, 'เทียบความอุ่นไม่ได้');
      expect(b.line, 'เท้าขวาหลุดการเชื่อมต่อตั้งแต่ 12:57');
      expect(
        tempBanner(_temp(right: false), latestAt: at, since: noSince).line,
        'เท้าขวายังไม่ได้เชื่อมต่อ',
      );
    });

    test('both streaming but no site compares: never safe', () {
      final b = tempBanner(
        _temp(fore: null, heel: null),
        latestAt: at,
        since: noSince,
      );
      expect(b.level, PatientLevel.noData);
      expect(b.connect, isFalse);
    });

    test('both missing: the no-data banner', () {
      final b = tempBanner(
        _temp(left: false, right: false),
        latestAt: null,
        since: noSince,
      );
      expect(b.title, 'ยังไม่ได้รับข้อมูล');
      expect(b.connect, isTrue);
    });
  });

  group('site cards', () {
    test('close, warmer above the threshold, alerting', () {
      expect(siteCard(_temp(), TempSite.heel, t).note, 'ใกล้เคียงกัน');
      final over = siteCard(_temp(fore: -2.6), TempSite.forefoot, t);
      expect(over.note, 'ขวาอุ่นกว่า');
      expect(over.deltaC, 2.6);
      expect(over.alerting, isFalse);
      final alerting = siteCard(
        _temp(
          fore: -2.6,
          alerts: const {
            TempSite.forefoot: TempAlertView(
              site: TempSite.forefoot,
              warmerSide: FootSide.right,
              deltaC: 2.6,
              consecutive: 2,
            ),
          },
        ),
        TempSite.forefoot,
        t,
      );
      expect(alerting.alerting, isTrue);
    });

    test('rule 4: one foot missing shows no number', () {
      final c = siteCard(_temp(right: false), TempSite.forefoot, t);
      expect(c.deltaC, isNull);
      expect(c.missing, isTrue);
      expect(c.note, 'ต้องเชื่อมต่อทั้งสองข้าง');
      expect(
        siteCard(_temp(fore: null), TempSite.forefoot, t).note,
        'ยังวัดไม่ได้',
      );
    });
  });

  test('citation', () {
    expect(citation('Lavery et al. (2004)'), 'Lavery et al., 2004');
    expect(citation('เกณฑ์ของโครงงาน'), 'เกณฑ์ของโครงงาน');
  });

  group('temperature detail rows', () {
    test('both feet: values, quality, threshold with the source', () {
      final rows = tempDetailRows(
        _temp(leftQuality: TempQuality.poorContact),
        t,
        latestAt: DateTime(2026, 10, 25, 12, 57, 31),
        since: const {},
      );
      String row(String label) =>
          rows.firstWhere((r) => r.label == label).value;
      expect(row('หน้าเท้าตอนนี้'), 'ซ้าย 31.0 · ขวา 30.7 °C');
      expect(
        row('วัดทุก'),
        '${TempLayout.notifyPeriod.inSeconds} วินาที · ล่าสุด 12:57:31',
      );
      expect(row('คุณภาพสัญญาณ'), 'เท้าซ้าย สัมผัสไม่ดี');
      expect(row('เกณฑ์'), contains('(Lavery et al., 2004)'));
      expect(row('เกณฑ์'), contains('ติดกัน ${t.consecutiveReadings} ครั้ง'));
    });

    test('all good: "ดีทั้ง 4 จุด"', () {
      final rows = tempDetailRows(_temp(), t, latestAt: null, since: const {});
      expect(rows.last.value, 'ดีทั้ง 4 จุด');
    });

    test('one foot missing: no two-foot rows', () {
      final rows = tempDetailRows(
        _temp(right: false),
        t,
        latestAt: null,
        since: const {},
      );
      expect(rows.map((r) => r.label), isNot(contains('ผลต่าง')));
      expect(rows[1].value, 'ยังไม่ได้เชื่อมต่อ');
    });
  });
}

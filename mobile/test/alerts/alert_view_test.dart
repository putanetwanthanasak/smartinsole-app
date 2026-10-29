import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/rules/pressure_level.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/ui/screens/alerts/alert_view.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../helpers/pump_app.dart';

final at = DateTime(2026, 10, 21, 14, 32, 10);

StoredAlert alert(
  AlertKind kind, {
  int level = 3,
  FootSide? side = FootSide.left,
  String? zone,
  LegacyTempSite? legacySite,
  double? value,
  double? threshold,
  String? gaitClass,
  double? gaitConfidence,
  Map<String, Object?>? details,
}) => StoredAlert(
  id: 1,
  kind: kind,
  level: level,
  patientLevel: PatientLevel.careful,
  atMs: at.millisecondsSinceEpoch,
  localDate: '2026-10-21',
  side: side,
  zone: zone,
  legacySite: legacySite,
  measuredValue: value,
  threshold: threshold,
  gaitClass: gaitClass,
  gaitConfidence: gaitConfidence,
  details: details,
);

Map<String, String> rowsOf(StoredAlert a) => {
  for (final r in detailRowsOf(a, testThresholds)) r.label: r.value,
};

void main() {
  setUpAll(() => initializeDateFormatting('th'));

  group('detail rows (§7.3)', () {
    test('TEMP_DELTA: the named zone and every qualifying site', () {
      final atMs = at.millisecondsSinceEpoch;
      final rows = rowsOf(
        alert(
          AlertKind.tempDelta,
          level: 4,
          side: FootSide.right,
          zone: 'heel',
          value: 2.6,
          threshold: 2.2,
          details: {
            'leftC': 31.4,
            'rightC': 34.0,
            'consecutive': 3,
            TempSiteEntry.listKey: [
              TempSiteEntry(zone: 'heel', deltaC: 2.6, atMs: atMs).toJson(),
              TempSiteEntry(
                zone: 'lateralHeel',
                deltaC: 2.3,
                atMs: atMs,
              ).toJson(),
            ],
          },
        ),
      );
      expect(rows, {
        'รหัส': 'TEMP_DELTA',
        'กลางส้นเท้า': 'ซ้าย 31.4 °C · ขวา 34.0 °C',
        'ผลต่างที่กลางส้นเท้า': '2.6 °C (เกณฑ์ 2.2 °C)',
        'วัดเกินเกณฑ์ติดกัน':
            '3 ครั้ง (เกณฑ์ ${testThresholds.consecutiveReadings} ครั้ง '
            'วัดทุก 30 วินาที)',
        'จุดที่เกินเกณฑ์': 'กลางส้นเท้า 2.6 · ส้นเท้าด้านนอก 2.3 °C',
        'ระดับภายในระบบ': '4 จาก 5',
        'เวลาที่พบ': '21 ต.ค. 2569 14:32:10',
        'ที่มาของเกณฑ์': 'Lavery et al. (2004)',
      });
    });

    test('TEMP_DELTA stored before the 8 sites keeps its old rows', () {
      final rows = rowsOf(
        alert(
          AlertKind.tempDelta,
          level: 4,
          side: FootSide.right,
          legacySite: LegacyTempSite.heel,
          value: 2.6,
          threshold: 2.2,
          details: {
            'leftC': 31.4,
            'rightC': 34.0,
            'consecutive': 3,
            'otherSiteDeltaC': 0.4,
          },
        ),
      );
      expect(rows, {
        'รหัส': 'TEMP_DELTA',
        'ส้นเท้า': 'ซ้าย 31.4 °C · ขวา 34.0 °C',
        'ผลต่างที่ส้นเท้า': '2.6 °C (เกณฑ์ 2.2 °C)',
        'วัดเกินเกณฑ์ติดกัน':
            '3 ครั้ง (เกณฑ์ ${testThresholds.consecutiveReadings} ครั้ง '
            'วัดทุก 30 วินาที)',
        'ผลต่างที่หน้าเท้า': '0.4 °C',
        'ระดับภายในระบบ': '4 จาก 5',
        'เวลาที่พบ': '21 ต.ค. 2569 14:32:10',
        'ที่มาของเกณฑ์': 'Lavery et al. (2004)',
      });
    });

    test('PRESSURE_PEAK: walking, gait class, stored threshold wins', () {
      final rows = rowsOf(
        alert(
          AlertKind.pressurePeak,
          zone: 'meta1',
          value: 236.4,
          threshold: 210,
          gaitClass: 'toe_walking',
          gaitConfidence: 0.78,
          details: {'walking': true},
        ),
      );
      expect(rows['ค่าที่วัดได้'], '236 kPa ที่โคนนิ้วหัวแม่เท้าซ้าย');
      expect(rows['เกณฑ์'], '210 kPa ขณะเดิน');
      expect(rows['ขณะนั้น'], 'กำลังเดิน (ตรวจจากความเร่ง)');
      expect(rows['รูปแบบการเดิน'], 'เดินเขย่งปลายเท้า · ความมั่นใจ 78%');
      expect(rows['ที่มาของเกณฑ์'], 'Owings et al. (2009)');
    });

    test('PRESSURE_PEAK without a gait class has no gait row', () {
      final rows = rowsOf(
        alert(AlertKind.pressurePeak, zone: 'heel', value: 230, threshold: 200),
      );
      expect(rows.containsKey('รูปแบบการเดิน'), isFalse);
      expect(rows.containsKey('ขณะนั้น'), isFalse);
    });

    test('PRESSURE_PTI', () {
      final rows = rowsOf(
        alert(
          AlertKind.pressurePti,
          zone: 'meta1',
          value: 92.3,
          threshold: 80,
          details: {'steps': 24, 'windowMin': 10},
        ),
      );
      expect(
        rows['ค่าที่วัดได้'],
        '92 kPa·s เฉลี่ยต่อก้าว ที่โคนนิ้วหัวแม่เท้าซ้าย',
      );
      expect(rows['เกณฑ์'], '80 kPa·s เฉลี่ยต่อก้าว ขณะเดิน');
      expect(rows['จำนวนก้าวที่ใช้'], '24 ก้าว ใน 10 นาทีล่าสุด');
      expect(rows['ที่มาของเกณฑ์'], 'Waaijman et al. (2014)');
    });

    test('LOAD_CONCENTRATION', () {
      final rows = rowsOf(
        alert(
          AlertKind.loadConcentration,
          side: FootSide.right,
          zone: 'heel',
          value: 46,
          threshold: 40,
          details: {'steps': 10},
        ),
      );
      expect(rows['ค่าที่วัดได้'], '46% ของแรงกดทั้งฝ่าเท้า ที่กลางส้นเท้าขวา');
      expect(
        rows['เกณฑ์'],
        '40% ติดกัน ${testThresholds.concentrationSteps} ก้าว',
      );
      expect(rows['จำนวนก้าวที่ใช้'], '10 ก้าวติดกัน');
      expect(rows['ที่มาของเกณฑ์'], 'ตัวชี้วัดของโครงงาน');
    });

    test('DEVICE_LOST: no time or source rows, minutes rounded up', () {
      final last = DateTime(2026, 10, 20, 16, 14, 5);
      final rows = rowsOf(
        alert(
          AlertKind.deviceLost,
          level: 1,
          value: 5.02,
          threshold: 5,
          details: {
            'lastDataAtMs': last.millisecondsSinceEpoch,
            'lastBatteryPct': 43,
          },
        ),
      );
      expect(rows, {
        'รหัส': 'DEVICE_LOST',
        'เชื่อมต่อได้ครั้งล่าสุด': '20 ต.ค. 2569 16:14:05',
        'หลุดการเชื่อมต่อนาน': '6 นาที (เกณฑ์ 5 นาที)',
        'แบตเตอรี่ครั้งล่าสุด': '43%',
        'ระดับภายในระบบ': '1 จาก 5',
      });
    });
  });

  group('maps', () {
    test('TEMP_DELTA caption and labels', () {
      final v = tempMapOf(
        alert(AlertKind.tempDelta, side: FootSide.right, zone: 'heel'),
      )!;
      expect(v.site, 5);
      expect(v.caption, 'กลางส้นเท้าขวาอุ่นกว่ากลางส้นเท้าซ้าย');
      expect(v.labels[FootSide.right], 'เท้าขวา กลางส้นเท้าอุ่นกว่าเท้าซ้าย');
      expect(v.labels[FootSide.left], 'เท้าซ้าย จุดวัดความอุ่นทั้ง 8 จุด');
    });

    test('TEMP_DELTA stored before the 8 sites has no map', () {
      expect(
        tempMapOf(
          alert(
            AlertKind.tempDelta,
            side: FootSide.right,
            legacySite: LegacyTempSite.heel,
          ),
        ),
        isNull,
      );
    });

    test('pressure with a stored map: its levels, the zone ringed', () {
      final v = pressureMapOf(
        alert(
          AlertKind.pressurePeak,
          zone: 'meta1',
          value: 236,
          details: {
            'map': {
              'left': {
                'kpa': [90, 236, 60, 30, 20, 40, 20, 30],
                'levels': [
                  'moderate',
                  'high',
                  'low',
                  'low',
                  'low',
                  'low',
                  'low',
                  'low',
                ],
              },
              'right': null,
            },
          },
        ),
        testThresholds,
      )!;
      expect(v.recorded, isTrue);
      expect(v.channel, 1);
      expect(v.levels[FootSide.left]![1], PressureLevel.high);
      expect(v.levels[FootSide.right], isNull);
      expect(v.caption, 'จุดที่มีวงล้อม: โคนนิ้วหัวแม่เท้าซ้าย');
      expect(
        v.labels[FootSide.left],
        'เท้าซ้าย โคนนิ้วหัวแม่เท้ารับน้ำหนักมาก',
      );
    });

    test('a map stored before the 8 zones: zones 6–7 not recorded', () {
      final v = pressureMapOf(
        alert(
          AlertKind.pressurePeak,
          zone: 'meta1',
          value: 236,
          details: {
            'map': {
              'left': {
                'kpa': [20.0, 236.5, 85.0, 20.0, 20.0, 60.0],
                'levels': ['low', 'high', 'medium', 'low', 'low', 'low'],
              },
              'right': null,
            },
          },
        ),
        testThresholds,
      )!;
      expect(v.recorded, isTrue);
      expect(v.levels[FootSide.left], hasLength(8));
      expect(v.levels[FootSide.left]![1], PressureLevel.high);
      expect(v.levels[FootSide.left]!.sublist(6), [null, null]);
    });

    test('older PEAK without a map: only the ringed zone has a level', () {
      final v = pressureMapOf(
        alert(AlertKind.pressurePeak, zone: 'heel', value: 236),
        testThresholds,
      )!;
      expect(v.recorded, isFalse);
      expect(v.levels[FootSide.left], [
        null,
        null,
        null,
        null,
        null,
        PressureLevel.high,
        null,
        null,
      ]);
      expect(v.levels[FootSide.right], List.filled(8, null));
      expect(v.labels[FootSide.right], 'เท้าขวา');
    });

    test('older PTI / LOAD_CONCENTRATION without a map claim no level', () {
      for (final kind in [AlertKind.pressurePti, AlertKind.loadConcentration]) {
        final v = pressureMapOf(
          alert(kind, zone: 'heel', value: 92),
          testThresholds,
        )!;
        expect(v.levels[FootSide.left], List.filled(8, null));
        expect(v.channel, 5);
      }
    });

    test('no map for temperature or device codes', () {
      expect(
        pressureMapOf(alert(AlertKind.deviceLost), testThresholds),
        isNull,
      );
      expect(tempMapOf(alert(AlertKind.pressurePeak, zone: 'heel')), isNull);
    });
  });

  test('look, action and target per kind', () {
    expect(lookOf(AlertKind.tempDelta).tag, 'ควรพักเท้า');
    expect(lookOf(AlertKind.pressurePti).tag, 'ควรระวัง');
    expect(lookOf(AlertKind.deviceLost).levelWord, 'เรื่องอุปกรณ์');
    expect(lookOf(AlertKind.batteryLow).tag, 'อุปกรณ์');
    expect(actionOf(AlertKind.tempDelta)!.myFeetTab, MyFeetTab.temperature);
    expect(
      actionOf(AlertKind.loadConcentration)!.myFeetTab,
      MyFeetTab.pressure,
    );
    expect(actionOf(AlertKind.deviceLost)!.myFeetTab, isNull);
    expect(targetOf(AlertKind.batteryLow), AlertTarget.connection);
    expect(targetOf(AlertKind.footCheckFinding), AlertTarget.footCheckFound);
    expect(targetOf(AlertKind.pressurePeak), AlertTarget.detail);
  });

  test('group titles and detail time across midnight', () {
    final now = DateTime(2026, 10, 18, 0, 5);
    expect(groupTitle('2026-10-18', now), 'วันนี้');
    expect(groupTitle('2026-10-17', now), 'เมื่อวาน · เสาร์ 17 ต.ค.');
    expect(groupTitle('2026-10-12', now), 'จันทร์ 12 ต.ค.');
    final late = alert(AlertKind.tempDelta)
        .copyAt(DateTime(2026, 10, 17, 23, 58));
    expect(detailTime(late, now), 'เมื่อวาน 23:58');
  });
}

extension on StoredAlert {
  StoredAlert copyAt(DateTime t) => StoredAlert(
    id: id,
    kind: kind,
    level: level,
    patientLevel: patientLevel,
    atMs: t.millisecondsSinceEpoch,
    localDate: localDate,
  );
}

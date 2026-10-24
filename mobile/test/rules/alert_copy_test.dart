import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_copy.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/ui/screens/home/home_copy.dart';

void main() {
  final thai = RegExp(r'[฀-๿]');
  const banned = ['kPa', 'kpa', 'ΔT', 'PAI'];

  /// Every combination an alert can be raised with.
  Iterable<(AlertCode, FootSide, int?, TempSite?)> cases() sync* {
    for (final code in AlertCode.values) {
      for (final side in FootSide.values) {
        switch (code) {
          case AlertCode.tempDelta:
            for (final site in TempSite.values) {
              yield (code, side, null, site);
            }
          case AlertCode.pressureWatch ||
              AlertCode.pressurePeak ||
              AlertCode.pressurePti ||
              AlertCode.loadConcentration:
            for (var c = 0; c < footLayout.zones.length; c++) {
              yield (code, side, c, null);
            }
          case AlertCode.asymmetryPeak ||
              AlertCode.deviceLost ||
              AlertCode.batteryLow:
            yield (code, side, null, null);
        }
      }
    }
  }

  test('every code has plain-Thai title, detail, steps, why and advice '
      '(rule 13)', () {
    for (final (code, side, channel, site) in cases()) {
      final c = alertCopyFor(
        code,
        side: side,
        channel: channel,
        site: site,
        value: 2.6,
        threshold: 5,
      );
      final all = [c.title, c.detail, ...c.steps, c.why, c.todo];
      expect(c.steps, isNotEmpty, reason: '$code');
      for (final s in all) {
        expect(s.trim(), isNotEmpty, reason: '$code');
        expect(thai.hasMatch(s), isTrue, reason: '$code: "$s"');
        for (final b in banned) {
          expect(s.contains(b), isFalse, reason: '$code: "$s"');
        }
      }
      expect(c.title, contains(sideTh(side)), reason: '$code names the foot');
      final setsStatus = code.level >= carefulLevel;
      expect(c.homeDetail != null, setsStatus, reason: '$code');
      expect(c.homeAdvice != null, setsStatus, reason: '$code');
    }
  });

  test('board copy where the spec has it (DESIGN-SPEC §6, §7)', () {
    final t = alertCopyFor(
      AlertCode.tempDelta,
      side: FootSide.right,
      site: TempSite.heel,
      value: 2.6,
    );
    expect(t.title, 'เท้าขวาอุ่นกว่าเท้าซ้าย');
    expect(
      t.detail,
      'ส้นเท้าขวาอุ่นกว่าส้นเท้าซ้าย 2.6\u00a0องศา ติดต่อกันมาสักพัก',
    );
    expect(
      t.homeDetail,
      'เท้าขวาอุ่นกว่าเท้าซ้าย 2.6\u00a0องศา ติดต่อกันมาสักพัก',
    );
    final p = alertCopyFor(
      AlertCode.pressurePeak,
      side: FootSide.left,
      channel: 1,
    );
    expect(p.title, 'ปลายเท้าซ้ายรับน้ำหนักมากตอนเดิน');
    expect(p.todo, 'ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่');
    expect(
      alertCopyFor(
        AlertCode.pressurePti,
        side: FootSide.left,
        channel: 1,
      ).homeDetail,
      'ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป',
    );
    expect(
      alertCopyFor(
        AlertCode.loadConcentration,
        side: FootSide.right,
        channel: 5,
      ).title,
      'น้ำหนักลงที่ส้นเท้าขวาจุดเดียวมากเกินไป',
    );
    final lost = alertCopyFor(
      AlertCode.deviceLost,
      side: FootSide.left,
      threshold: 5,
    );
    expect(lost.title, 'แผ่นรองเท้าซ้ายหลุดการเชื่อมต่อ');
    expect(
      lost.detail,
      'ขาดการเชื่อมต่อนานกว่า 5\u00a0นาที ระหว่างนี้แอปยังบอกไม่ได้ว่าเท้าซ้าย'
      'ปลอดภัยหรือไม่',
    );
    expect(
      alertCopyFor(AlertCode.batteryLow, side: FootSide.right).title,
      'แบตเตอรี่แผ่นรองเท้าขวาเหลือน้อย',
    );
  });

  test('No data names the missing foot (BACKLOG 38)', () {
    expect(
      statusCopy(const PatientStatus.missing(FootSide.right)).detail,
      'ยังไม่ได้เชื่อมต่อแผ่นรองเท้าขวา จึงยังบอกไม่ได้ว่าเท้าขวาปลอดภัยหรือไม่',
    );
    expect(
      statusCopy(PatientStatus.noData).detail,
      'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่',
    );
  });
}

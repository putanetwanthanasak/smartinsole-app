import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../rules/alert_code.dart';
import '../../../rules/patient_status.dart';
import '../../../rules/pressure_level.dart';
import 'home_model.dart';

// Home copy (DESIGN-SPEC §6). The detail and advice strings are DRAFT
// health copy until the medical expert reviews them (DESIGN-SPEC
// Appendix A, decision 5). Never use the terms or units kPa, ΔT or PAI on
// Home; the temperature difference appears only as "{x.x}°".

String sideTh(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

/// Non-breaking space: keeps a number with its unit ("2.6 องศา").
const nbsp = ' ';

String formatDelta(double c) => c.toStringAsFixed(1);

class StatusCopy {
  const StatusCopy({required this.title, required this.detail, this.advice});

  final String title;
  final String detail;

  /// "สิ่งที่ควรทำตอนนี้" box; Be careful and Rest your feet only.
  final String? advice;
}

StatusCopy statusCopy(PatientStatus status) {
  switch (status.level) {
    case PatientLevel.noData:
      return const StatusCopy(
        title: 'ยังไม่ได้รับข้อมูล',
        detail: 'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่',
      );
    case PatientLevel.safe:
      return const StatusCopy(
        title: 'ตอนนี้เท้าปลอดภัย',
        detail: 'น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ',
      );
    case PatientLevel.careful:
    case PatientLevel.rest:
      final title = status.level == PatientLevel.rest
          ? 'ควรพักเท้าตอนนี้'
          : 'ควรระวัง';
      final cause = status.cause!;
      final (detail, advice) = _causeCopy(cause);
      return StatusCopy(title: title, detail: detail, advice: advice);
  }
}

/// Detail + advice from the rule that set the status (alert code + side +
/// zone). Patterns from the boards (DESIGN-SPEC §6, §7.1).
(String, String) _causeCopy(StatusCause c) {
  final side = sideTh(c.side);
  final where = c.channel == null
      ? 'เท้า'
      : footLayout.zones[c.channel!].region.th;
  switch (c.code) {
    case AlertCode.tempDelta:
      final other = sideTh(
        c.side == FootSide.left ? FootSide.right : FootSide.left,
      );
      return (
        'เท้า$sideอุ่นกว่าเท้า$other ${formatDelta(c.deltaC!)}$nbspองศา '
            'ติดต่อกันมาสักพัก',
        'นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม '
            'ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์',
      );
    case AlertCode.pressurePti:
      return (
        '$where$sideรับน้ำหนักมากต่อเนื่องนานเกินไป',
        'ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่',
      );
    case AlertCode.pressurePeak:
      return (
        '$where$sideรับน้ำหนักมากตอนเดิน',
        'ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่',
      );
    case AlertCode.loadConcentration:
      return (
        'น้ำหนักลงที่$where$sideจุดเดียวมากเกินไป',
        'ลองยืนให้น้ำหนักลงทั้งฝ่าเท้า หรือเปลี่ยนท่ายืน',
      );
    case AlertCode.pressureWatch ||
        AlertCode.asymmetryPeak ||
        AlertCode.deviceLost ||
        AlertCode.batteryLow:
      throw ArgumentError('${c.code} does not set a Be-careful/Rest status');
  }
}

/// Pressure card caption and whether it is the high-zone warning.
(String, bool) mapCaption(FootMapView left, FootMapView right) {
  FootMapView? high;
  for (final m in [left, right]) {
    if (m.topLevel == PressureLevel.high) {
      // Both feet high: name the left one first, as the boards read.
      high ??= m;
    }
  }
  if (high != null) {
    final zone = footLayout.zones[high.topChannel!];
    return ('${zone.region.th}${sideTh(high.side)}รับน้ำหนักมาก', true);
  }
  final withData = [left, right].where((m) => m.hasData).toList();
  if (withData.isEmpty) {
    return ('ยังไม่มีข้อมูล ต้องเชื่อมต่อแผ่นรองเท้าก่อน', false);
  }
  if (withData.length == 1) {
    return ('แรงกดเท้า${sideTh(withData.single.side)}กระจายดี', false);
  }
  return ('แรงกดกระจายดีทั้งสองข้าง', false);
}

/// Screen-reader label of one foot map, e.g. "เท้าซ้าย ปลายเท้ารับน้ำหนักมาก".
String mapLabel(FootMapView m) {
  final foot = 'เท้า${sideTh(m.side)}';
  if (!m.hasData) return '$foot ยังไม่มีข้อมูล';
  final level = m.topLevel;
  if (level == null) return '$foot แรงกดกระจายดี';
  final zone = footLayout.zones[m.topChannel!];
  return '$foot ${zone.region.th}รับน้ำหนัก${level.th}';
}

/// Temperature card note.
String tempNote(HomeView v) {
  final warm = v.warmerSide;
  if (v.deltaOver && warm != null) return 'เท้า${sideTh(warm)}อุ่นกว่าปกติ';
  return 'สองข้างอุ่นใกล้เคียงกัน';
}

/// Balance card note.
String balanceNote(HomeView v) {
  final heavy = v.heavierSide;
  if (v.uneven && heavy != null) {
    return 'ลงน้ำหนักเท้า${sideTh(heavy)}มากกว่า';
  }
  return 'ซ้ายและขวาพอ ๆ กัน';
}

const needBothFeet = 'ต้องเชื่อมต่อทั้งสองข้าง';

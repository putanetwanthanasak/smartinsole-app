import '../../../config/foot_layout.dart';
import '../../../rules/alert_copy.dart';
import '../../../rules/patient_status.dart';
import '../../../rules/pressure_level.dart';
import 'home_model.dart';

export '../../../rules/alert_copy.dart' show formatDelta, nbsp, sideTh;

// Home copy (DESIGN-SPEC §6). The detail and advice strings are DRAFT
// health copy until the medical expert reviews them (DESIGN-SPEC
// Appendix A, decision 5); a rule's detail and advice come from
// `alertCopyFor`. Never use the terms or units kPa, ΔT or PAI on Home; the
// temperature difference appears only as "{x.x}°".

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
      final missing = status.missingSide;
      return StatusCopy(
        title: 'ยังไม่ได้รับข้อมูล',
        // One foot missing names it (BACKLOG 38; S7 draft).
        detail: missing == null
            ? 'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่'
            : 'ยังไม่ได้เชื่อมต่อแผ่นรองเท้า${sideTh(missing)} '
                  'จึงยังบอกไม่ได้ว่าเท้า${sideTh(missing)}ปลอดภัยหรือไม่',
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
      final c = status.cause!;
      final copy = alertCopyFor(
        c.code,
        side: c.side,
        channel: c.channel,
        site: c.site,
        value: c.deltaC,
      );
      final detail = copy.homeDetail;
      final advice = copy.homeAdvice;
      if (detail == null || advice == null) {
        throw ArgumentError('${c.code} does not set a Be-careful/Rest status');
      }
      return StatusCopy(title: title, detail: detail, advice: advice);
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

/// Balance card note. While `ASYMMETRY_PEAK` holds it names the rule's
/// foot (and Home draws it in the Be-careful colour, BACKLOG 37).
String balanceNote(HomeView v) {
  final asym = v.asymmetrySide;
  if (asym != null) return 'ลงน้ำหนักเท้า${sideTh(asym)}มากกว่า';
  final heavy = v.heavierSide;
  if (v.uneven && heavy != null) {
    return 'ลงน้ำหนักเท้า${sideTh(heavy)}มากกว่า';
  }
  return 'ซ้ายและขวาพอ ๆ กัน';
}

const needBothFeet = 'ต้องเชื่อมต่อทั้งสองข้าง';

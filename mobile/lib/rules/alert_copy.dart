import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../storage/models.dart' show LegacyTempSite;
import '../text/thai_break.dart';
import 'alert_code.dart';

// Plain-Thai copy for every alert code (rule 13), built from code + side +
// zone or site. **DRAFT health copy** until the medical expert reviews it
// (DESIGN-SPEC Appendix A, decision 5). Board copy is used where the spec
// has it (§6, §7.1, §7.3); every string marked "S7 draft" there was
// written in S7 in the same style. Never put the terms or units kPa, ΔT or
// PAI in these strings; numbers appear as "{x.x} องศา", "{n}%" and
// "{n} นาที".

String sideTh(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

/// "A", "A และ B", "A B และ C" (draft, for screen-reader labels).
String joinTh(List<String> names) => names.length <= 1
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(' ')} และ${names.last}';

FootSide otherSide(FootSide s) =>
    s == FootSide.left ? FootSide.right : FootSide.left;

/// Non-breaking space: keeps a number with its unit ("2.6 องศา").
const nbsp = ' ';

String formatDelta(double c) => c.toStringAsFixed(1);

/// Everything the app says about one alert.
class AlertCopy {
  const AlertCopy({
    required this.title,
    required this.detail,
    required this.steps,
    required this.why,
    required this.todo,
    this.homeDetail,
    this.homeAdvice,
  });

  /// Alerts list card and alert detail title.
  final String title;

  /// Alert detail, under the title.
  final String detail;

  /// "สิ่งที่ควรทำ", numbered.
  final List<String> steps;

  /// "ทำไมแอปถึงเตือน".
  final String why;

  /// The list card's "ควรทำ: " line.
  final String todo;

  /// Home's status card detail and advice; only codes that set the status
  /// (level 3 and above) have them.
  final String? homeDetail;
  final String? homeAdvice;
}

/// The copy for [code] about [side], at zone [channel] (the FSR channel
/// for pressure codes, the temperature site for `TEMP_DELTA`; site i =
/// zone i). A `TEMP_DELTA` stored before schema v2 names its v1 site in
/// [legacySite] instead. [value] is the measured value in the code's unit,
/// [threshold] the boundary it crossed.
AlertCopy alertCopyFor(
  AlertCode code, {
  required FootSide side,
  int? channel,
  LegacyTempSite? legacySite,
  double? value,
  double? threshold,
}) {
  final s = sideTh(side);
  final other = sideTh(otherSide(side));
  final zone = channel == null ? null : footLayout.zones[channel];
  // Site and region names never split across lines, e.g. not
  // "ส้นเท้า / ด้านนอก" (S10, BACKLOG 60/69; display only,
  // lib/text/thai_break.dart). The words are unchanged (Appendix A). The
  // side stays a separate word: a joined unit wider than the line (a long
  // name at the largest text on a narrow phone) would make Flutter break
  // the rest of the paragraph by character.
  final regionS = '${zone?.region.displayTh ?? 'เท้า'}$s';
  // Titles (28–32 px) keep plain names: there a joined region name is
  // wider than the line at the largest text (measured in S10).
  final regionTitle = '${zone?.region.th ?? 'เท้า'}$s';
  final zoneS = '${zone?.displayTh ?? 'เท้า'}$s';
  final footS = keepTogether('เท้า$s');
  final footOther = keepTogether('เท้า$other');
  // A short last word kept with the one before it (BACKLOG 46).
  final walking = keepTogether('ตอนเดิน');
  final orNot = keepTogether('หรือไม่');
  // One word to a reader, two to the dictionary (S10 emulator check).
  final continuous = keepTogether('ต่อเนื่อง');
  switch (code) {
    case AlertCode.tempDelta:
      final siteName =
          zone?.displayTh ?? keepTogether(legacyTempSiteTh(legacySite));
      final x = value == null ? '' : ' ${formatDelta(value)}$nbspองศา';
      return AlertCopy(
        title: '$footSอุ่นกว่า$footOther',
        detail: '$siteName$sอุ่นกว่า$siteName$other$x ติดต่อกันมาสักพัก',
        steps: const [
          'นั่งพักเท้า',
          'ตรวจดูว่ามีรอยแดงหรือแผลไหม',
          'ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์',
        ],
        why:
            'เมื่อเท้าข้างหนึ่งอุ่นกว่าอีกข้างที่ตำแหน่งเดียวกันต่อเนื่อง '
            'อาจเป็นสัญญาณเริ่มต้นของการอักเสบใต้ผิวหนัง ซึ่งมักเกิดก่อนจะเห็นแผล',
        todo: 'นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม',
        homeDetail: '$footSอุ่นกว่า$footOther$x ติดต่อกันมาสักพัก',
        homeAdvice:
            'นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม '
            'ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์',
      );
    case AlertCode.pressurePeak:
      return AlertCopy(
        title: '$regionTitleรับน้ำหนักมาก$walking',
        // S7 draft: the board's "หลายก้าวติดกัน" is not what the rule
        // checks (one walking sample above the boundary raises it).
        detail: '$zoneSรับแรงกดสูงมาก$walking',
        steps: const [
          'ลองเดินช้าลง และก้าวให้สั้นลง',
          'นั่งพักสักครู่ แล้วขยับเท้าเปลี่ยนท่า',
          'ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า',
        ],
        why:
            'แรงกดที่สูงมากซ้ำ ๆ ที่จุดเดิมขณะเดิน อาจทำให้ผิวบริเวณนั้นช้ำ'
            'และเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง',
        todo: 'ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่',
        homeDetail: '$regionSรับน้ำหนักมาก$walking',
        homeAdvice: 'ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่',
      );
    case AlertCode.pressurePti:
      return AlertCopy(
        title: '$regionTitleรับน้ำหนักมาก$continuousนานเกินไป',
        // S7 draft (detail, steps, why).
        detail: '$zoneSรับแรงกดนานในทุกก้าว $continuousมาตลอดช่วงที่ผ่านมา',
        steps: const [
          'นั่งพักเท้าสักครู่',
          'ขยับเท้า เปลี่ยนท่ายืนหรือท่าเดิน',
          'ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า',
        ],
        why:
            'เมื่อจุดเดิมของฝ่าเท้ารับแรงกดนาน ๆ ซ้ำทุกก้าว ผิวบริเวณนั้น'
            'อาจได้เลือดไปเลี้ยงน้อยลงและเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง',
        todo: 'ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่',
        homeDetail: '$regionSรับน้ำหนักมาก$continuousนานเกินไป',
        homeAdvice: 'ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่',
      );
    case AlertCode.loadConcentration:
      return AlertCopy(
        title: 'น้ำหนักลงที่$regionTitleจุดเดียวมากเกินไป',
        // S7 draft (detail, steps, why, and the advice: the rule now
        // counts walking steps, so the board's standing advice became a
        // walking one).
        detail:
            'ทุกก้าวที่ผ่านมา น้ำหนักลงที่$zoneSมากกว่าจุดอื่นของฝ่าเท้ามาก',
        steps: const [
          'ลองเดินช้าลง ให้น้ำหนักลงทั้งฝ่าเท้า',
          'นั่งพักสักครู่ แล้วขยับเท้าเปลี่ยนท่า',
          'ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า',
        ],
        why:
            'เมื่อน้ำหนักลงที่จุดเดียวของฝ่าเท้ามากเกินไปทุกก้าว '
            'ผิวบริเวณนั้นต้องรับแรงมากกว่าปกติ และอาจเกิดแผลได้ '
            'โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง',
        todo: 'ลองเดินช้าลงให้น้ำหนักลงทั้งฝ่าเท้า หรือนั่งพักสักครู่',
        homeDetail: 'น้ำหนักลงที่$regionSจุดเดียวมากเกินไป',
        homeAdvice: 'ลองเดินช้าลงให้น้ำหนักลงทั้งฝ่าเท้า หรือนั่งพักสักครู่',
      );
    case AlertCode.pressureWatch:
      // Level 2: stored, never listed (DESIGN-SPEC §7.1). S7 draft.
      return AlertCopy(
        title: '$regionTitleรับน้ำหนักค่อนข้างมาก',
        detail: '$zoneSรับแรงกดสูงกว่าปกติ',
        steps: const ['ลองขยับเท้า หรือเปลี่ยนท่า'],
        why: 'แอปเฝ้าดูจุดที่รับแรงกดสูง เพื่อเตือนก่อนที่แรงกดจะสูงจนเสี่ยงเกิดแผล',
        todo: 'ลองขยับเท้า หรือเปลี่ยนท่า',
      );
    case AlertCode.asymmetryPeak:
      // Level 2: stored, never listed; Home shows it as the orange
      // balance note. S7 draft.
      return AlertCopy(
        title: 'ลงน้ำหนัก$footSมากกว่า',
        detail: 'ตอนเดิน $footSรับแรงกดสูงกว่า$footOtherติดต่อกันหลายก้าว',
        steps: const ['ลองเดินช้าลง และลงน้ำหนักให้เท่ากันทั้งสองข้าง'],
        why:
            'เมื่อเท้าข้างหนึ่งรับแรงมากกว่าอีกข้างต่อเนื่อง '
            'เท้าข้างนั้นมีโอกาสเกิดแผลมากขึ้น',
        todo: 'ลองเดินช้าลง และลงน้ำหนักให้เท่ากันทั้งสองข้าง',
      );
    case AlertCode.deviceLost:
      final minutes = threshold == null ? '' : ' ${threshold.round()}';
      return AlertCopy(
        title: 'แผ่นรองเท้า$sหลุดการเชื่อมต่อ',
        detail:
            'ขาดการเชื่อมต่อนานกว่า$minutes$nbspนาที '
            'ระหว่างนี้แอปยังบอกไม่ได้ว่า$footSปลอดภัย$orNot',
        steps: const [
          'ตรวจว่าสวิตช์ที่กล่องอุปกรณ์เปิดอยู่',
          'วางโทรศัพท์ไว้ใกล้ ๆ',
          'กด "เชื่อมต่ออีกครั้ง" ด้านล่าง',
        ],
        why: _needBothFeet,
        todo: 'ตรวจว่าแผ่นรองเท้าเปิดอยู่ แล้วเชื่อมต่อใหม่',
      );
    case AlertCode.batteryLow:
      final pct = value == null ? '' : ' ${value.round()}%';
      return AlertCopy(
        title: 'แบตเตอรี่แผ่นรองเท้า$sเหลือน้อย',
        // S7 draft (detail, steps, why).
        detail:
            'แบตเตอรี่เหลือ$pct ถ้าแบตเตอรี่หมด '
            'แอปจะบอกไม่ได้ว่า$footSปลอดภัย$orNot',
        steps: const [
          'ชาร์จแบตเตอรี่ก่อนใช้ครั้งต่อไป',
          'ถ้าต้องใช้ต่อ วางโทรศัพท์ไว้ใกล้ ๆ และดูว่ายังเชื่อมต่ออยู่',
        ],
        why: _needBothFeet,
        todo: 'ชาร์จแบตเตอรี่ก่อนใช้ครั้งต่อไป',
      );
  }
}

const _needBothFeet =
    'แอปต้องได้รับข้อมูลจากแผ่นรองเท้าทั้งสองข้าง '
    'จึงจะเทียบน้ำหนักและความอุ่นของเท้าได้';

/// The v1 temperature sites' names, for `TEMP_DELTA` alerts stored before
/// schema v2 (the 2-site layout's names); "เท้า" when there is none.
String legacyTempSiteTh(LegacyTempSite? site) => switch (site) {
  LegacyTempSite.forefoot => 'หน้าเท้า',
  LegacyTempSite.heel => 'ส้นเท้า',
  null => 'เท้า',
};

import '../../../config/thresholds.dart';
import '../../../gait/gait_class.dart';
import '../../../gait/model_spec.dart';
import '../../../rules/gait_note.dart' show gaitClassTh;
import '../../clock.dart';
import '../../widgets/details_expander.dart';
import '../home/home_copy.dart' show needBothFeet;
import 'gait_model.dart';

// Gait tab copy (DESIGN-SPEC §8.3). Board texts are used as given;
// strings marked "S8A draft" are not on the boards and are listed in
// Appendix A. Plain Thai first: the numbers live only in the details rows.

String activityTh(GaitActivity a) => switch (a) {
  GaitActivity.walking => 'กำลังเดิน',
  GaitActivity.still => 'ยืนหรือนั่งอยู่',
  GaitActivity.noData => '—',
};

/// The class name (the gait note's names, contract §8.3.1).
String gaitClassName(GaitClass c) => gaitClassTh[c.id]!;

/// The short line under the class name. `normal` and `toe_walking` are
/// from the boards; the other three are S8A drafts (Appendix A).
String gaitClassDescription(GaitClass c) => switch (c) {
  GaitClass.normal => 'เดินตามธรรมชาติ',
  GaitClass.toeWalking => 'ส้นเท้าแตะพื้นน้อยหรือไม่แตะ',
  GaitClass.antalgic => 'ลงน้ำหนักข้างหนึ่งสั้นกว่าอีกข้าง',
  GaitClass.heelWalking => 'น้ำหนักลงที่ส้นเท้า ปลายเท้าแตะพื้นน้อย',
  GaitClass.rotatedFoot => 'ปลายเท้าหันเข้าด้านในหรือออกด้านนอกขณะเดิน',
};

/// Under a rule-based result. The low-confidence line is an S8A draft.
String rulesLine(RulesBecause? because) => switch (because) {
  RulesBecause.lowConfidence =>
    'ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่มั่นใจพอ',
  _ => 'ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม',
};

String confidenceWord(GaitEstimateView e) => e.high ? 'สูง' : 'ปานกลาง';

/// Segments filled: 3 at `model.highConfidence` and up, otherwise 2
/// (results below `minConfidence` are never shown).
int confidenceFilled(GaitEstimateView e) => e.high ? 3 : 2;

const noResultTitle = 'ยังไม่มีผลตอนนี้';
const noResultLine = 'ระบบจะประเมินท่าเดินเมื่อคุณเดินต่อเนื่องสักครู่';

/// S8A draft: the estimate card while a foot is missing (rule 4).
const noDataTitle = 'ยังไม่มีข้อมูล';
const noDataLine = 'ต้องเชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน';

const footerLine =
    'ท่าเดินใช้ประกอบคำแนะนำเท่านั้น ไม่ได้ใช้ตัดสินว่าเท้าปลอดภัยหรือไม่';

/// "ผลล่าสุด 10:58 · เดินปกติ".
String lastLine(GaitLastView l) =>
    'ผลล่าสุด ${hhmm(l.at)} · ${gaitClassName(l.gaitClass)}';

String balanceTitle({required bool walking}) =>
    walking ? 'การลงน้ำหนักซ้าย–ขวา' : 'การลงน้ำหนักซ้าย–ขวา ขณะยืน';

/// "ประเมินโดย".
String sourceTh(GaitEstimateView e) => e.fromModel
    ? 'โมเดล AI (Model A)'
    : e.because == RulesBecause.lowConfidence
    ? 'กฎพื้นฐาน (โมเดล AI ยังไม่มั่นใจพอ)'
    : 'กฎพื้นฐาน (โมเดล AI ยังไม่พร้อม)';

/// Whole number, or one decimal when it has one ("15", "2.5").
String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

String _pct(double fraction) => _n(fraction * 100);

/// The rows behind "ดูตัวเลขละเอียด" (§8.3). While walking: the step PAI,
/// the PTI asymmetry (display only, S8A decision 4), and with an estimate
/// its confidence (model only), source and window. Otherwise: the last
/// estimate and the standing PAI. Two-foot values need both feet.
List<DetailRow> gaitDetailRows(GaitView v, Thresholds t, ModelInputSpec spec) {
  final e = v.estimate;
  final walking = v.activity == GaitActivity.walking || e != null;
  if (!walking) {
    final last = v.last;
    return [
      if (last != null)
        DetailRow(
          'ผลประเมินล่าสุด',
          '${hhmm(last.at)} · ${gaitClassName(last.gaitClass)}'
              '${last.fromRules ? ' (กฎพื้นฐาน)' : ''}',
        ),
      DetailRow(
        'ความไม่สมดุลของแรงกดขณะยืน',
        v.standingPaiPct == null ? _missing(v) : '${v.standingPaiPct}%',
      ),
    ];
  }
  final pai = v.walkingPaiPct;
  final pti = v.ptiAsymmetryPct;
  return [
    DetailRow(
      'ความไม่สมดุลของแรงกด (PAI)',
      pai == null
          ? _missing(v)
          : '$pai% (เฝ้าระวังเมื่อเกิน ${_n(t.peakAsymmetryPct)}%)',
    ),
    DetailRow(
      'ความไม่สมดุลของแรงกดสะสม',
      // S8A draft (decision 4): display only, no alert uses it yet.
      pti == null
          ? _missing(v)
          : '$pti% (ค่าอ้างอิง ${_n(t.ptiAsymmetryPct)}% · ยังไม่ใช้แจ้งเตือน)',
    ),
    if (e != null && e.fromModel)
      DetailRow(
        'ความมั่นใจของผลประเมิน',
        '${e.confidencePct}% (ใช้ผลเมื่อ ${_pct(t.minConfidence)}% ขึ้นไป)',
      ),
    if (e != null) DetailRow('ประเมินโดย', sourceTh(e)),
    if (e != null)
      DetailRow(
        'ข้อมูลที่ใช้',
        'ช่วงละ ${_n(spec.windowMs / 1000)} วินาที '
            'ประเมินทุก ${_n(spec.strideMs / 1000)} วินาที',
      ),
  ];
}

/// "—" for a figure with no value: say why when a foot is missing.
String _missing(GaitView v) => v.bothUsable ? '—' : '— ($needBothFeet)';

const probabilitiesTitle = 'ความน่าจะเป็นของแต่ละท่า';
const copTitle = 'เส้นทางของแรงกดในก้าวล่าสุด (CoP)';

import 'package:intl/intl.dart';

import '../../../footcheck/compare_source.dart';
import '../../../footcheck/history.dart';
import '../../../storage/models.dart';

/// Daily foot check copy (DESIGN-SPEC §11). Health advice is a draft until
/// the medical expert reviews it (Appendix A). Lines marked "draft (S8C)"
/// are not on the boards (§14).
abstract final class FootCheckCopy {
  static const title = 'ตรวจเท้าประจำวัน';

  // §11.1 Start.
  static const time = 'ใช้เวลาประมาณ 1 นาที';
  static const reason =
      'แผ่นรองเท้าวัดได้เฉพาะใต้ฝ่าเท้า การดูเท้าทุกวันช่วยให้เห็นแผลที่ปลายนิ้ว'
      'หรือหลังเท้า ซึ่งอาจเกิดขึ้นโดยไม่รู้สึกตัว';
  static const whatTitle = 'ทำอะไรบ้าง';
  static const whatSteps = [
    'ถ่ายรูปเท้า 4 ภาพ ฝ่าเท้าและหลังเท้าทั้งสองข้าง',
    'ดูรูปวันนี้เทียบกับเมื่อวาน',
    'ตอบคำถามสั้น ๆ 3 ข้อ',
  ];
  static const tip =
      'มองฝ่าเท้าไม่ถนัด วางโทรศัพท์บนพื้นแล้วใช้ปุ่มตั้งเวลา หรือให้ญาติช่วยถ่ายก็ได้';
  static const privacy = 'รูปเก็บไว้ในโทรศัพท์เครื่องนี้เท่านั้น';
  static const startPhotos = 'เริ่มถ่ายรูป';
  static const answerOnly = 'ไม่ถ่ายรูป ตอบคำถามอย่างเดียว';

  // §11.2 Capture.
  static const cancel = 'ยกเลิก';
  static String counter(int n) => 'ภาพที่ $n จาก 4';
  static const hint = 'ให้เท้าอยู่ในกรอบ และมีแสงสว่างพอ';
  static const chip = 'วางโทรศัพท์บนพื้น แล้วใช้ปุ่มตั้งเวลา';
  static const timer = 'ตั้งเวลา 3 วิ';
  static const shutter = 'ถ่ายรูป';
  static const skip = 'ข้ามภาพนี้';

  /// Added in S8C (user decision 5): top right of Capture.
  static const switchCamera = 'สลับกล้อง';
  static const guidePrefix = 'กรอบวาง';
  static const slotDone = 'ถ่ายแล้ว';
  static const slotCurrent = 'กำลังถ่าย';
  static const slotTodo = 'ยังไม่ได้ถ่าย';

  // Cancel confirmation (user addition 7, draft).
  static const cancelSheetTitle = 'ยกเลิกการตรวจครั้งนี้?';
  static const cancelSheetText = 'รูปที่ถ่ายไว้จะถูกลบ';
  static const cancelSheetKeep = 'ถ่ายต่อ';
  static const cancelSheetConfirm = 'ยกเลิกการตรวจ';

  // Camera not available (draft, S8C).
  static const cameraDenied = 'ต้องอนุญาตให้ใช้กล้อง';
  static const cameraDeniedText =
      'แอปใช้กล้องเพื่อถ่ายรูปเท้าเท่านั้น รูปเก็บไว้ในโทรศัพท์เครื่องนี้';
  static const cameraAllow = 'อนุญาตให้ใช้กล้อง';
  static const cameraFailed = 'เปิดกล้องไม่ได้';
  static const cameraFailedText = 'ลองใหม่อีกครั้ง หรือตอบคำถามอย่างเดียวก็ได้';
  static const cameraRetry = 'ลองใหม่';
  static const savingPhoto = 'กำลังบันทึกรูป';

  // §11.3 Compare & answer.
  static const compareTitle = 'เทียบกับเมื่อวาน';
  static const pickerLabel = 'รูปที่ดู';
  static const photo = 'รูป';
  static const yesterday = 'เมื่อวาน';
  static const earlier = 'ครั้งก่อน';
  static const today = 'วันนี้';
  static const noEarlier = 'ยังไม่มีรูปก่อนหน้า';
  static const skipped = 'ไม่ได้ถ่ายภาพนี้';
  static const none = 'ไม่มี';
  static const yesOrUnsure = 'มี / ไม่แน่ใจ';
  static const note =
      'แอปไม่ได้ตรวจรูปให้ ถ้าเห็นอะไรผิดปกติหรือไม่แน่ใจ ให้ตอบว่า '
      '"มี / ไม่แน่ใจ"';
  static const save = 'บันทึก';

  static String question(FootCheckQuestion q) => switch (q) {
    FootCheckQuestion.redness => 'เห็นรอยแดง หรือผิวเปลี่ยนสีไหม',
    FootCheckQuestion.wound => 'เห็นแผล รอยถลอก หรือตุ่มพองไหม',
    FootCheckQuestion.swelling => 'เท้าบวม หรือผิดรูปไปจากเดิมไหม',
  };

  /// The question without its final "ไหม" (§11.4 "คุณตอบว่า" lines).
  static String finding(FootCheckQuestion q) {
    final text = question(q);
    return text.endsWith('ไหม') ? text.substring(0, text.length - 3) : text;
  }

  static String viewName(FootView v) => switch (v) {
    FootView.soleLeft => 'ฝ่าเท้าซ้าย',
    FootView.soleRight => 'ฝ่าเท้าขวา',
    FootView.topLeft => 'หลังเท้าซ้าย',
    FootView.topRight => 'หลังเท้าขวา',
  };

  static String slotName(FootView v) => switch (v) {
    FootView.soleLeft => 'ฝ่าซ้าย',
    FootView.soleRight => 'ฝ่าขวา',
    FootView.topLeft => 'หลังซ้าย',
    FootView.topRight => 'หลังขวา',
  };

  static String dayMonth(DateTime d) => DateFormat('d MMM', 'th').format(d);

  /// Left photo caption: "เมื่อวาน · 25 ต.ค." / "ครั้งก่อน · 23 ต.ค.".
  static String compareCaption(CompareSource s) => switch (s.kind) {
    CompareKind.yesterday =>
      '$yesterday · ${dayMonth(localDateTimeOf(s.photo!.localDate))}',
    CompareKind.earlier =>
      '$earlier · ${dayMonth(localDateTimeOf(s.photo!.localDate))}',
    CompareKind.none => earlier,
  };

  // §11.4 Something found.
  static const foundTitle = 'พบสิ่งที่ควรให้แพทย์ดู';
  static const youAnswered = 'คุณตอบว่า';
  static const whatNow = 'สิ่งที่ควรทำตอนนี้';
  static const foundSteps = [
    'ล้างเท้าด้วยน้ำสะอาด แล้วซับให้แห้ง',
    'ถ้ามีแผล ปิดด้วยผ้าก๊อซสะอาด',
    'เดินให้น้อยลง และอย่าเดินเท้าเปล่า',
    'ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู',
  ];
  static const urgent =
      'ไปโรงพยาบาลทันที ถ้ามีไข้ เท้าบวมแดงลามออกไป มีหนอง หรือมีกลิ่น';
  static const seePhotos = 'ดูรูปที่บันทึกไว้';
  static const backHome = 'เข้าใจแล้ว กลับหน้าหลัก';

  // §11.5 Saved.
  static const savedTitle = 'บันทึกแล้ว เจอกันพรุ่งนี้';
  static String checkedAt(String hhmm) => 'วันนี้ดูเท้าแล้ว เวลา $hhmm';
  static String remindAt(String hhmm) => 'พรุ่งนี้แอปจะเตือนตอน $hhmm';
  static const yesterdayFound =
      'เมื่อวานพบสิ่งที่ควรให้แพทย์ดู ถ้ายังไม่ได้ไป ควรไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน';
  static const weekTitle = '7 วันที่ผ่านมา';
  static const weekLabel = 'ผลการดูเท้า 7 วันที่ผ่านมา';
  static const daySaved = 'บันทึกแล้ว';
  static const dayFound = 'ควรให้แพทย์ดู';
  static const dayMissed = 'ไม่ได้ดู';

  /// Added in S8C (user decision 4).
  static const again = 'ตรวจอีกครั้ง';

  // The tab after today's latest check found something (user decision 4,
  // the approved proposal; draft).
  static const foundTodayTitle = 'วันนี้พบสิ่งที่ควรให้แพทย์ดู';
  static String foundCheckedAt(String hhmm) => 'ดูเท้าแล้ว เวลา $hhmm';
  static const whatToDo = 'ดูสิ่งที่ควรทำ';

  /// Thai weekday abbreviation without the dot ("พฤ").
  static String weekdayShort(DateTime d) =>
      DateFormat('E', 'th').format(d).replaceAll('.', '');

  // Photo history (draft, S8C: not designed, §14).
  static const historyTitle = 'รูปที่บันทึกไว้';
  static const historyNote = 'รูปเก็บไว้ 30 วัน ลบรูปทั้งหมดได้ที่หน้าตั้งค่า';
  static const historyEmpty = 'ยังไม่มีรูปที่บันทึกไว้';
  static const historyEmptyText = 'รูปจากการดูเท้าประจำวันจะอยู่ที่นี่';
  static const notTaken = 'ไม่ได้ถ่าย';
  static String atTime(String hhmm) => 'เวลา $hhmm';
  static const close = 'ปิด';
}

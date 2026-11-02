/// Thai line breaking for volunteer-facing copy (S10, BACKLOG 46, 60, 69).
///
/// Thai has no spaces between words, so Flutter breaks lines by dictionary
/// and can split a site name ("ส้นเท้า / ด้านนอก") or leave one short word
/// alone on the last line ("ไม่"). A WORD JOINER (U+2060) is invisible and
/// forbids a line break on either side of it.
///
/// Joiners go **only between the words** of a phrase, as the dictionary
/// splits it (the [thaiWords] table). A joiner inside a word cuts the Thai
/// text around it into pieces the dictionary cannot read, and Flutter then
/// breaks plain words next to the phrase ("สู / งมาก", seen in S10).
/// `test/text/thai_break_test.dart` checks every entry against Flutter's
/// own word boundaries.
///
/// **Display only.** Use it where copy is composed for the screen or a
/// notification, never on anything stored or exported: the database, the
/// capture files, `alerts.csv` and every export keep plain text (the same
/// test checks they never see a joiner). Use it where a phrase sits inside
/// running text; a name that is a whole `Text` by itself needs none.
///
/// To reapply after the copy is edited (e.g. S10b's expert text fixes):
/// add the phrase to [thaiWords] with "|" between its words, wrap it in
/// [keepTogether] where the copy is composed, and add it to
/// `test/footcheck/thai_line_break_test.dart`. The table test fails if the
/// words are not the dictionary's.
library;

/// U+2060 WORD JOINER.
const wordJoiner = '⁠';

/// Phrases that must stay on one line, with "|" between their words as
/// Flutter's dictionary splits them.
const thaiWords = {
  // Site names (DESIGN-SPEC §8; `foot_layout.dart`).
  'นิ้วหัวแม่เท้า': 'นิ้ว|หัว|แม่|เท้า',
  'โคนนิ้วหัวแม่เท้า': 'โคน|นิ้ว|หัว|แม่|เท้า',
  'กลางหน้าเท้า': 'กลาง|หน้า|เท้า',
  'โคนนิ้วก้อย': 'โคน|นิ้ว|ก้อย',
  'ขอบเท้าด้านนอก': 'ขอบ|เท้า|ด้าน|นอก',
  'กลางส้นเท้า': 'กลาง|ส้น|เท้า',
  'อุ้งเท้า': 'อุ้งเท้า',
  'ส้นเท้าด้านนอก': 'ส้น|เท้า|ด้าน|นอก',
  // Regions (the rest are site names too) and the 2-site names stored
  // before schema v2.
  'ปลายเท้า': 'ปลาย|เท้า',
  'ส้นเท้า': 'ส้น|เท้า',
  'หน้าเท้า': 'หน้า|เท้า',
  'เท้า': 'เท้า',
  // A foot, short last words (BACKLOG 46) and a word the dictionary
  // splits.
  'เท้าซ้าย': 'เท้า|ซ้าย',
  'เท้าขวา': 'เท้า|ขวา',
  'ตอนเดิน': 'ตอน|เดิน',
  'หรือไม่': 'หรือ|ไม่',
  'ต่อเนื่อง': 'ต่อ|เนื่อง',
  'น้ำหนัก': 'น้ำ|หนัก',
  'จุดเดียว': 'จุด|เดียว',
};

/// [phrase] with a [wordJoiner] between its words ([thaiWords]), so no line
/// break can fall inside it. Idempotent. A phrase missing from the table
/// fails an assert in debug builds and comes back plain in release.
String keepTogether(String phrase) {
  final plain = withoutJoiners(phrase);
  final words = thaiWords[plain];
  assert(words != null, 'keepTogether: add "$plain" to thaiWords');
  if (words == null) return plain;
  return words.split('|').join(wordJoiner);
}

/// [text] without word joiners.
String withoutJoiners(String text) => text.replaceAll(wordJoiner, '');

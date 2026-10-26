import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/screens/foot_check/foot_check_copy.dart';
import 'package:smartinsole/ui/theme/typography.dart';

/// Thai word breaking split "ไม่แน่ใจ", "ตั้งเวลา" and "แพทย์ดู" across
/// lines (S8C screenshots). The copy keeps them together with word joiners
/// (U+2060); this lays each text out at every width and text scale a phone
/// gives and checks the phrase is always on one line.
void main() {
  const wj = '⁠';

  /// How many lines [phrase] in [text] spans (null when it is missing):
  /// the line of its first character vs the line of its last.
  int? linesOf(
    String text,
    String phrase,
    TextStyle style,
    double width,
    double scale,
  ) {
    final start = text.indexOf(phrase);
    if (start < 0) return null;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout(maxWidth: width);
    final first = painter.getLineBoundary(TextPosition(offset: start));
    final last = painter.getLineBoundary(
      TextPosition(offset: start + phrase.length - 1),
    );
    painter.dispose();
    return first == last ? 1 : 2;
  }

  /// Widths (logical px) a text block gets on phones 320–430 wide, minus
  /// page padding and card padding; text scales 1.0, 1.3 and ใหญ่มาก × 1.3.
  final widths = [for (var w = 180.0; w <= 400; w += 1) w];
  const scales = [1.0, 1.3, 1.88];

  void expectTogether(String text, String phrase, TextStyle style) {
    expect(text, contains(phrase));
    for (final scale in scales) {
      for (final w in widths) {
        expect(
          linesOf(text, phrase, style, w, scale),
          1,
          reason: '"$phrase" split at width $w, scale $scale',
        );
      }
    }
  }

  test('the quoted "มี / ไม่แน่ใจ" in the Compare note stays on one line', () {
    expectTogether(
      FootCheckCopy.note,
      'มี / $wjไม่$wjแน่ใจ',
      AppText.secondary,
    );
  });

  test('"ตั้งเวลา" stays together in the capture chip and the Start tip', () {
    expectTogether(FootCheckCopy.chip, 'ตั้ง$wjเวลา', AppText.secondary);
    expectTogether(FootCheckCopy.tip, 'ตั้ง$wjเวลา', AppText.body);
  });

  test('"แพทย์ดู" stays together in the found-today title', () {
    expectTogether(
      FootCheckCopy.foundTodayTitle,
      'แพทย์$wjดู',
      AppText.pageTitle,
    );
  });

  test('control: without the joiners Thai word breaking does split them', () {
    // Proves the check above can fail: the plain text breaks inside the
    // phrase at some width.
    bool splits(String text, String phrase, TextStyle style) => [
      for (final scale in scales)
        for (final w in widths) linesOf(text, phrase, style, w, scale)!,
    ].any((n) => n > 1);

    expect(
      splits(
        FootCheckCopy.note.replaceAll(wj, ''),
        'มี / ไม่แน่ใจ',
        AppText.secondary,
      ),
      isTrue,
    );
    expect(
      splits(
        FootCheckCopy.chip.replaceAll(wj, ''),
        'ตั้งเวลา',
        AppText.secondary,
      ),
      isTrue,
    );
  });
}

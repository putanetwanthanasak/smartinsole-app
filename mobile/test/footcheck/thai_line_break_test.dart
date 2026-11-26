import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_copy.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/text/thai_break.dart';
import 'package:smartinsole/ui/screens/alerts/alert_view.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/screens/foot_check/foot_check_copy.dart';
import 'package:smartinsole/ui/theme/typography.dart';

/// Thai word breaking split "ไม่แน่ใจ", "ตั้งเวลา" and "แพทย์ดู" across
/// lines (S8C screenshots); S10 (BACKLOG 46, 60, 69) adds the alert, Home
/// and My feet copy: site names with their side, and short last words. The copy keeps them together with word joiners
/// (U+2060); this lays each text out at every width and text scale a phone
/// gives and checks the phrase is always on one line.
void main() {
  setUpAll(() => initializeDateFormatting('th'));
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

  /// The alert, Home and My feet text lines (S10): page or card width on
  /// phones 360–430 dp wide, so at least about 260 px.
  final alertWidths = [for (var w = 260.0; w <= 400; w += 1) w];

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

  /// Like [expectTogether], for phrases that can be wider than a narrow
  /// line at large text (a whole site name with its side): wherever the
  /// phrase fits on one line by itself, it is never split (S10). Where it
  /// does not fit, it breaks by character like any too-long word.
  void expectTogetherWhenFits(String text, String phrase, TextStyle style) {
    expect(text, contains(phrase));
    for (final scale in scales) {
      final own = TextPainter(
        text: TextSpan(text: phrase, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout();
      final need = own.width;
      own.dispose();
      for (final w in alertWidths) {
        if (w < need) continue;
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

  // S10: every site name with its side, in the TEMP_DELTA detail and the
  // pressure details (the BACKLOG 69 case was "ส้นเท้า / ด้านนอก").
  test('site names stay whole in the alert copy', () {
    for (final side in FootSide.values) {
      for (var ch = 0; ch < footLayout.zones.length; ch++) {
        final z = footLayout.zones[ch];
        final temp = alertCopyFor(
          AlertCode.tempDelta,
          side: side,
          channel: ch,
          value: 2.6,
        );
        expectTogetherWhenFits(temp.detail, z.displayTh, AppText.body);
        final peak = alertCopyFor(
          AlertCode.pressurePeak,
          side: side,
          channel: ch,
        );
        expectTogetherWhenFits(peak.detail, z.displayTh, AppText.body);
        expectTogetherWhenFits(
          peak.homeDetail!,
          z.region.displayTh,
          AppText.body,
        );
      }
    }
  });

  // BACKLOG 69: "จุดที่อุ่นกว่าบนเท้าขวา: กลางส้นเท้า · ส้นเท้าด้านนอก"
  // broke between "ส้นเท้า" and "ด้านนอก" at 100 % on 390 dp.
  test('the alert-detail sites line keeps every site name whole', () {
    final all = [for (final z in footLayout.zones) z.id];
    final line = tempMapOf(
      StoredAlert(
        id: 1,
        kind: AlertKind.tempDelta,
        level: 4,
        patientLevel: PatientLevel.rest,
        atMs: 0,
        localDate: '2026-10-21',
        side: FootSide.right,
        zone: 'heel',
        details: {
          TempSiteEntry.listKey: [
            for (final z in all)
              TempSiteEntry(zone: z, deltaC: 2.5, atMs: 0).toJson(),
          ],
        },
      ),
    )!.sitesLine!;
    for (final z in footLayout.zones) {
      expectTogetherWhenFits(line, z.displayTh, AppText.secondary);
    }
    expect(line, isNot(contains(' ·')), reason: '"·" never starts a line');
  });

  test('short last words stay with the word before (BACKLOG 46)', () {
    final lost = alertCopyFor(
      AlertCode.deviceLost,
      side: FootSide.right,
      threshold: 5,
    );
    expectTogetherWhenFits(lost.detail, keepTogether('หรือไม่'), AppText.body);
    final peak = alertCopyFor(
      AlertCode.pressurePeak,
      side: FootSide.left,
      channel: 1,
    );
    expectTogetherWhenFits(peak.detail, keepTogether('ตอนเดิน'), AppText.body);
  });

  test('"ต่อเนื่อง" stays one word in the PTI copy', () {
    final pti = alertCopyFor(
      AlertCode.pressurePti,
      side: FootSide.left,
      channel: 1,
    );
    for (final t in [pti.detail, pti.homeDetail!]) {
      expectTogetherWhenFits(t, keepTogether('ต่อเนื่อง'), AppText.body);
    }
  });

  test('Home\'s date keeps the day with its month', () {
    final d = DateTime(2026, 10, 18);
    expectTogether(
      DateFormat('EEEE d\u00A0MMMM', 'th').format(d),
      DateFormat('d\u00A0MMMM', 'th').format(d),
      AppText.secondary,
    );
    expect(thaiLongDate(d), contains('18\u00A0'));
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

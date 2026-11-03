import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/rules/alert_copy.dart';
import 'package:smartinsole/text/thai_break.dart';
import 'package:smartinsole/ui/theme/typography.dart';

/// `keepTogether` (S10, BACKLOG 46/60/69) and where joiners may go.
void main() {
  group('keepTogether', () {
    test('a joiner between words only', () {
      expect(
        keepTogether('ส้นเท้าด้านนอก'),
        'ส้น\u2060เท้า\u2060ด้าน\u2060นอก',
      );
      expect(keepTogether('อุ้งเท้า'), 'อุ้งเท้า', reason: 'one word');
      expect(keepTogether(keepTogether('ตอนเดิน')), keepTogether('ตอนเดิน'));
    });

    // The table is the dictionary's own split: a joiner inside a word
    // would make Flutter break plain words next to the phrase.
    test('every table entry splits where the dictionary does', () {
      for (final MapEntry(key: phrase, value: words) in thaiWords.entries) {
        expect(words.replaceAll('|', ''), phrase);
        final p = TextPainter(
          text: TextSpan(text: phrase, style: AppText.body),
          textDirection: TextDirection.ltr,
        )..layout();
        final found = <String>[];
        var i = 0;
        while (i < phrase.length) {
          final b = p.getWordBoundary(TextPosition(offset: i));
          final end = b.end > i ? b.end : i + 1;
          found.add(phrase.substring(i, end));
          i = end;
        }
        p.dispose();
        expect(found.join('|'), words, reason: phrase);
      }
    });

    test('every site and region name is in the table', () {
      for (final z in footLayout.zones) {
        expect(thaiWords, contains(z.nameTh));
        expect(thaiWords, contains(z.region.th));
        expect(withoutJoiners(z.displayTh), z.nameTh);
      }
    });
  });

  test('every site and region named in alert body copy is kept whole', () {
    final names = {
      for (final z in footLayout.zones) ...{z.nameTh, z.region.th},
    };
    for (final code in AlertCode.values) {
      for (final side in FootSide.values) {
        for (var ch = 0; ch < footLayout.zones.length; ch++) {
          final c = alertCopyFor(
            code,
            side: side,
            channel: ch,
            value: 2.5,
            threshold: 5,
          );
          // Titles keep plain names (see the width test below).
          for (final text in [c.detail, c.todo, ?c.homeDetail, ?c.homeAdvice]) {
            final plainText = withoutJoiners(text);
            for (final n in names) {
              if (!plainText.contains(n)) continue;
              expect(
                text,
                contains(keepTogether(n)),
                reason: '${code.name} ${side.name} $ch: "$n" in "$plainText"',
              );
            }
          }
        }
      }
    }
  });

  // The bug class S10 hit: joiners in the wrong place (or a joined
  // phrase wider than the line) make Flutter break inside plain words
  // ("สู / งมาก"). So every line break in the copy must fall on a word
  // boundary of the plain text, at every text line width an alert gets
  // (about 260 px, an alert card on a 360 dp phone, to 400) and every text
  // scale up to 1.3 × "ใหญ่มาก" (1.88), in the style it is drawn in:
  // titles `pageTitle` (alert detail), `bodyStrong` (Alerts list) and
  // `button` (the My feet banner, narrower: from 216 px), the rest `body`.
  // Titles are held to more: a break may not fall inside any short
  // phrase of `thaiWords` either, joined in the code or not. The
  // dictionary splits those ("รับน้ำ / หนักมาก" was a word boundary to
  // it, S10 emulator check), so the word-boundary test alone missed them.
  test('copy only breaks lines between words', () {
    const scales = [1.0, 1.3, 1.88];
    final widths = [for (var w = 260.0; w <= 400; w += 7) w];
    // The banner's text is the screen less 144 dp (page, banner padding,
    // icon): 216 on a 360 dp phone, 267 on the Note 10.
    final bannerWidths = [for (var w = 216.0; w <= 340; w += 7) w];

    /// The table's phrases, longest first. A title never breaks inside
    /// one of up to 3 words; the 4- and 5-word site names may break
    /// between the shorter phrases they hold ("ขอบเท้า / ด้านนอก").
    final phrases = thaiWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    bool isShort(String ph) => thaiWords[ph]!.split('|').length <= 3;

    /// Plain-text offsets strictly inside a short phrase, read word by
    /// word ([edges]) from the left, taking the longest phrase that starts
    /// and ends on a word edge: "ปลายเท้าซ้าย" is "ปลายเท้า" + "ซ้าย" and
    /// "แผ่นรองเท้าซ้าย" is "แผ่น" + "รองเท้า" + "ซ้าย" (a break before the
    /// side is a word break), neither holds "เท้าซ้าย". A long phrase is
    /// read again inside for the shorter ones.
    Set<int> insidePhrases(String plainText, Set<int> edges) {
      final inside = <int>{};
      final starts = edges.toList()..sort();
      void scan(int from, int to, int maxLen) {
        var i = from;
        while (i < to) {
          final ph = phrases.firstWhere(
            (p) =>
                p.length < maxLen &&
                i + p.length <= to &&
                plainText.startsWith(p, i) &&
                edges.contains(i + p.length),
            orElse: () => '',
          );
          if (ph.isEmpty) {
            i = starts.firstWhere((e) => e > i);
            continue;
          }
          if (isShort(ph)) {
            for (var o = i + 1; o < i + ph.length; o++) {
              inside.add(o);
            }
          } else {
            scan(i, i + ph.length, ph.length);
          }
          i += ph.length;
        }
      }

      scan(0, plainText.length, plainText.length + 1);
      return inside;
    }

    /// Plain-text offsets where a word starts or ends.
    Set<int> wordEdges(String plainText, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: plainText, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final edges = <int>{0, plainText.length};
      for (var i = 0; i < plainText.length; i++) {
        final b = p.getWordBoundary(TextPosition(offset: i));
        edges.addAll([b.start, b.end]);
      }
      p.dispose();
      return edges;
    }

    /// Breaks that fall inside a word, as "before / after".
    List<String> badBreaks(
      String text,
      TextStyle style, {
      bool title = false,
      List<double>? lineWidths,
    }) {
      final plainText = withoutJoiners(text);
      final edges = wordEdges(plainText, style);
      final inside = title ? insidePhrases(plainText, edges) : const <int>{};
      int plainOffset(int o) => withoutJoiners(text.substring(0, o)).length;
      final bad = <String>[];
      for (final scale in scales) {
        for (final w in lineWidths ?? widths) {
          final p = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout(maxWidth: w);
          var off = 0;
          while (off < text.length) {
            final end = p.getLineBoundary(TextPosition(offset: off)).end;
            if (end <= off || end >= text.length) break;
            final at = plainOffset(end);
            // A break after a space is a word boundary too.
            final afterSpace = at > 0 && plainText[at - 1] == ' ';
            if ((!edges.contains(at) && !afterSpace) || inside.contains(at)) {
              bad.add(
                '$w×$scale "${plainText.substring(0, at)} / '
                '${plainText.substring(at)}"',
              );
            }
            off = end;
          }
          p.dispose();
        }
      }
      return bad;
    }

    void check(
      String text,
      TextStyle style,
      String what, {
      bool title = false,
      List<double>? lineWidths,
    }) => expect(
      badBreaks(text, style, title: title, lineWidths: lineWidths),
      isEmpty,
      reason: what,
    );

    // Control: the first S10 version (a joiner between every letter of
    // "ตอนเดิน") broke "สูง" in the PEAK detail.
    final perLetter = [for (final r in 'ตอนเดิน'.runes) String.fromCharCode(r)]
        .join(wordJoiner)
        .replaceAll('$wordJoiner\u0E34', '\u0E34');
    expect(
      badBreaks('โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงมาก$perLetter', AppText.body),
      isNotEmpty,
    );
    // Control for titles: the PTI title as the S10 screenshots had it, with
    // no joiners, broke "รับน้ำ / หนักมาก".
    expect(
      badBreaks(
        'ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป',
        AppText.pageTitle,
        title: true,
      ),
      contains(contains('รับน้ำ / หนัก')),
    );

    // The other titles a volunteer sees: Home's status (32 px) and the
    // My feet banners.
    for (final t in [
      'ยังไม่ได้รับข้อมูล',
      'ตอนนี้เท้าปลอดภัย',
      'ควรพักเท้าตอนนี้',
      'ควรระวัง',
    ]) {
      check(t, AppText.statusTitle, 'Home "$t"', title: true);
    }
    for (final t in [
      'ยังไม่ได้รับข้อมูล',
      'ยังไม่ได้รับข้อมูล${keepTogether('เท้าซ้าย')}',
      'แรงกดกระจายดีทั้งสองข้าง',
      'เทียบความอุ่นไม่ได้',
      'สองข้างอุ่นใกล้เคียงกัน',
      // The Temperature banner as my_feet_copy builds it, every site.
      for (final z in footLayout.zones)
        '${z.titleTh}ซ้าย${keepTogether('อุ่นกว่า')}ขวา 2.6$nbspองศา',
    ]) {
      check(
        t,
        AppText.button,
        'My feet "$t"',
        title: true,
        lineWidths: bannerWidths,
      );
    }

    for (final code in AlertCode.values) {
      for (final side in FootSide.values) {
        for (var ch = 0; ch < footLayout.zones.length; ch++) {
          final c = alertCopyFor(
            code,
            side: side,
            channel: ch,
            value: 2.5,
            threshold: 5,
          );
          final at = '${code.name} ${side.name} $ch';
          check(c.title, AppText.pageTitle, '$at title', title: true);
          check(c.title, AppText.bodyStrong, '$at list', title: true);
          check(
            c.title,
            AppText.button,
            '$at banner',
            title: true,
            lineWidths: bannerWidths,
          );
          check(c.detail, AppText.body, '$at detail');
          check(c.todo, AppText.body, '$at todo');
          if (c.homeDetail case final d?) check(d, AppText.body, at);
        }
      }
    }
  });

  // User decision at S10 plan approval: joiners are display only. Nothing
  // that stores or exports data may build text with them: the database
  // (lib/storage), research capture and its files and alerts.csv
  // (lib/capture), and the data path (lib/ble, lib/device, lib/gait). None
  // of these import the copy or the helper, so no joiner can reach a row
  // or a file.
  test('joiners never reach the database, capture files or exports', () {
    const forbidden = [
      'thai_break.dart',
      'alert_copy.dart',
      'displayTh',
      'keepTogether',
      'wordJoiner',
      r'⁠',
      '⁠',
    ];
    final dirs = [
      'lib/storage',
      'lib/capture',
      'lib/ble',
      'lib/device',
      'lib/gait',
    ];
    var checked = 0;
    for (final d in dirs) {
      for (final f in Directory(d).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final word in forbidden) {
          expect(src.contains(word), isFalse, reason: '${f.path}: $word');
        }
        checked++;
      }
    }
    expect(checked, greaterThan(40));
  });
}

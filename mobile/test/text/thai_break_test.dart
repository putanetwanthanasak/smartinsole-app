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
  // titles `pageTitle`, the rest `body`.
  test('copy only breaks lines between words', () {
    const scales = [1.0, 1.3, 1.88];
    final widths = [for (var w = 260.0; w <= 400; w += 7) w];

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
    List<String> badBreaks(String text, TextStyle style) {
      final plainText = withoutJoiners(text);
      final edges = wordEdges(plainText, style);
      int plainOffset(int o) => withoutJoiners(text.substring(0, o)).length;
      final bad = <String>[];
      for (final scale in scales) {
        for (final w in widths) {
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
            if (!edges.contains(at) && !afterSpace) {
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

    void check(String text, TextStyle style, String what) =>
        expect(badBreaks(text, style), isEmpty, reason: what);

    // Control: the first S10 version (a joiner between every letter of
    // "ตอนเดิน") broke "สูง" in the PEAK detail.
    final perLetter = [for (final r in 'ตอนเดิน'.runes) String.fromCharCode(r)]
        .join(wordJoiner)
        .replaceAll('$wordJoiner\u0E34', '\u0E34');
    expect(
      badBreaks('โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงมาก$perLetter', AppText.body),
      isNotEmpty,
    );

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
          check(c.title, AppText.pageTitle, '$at title');
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

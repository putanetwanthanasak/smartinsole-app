import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rule 12: thresholds come from `thresholds.json`, never from code. Every
/// numeric literal in `lib/rules/` (code only: comments and string text
/// are skipped, string interpolations are code) must be one of a few
/// structural numbers, none of which is a threshold value.
///
/// `alert_code.dart` is skipped: it is the contract's level column (1–5)
/// and the FLUTTER-PLAN §7 level boundaries, not thresholds.
final allowed = <num>{0, 0.5, 1, 100, 1000}; // zero, half, one, %, ms per s
const skipped = {'alert_code.dart'};

void main() {
  test('no threshold value is among the allowed literals', () {
    final json = jsonDecode(
      File('../shared/thresholds.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final values = <num>{
      for (final e in json.entries)
        // `sources` holds the contract's citation texts, not numbers.
        if (e.key != 'version' && e.key != 'sources')
          for (final v in (e.value! as Map<String, Object?>).values) v! as num,
    };
    expect(values, isNotEmpty);
    expect(values.intersection(allowed), isEmpty);
  });

  test('lib/rules has no numeric literal outside $allowed', () {
    final files = Directory('lib/rules')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !skipped.contains(f.uri.pathSegments.last))
        .toList();
    expect(files.length, greaterThan(5));
    final found = <String>[];
    for (final f in files) {
      final code = dartCodeOnly(f.readAsStringSync());
      for (final m in _number.allMatches(code)) {
        final v = num.parse(m.group(0)!);
        if (!allowed.contains(v)) {
          found.add('${f.path}: ${m.group(0)}');
        }
      }
    }
    expect(found, isEmpty, reason: 'move these into thresholds.json');
  });

  test('the scanner sees code, not comments or string text', () {
    expect(
      _number
          .allMatches(
            dartCodeOnly(
              "final a = 75; // 80\n"
              "/* 200 */ final b = 'at 2.2 °C \${x + 15}';\n"
              "final c = r'40'; final d = '''60 \$y''';\n"
              "final utf8x = 3e2;",
            ),
          )
          .map((m) => m.group(0))
          .toList(),
      ['75', '15', '3e2'],
    );
  });
}

final _number = RegExp(r'(?<![\w$.])(\d+(\.\d+)?([eE][+-]?\d+)?)(?![\w.])');

/// [src] with comments and string text blanked out; `${…}` inside strings
/// is kept, since it is code.
String dartCodeOnly(String src) => (_Scanner(src)..code()).out.toString();

class _Scanner {
  _Scanner(this.src);

  final String src;
  final out = StringBuffer();
  int i = 0;
  int depth = 0;

  /// Code until the end, or until the `}` that closes brace depth [until].
  void code({int? until}) {
    while (i < src.length) {
      final c = src[i];
      if (src.startsWith('//', i)) {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
      } else if (src.startsWith('/*', i)) {
        final end = src.indexOf('*/', i + 2);
        i = end < 0 ? src.length : end + 2;
        out.write(' ');
      } else if (c == "'" || c == '"') {
        out.write(' ');
        string();
      } else {
        if (c == '{') depth++;
        if (c == '}') {
          depth--;
          if (until != null && depth == until) {
            i++;
            return;
          }
        }
        out.write(c);
        i++;
      }
    }
  }

  void string() {
    final raw = i > 0 && src[i - 1] == 'r';
    final q = src[i];
    final close = src.startsWith(q * 3, i) ? q * 3 : q;
    i += close.length;
    while (i < src.length) {
      if (src.startsWith(close, i)) {
        i += close.length;
        return;
      }
      if (!raw && src[i] == r'\') {
        i += 2;
      } else if (!raw && src.startsWith(r'${', i)) {
        // Interpolated code: scan it until its brace closes.
        i += 2;
        out.write(' ');
        depth++;
        code(until: depth - 1);
      } else {
        i++;
      }
    }
  }
}

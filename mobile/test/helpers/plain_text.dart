import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:smartinsole/text/thai_break.dart';

/// Copy shown to volunteers carries invisible word joiners (U+2060, S10,
/// `lib/text/thai_break.dart`). Tests that compare it with the plain Thai
/// of DESIGN-SPEC import this `expect` instead of flutter_test's
/// (`import 'package:flutter_test/flutter_test.dart' hide expect;`): it
/// drops the joiners from [actual] and from a plain expected value
/// (strings, and strings inside lists, sets, maps and `(String, bool)`
/// records) before matching.
void expect(dynamic actual, dynamic matcher, {String? reason, dynamic skip}) =>
    ft.expect(
      plain(actual),
      matcher is ft.Matcher ? matcher : plain(matcher),
      reason: reason,
      skip: skip,
    );

/// [value] with every word joiner removed from the strings in it.
dynamic plain(dynamic value) => switch (value) {
  final String s => withoutJoiners(s),
  final Map<dynamic, dynamic> m => {
    for (final e in m.entries) plain(e.key): plain(e.value),
  },
  final List<dynamic> l => [for (final x in l) plain(x)],
  final Set<dynamic> s => {for (final x in s) plain(x)},
  (final String a, final bool b) => (withoutJoiners(a), b),
  _ => value,
};

/// `find.text` for copy that may carry word joiners: a [Text] whose text,
/// without joiners, is [wanted] (like `find.text`, not its inner
/// [RichText]).
ft.Finder findPlainText(String wanted) => ft.find.byWidgetPredicate(
  (w) => switch (w) {
    Text(:final data?) => withoutJoiners(data) == wanted,
    Text(:final textSpan?) => withoutJoiners(textSpan.toPlainText()) == wanted,
    _ => false,
  },
);

/// `find.bySemanticsLabel` for a label that may carry word joiners: matches
/// [label] exactly, with any joiners between its characters.
ft.Finder findPlainSemantics(String label) => ft.find.bySemanticsLabel(
  RegExp(
    '^${[for (final r in label.runes) RegExp.escape(String.fromCharCode(r))].join('$wordJoiner*')}\$',
  ),
);

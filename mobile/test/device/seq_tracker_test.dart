import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/seq_tracker.dart';

void main() {
  test('continuous seq has no gaps', () {
    final t = SeqTracker();
    expect(
      [
        for (final s in [0, 1, 2, 3]) t.accept(s),
      ],
      [0, 0, 0, 0],
    );
    expect(t.gaps, 0);
    expect(t.totalMissing, 0);
  });

  test('a gap counts the skipped packets', () {
    final t = SeqTracker();
    expect(
      [
        for (final s in [0, 1, 5, 6]) t.accept(s),
      ],
      [0, 0, 3, 0],
    );
    expect(t.gaps, 1);
    expect(t.missing, 3);
  });

  test('seq wraps at 65535 without a gap', () {
    final t = SeqTracker();
    for (var i = 0; i <= 65535; i++) {
      t.accept(i);
    }
    expect(t.accept(0), 0);
    expect(t.accept(1), 0);
    expect(t.gaps, 0);
    expect(t.lastSeq, 1);
  });

  test('a gap across the wrap is counted modulo 65536', () {
    final t = SeqTracker();
    for (var i = 0; i <= 65533; i++) {
      t.accept(i);
    }
    expect(t.accept(2), 4); // 65534, 65535, 0, 1 are missing
    expect(t.gaps, 1);
  });

  test('a first packet with seq k > 0 is k missing at start (BACKLOG 27)', () {
    final t = SeqTracker();
    expect(t.accept(1), 1);
    expect(t.missingAtStart, 1);
    expect(t.gaps, 0);
    expect(t.totalMissing, 1);
  });

  test('a new session restarts at seq 0 without a gap', () {
    final t = SeqTracker()
      ..accept(0)
      ..accept(1)
      ..accept(2)
      ..newSession();
    expect(t.accept(0), 0);
    expect(t.gaps, 0);
    expect(t.totalMissing, 0);
  });
}

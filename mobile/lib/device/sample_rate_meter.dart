import 'dart:async';
import 'dart:collection';

import '../ble/packets.dart';
import 'foot_sample.dart';

/// Samples per second per foot over the last [window], from the 50 Hz
/// path by arrival time (rule 3). Read at read time (rule 2): nothing is
/// latched by a timer, so a stream that stops reads as a falling rate.
class SampleRateMeter {
  SampleRateMeter({
    required Stream<FootBatch> batches,
    required this.now,
    this.window = const Duration(seconds: 10),
  }) : _since = now() {
    _sub = batches.listen(_onBatch);
  }

  final DateTime Function() now;
  final Duration window;
  final DateTime _since;
  late final StreamSubscription<FootBatch> _sub;
  final _arrivals = {
    for (final s in FootSide.values) s: ListQueue<(DateTime, int)>(),
  };

  void _onBatch(FootBatch b) {
    _arrivals[b.side]!.add((b.receivedAt, b.samples.length));
    _prune(b.side, b.receivedAt);
  }

  void _prune(FootSide side, DateTime t) {
    final q = _arrivals[side]!;
    while (q.isNotEmpty && t.difference(q.first.$1) > window) {
      q.removeFirst();
    }
  }

  /// Samples per second, or null until the meter has watched one whole
  /// [window] (a shorter count would read low, or high, by chance).
  double? rate(FootSide side) {
    final t = now();
    if (t.difference(_since) < window) return null;
    _prune(side, t);
    final n = _arrivals[side]!.fold<int>(0, (a, e) => a + e.$2);
    return n * Duration.millisecondsPerSecond / window.inMilliseconds;
  }

  void dispose() => _sub.cancel();
}

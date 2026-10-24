import 'foot_sample.dart';

/// Mean total load of one foot (the sum of all FSR channels, kPa, averaged
/// per sample) over the last [windowMs], fed from the 50 Hz path
/// ([DeviceManager.batches]) and read on the 10 Hz display path (rule 10).
///
/// A mean per sample, not a plain sum, so a foot that lost packets is not
/// shown as carrying less weight. Like [RollingPeaks], the window ends at
/// this foot's newest sample time and a new connection session starts an
/// empty window; samples are kept in [bucketMs] buckets.
class RollingLoad {
  RollingLoad({required this.windowMs, this.bucketMs = 100})
    : assert(windowMs % bucketMs == 0);

  final int windowMs;
  final int bucketMs;

  /// (bucket index, summed load, sample count).
  final _buckets = <(int, double, int)>[];
  int? _session;

  /// Adds one batch.
  void add(FootBatch batch) {
    if (batch.session != _session) {
      _session = batch.session;
      _buckets.clear();
    }
    for (final s in batch.samples) {
      final load = s.fsrKpa.fold<double>(0, (a, k) => a + k);
      var index = s.unixMs ~/ bucketMs;
      // Older than the newest bucket (not possible with a monotonic
      // DeviceClock): counted in the newest bucket.
      if (_buckets.isNotEmpty && index < _buckets.last.$1) {
        index = _buckets.last.$1;
      }
      if (_buckets.isNotEmpty && _buckets.last.$1 == index) {
        final (i, sum, n) = _buckets.removeLast();
        _buckets.add((i, sum + load, n + 1));
        continue;
      }
      _buckets.add((index, load, 1));
      final oldest = index - windowMs ~/ bucketMs;
      _buckets.removeWhere((b) => b.$1 <= oldest);
    }
  }

  /// Mean summed kPa per sample in the window, or null when empty.
  double? meanLoad() {
    if (_buckets.isEmpty) return null;
    var sum = 0.0;
    var n = 0;
    for (final (_, s, c) in _buckets) {
      sum += s;
      n += c;
    }
    return sum / n;
  }
}

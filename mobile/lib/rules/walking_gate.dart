import 'dart:collection';
import 'dart:math' as math;

/// Contract §8.3.2's walking gate for one foot: walking while the mean of
/// |‖a‖ − 1 g| over the last `motion.walkingWindowMs` of samples is at or
/// above `motion.walkingAccelG`. The magnitude does not depend on how the
/// foot is turned, so a still foot reads about 1 g whatever its angle.
///
/// Fed from the 50 Hz path, one sample at a time; [add] returns the gate
/// for the window that ends at that sample. Windows are in the samples'
/// own unix time, so a backgrounded app's late timers cannot change it.
class WalkingGate {
  WalkingGate({required this.windowMs, required this.accelG});

  final int windowMs;
  final double accelG;

  final _devs = Queue<(double, double)>();
  bool _walking = false;

  /// The gate after the newest sample.
  bool get walking => _walking;

  /// Adds one sample's accel (x, y, z in g) at [unixMs].
  bool add(double unixMs, List<double> accel) {
    var sq = 0.0;
    for (final a in accel) {
      sq += a * a;
    }
    final dev = (math.sqrt(sq) - 1).abs();
    _devs.add((unixMs, dev));
    while (_devs.first.$1 <= unixMs - windowMs) {
      _devs.removeFirst();
    }
    // Summed afresh (about 40 values), so no running total drifts across
    // the boundary.
    var sum = 0.0;
    for (final (_, d) in _devs) {
      sum += d;
    }
    // Compared in whole mg (the IMU reads 0.24 mg steps), so a mean of
    // exactly `walkingAccelG` is walking whatever the float noise.
    _walking = (sum / _devs.length * 1000).round() >= (accelG * 1000).round();
    return _walking;
  }

  /// A new connection or a gap: the old window no longer describes now.
  void reset() {
    _devs.clear();
    _walking = false;
  }
}

import 'dart:collection';

/// Maps one streaming session's device clock (ms since the board booted,
/// uint32) to phone unix time, per sample.
///
/// The board's `t0_ms` counts from boot and `SYNC_TIME` changes nothing on
/// the wire, so the mapping is the app's: `unix = deviceMs + offset`.
///
/// **Anchored to each packet's own arrival** (BACKLOG 28). A packet leaves
/// the board when its last sample is taken, so its arrival minus that
/// sample's device time is the offset plus this packet's latency. Latency
/// only ever adds, so the smallest such value over a sliding [window] is
/// the best estimate (a minimum-latency filter). The web app's "send time −
/// last received sample" is quantised to the 160 ms packet period instead,
/// which gave its CSV steps of exactly 160 ms; nothing here depends on
/// when a packet happens to arrive relative to anything else.
///
/// **Never backwards, never a step.** The offset actually applied moves
/// toward the estimate by at most [maxSlewMs] per sample, so consecutive
/// sample times are 20 ± [maxSlewMs] ms apart and can never go backwards
/// within a session. A wall-clock step on the phone, or crystal drift, is
/// absorbed the same way. A new session (new `START_STREAM`) needs a new
/// [DeviceClock]: `t0` may restart (REBOOT), and a fresh estimate is right.
class DeviceClock {
  DeviceClock({this.window = defaultWindowMs, this.maxSlewMs = defaultSlewMs});

  /// 30 s of device time: long enough to contain some packet with close to
  /// the least latency, short enough that crystal drift (tens of ppm)
  /// moves the offset by only about 1 ms across it. Technical, not a
  /// clinical threshold.
  static const defaultWindowMs = 30000;

  /// 0.25 ms per 20 ms sample (1.25 %): a 20 ms correction takes 1.6 s,
  /// and sample spacing never leaves 20 ± 0.25 ms.
  static const defaultSlewMs = 0.25;

  final int window;
  final double maxSlewMs;

  int? _lastRaw;
  int _ext = 0;
  double? _applied;
  double? _lastUnix;

  /// (device ms of the packet's last sample, candidate offset), candidates
  /// strictly increasing from front to back: the front is the window
  /// minimum.
  final _candidates = ListQueue<(int, double)>();

  /// Times the monotonic guard had to act. Expected to stay 0; any other
  /// value is a bug worth a look, so it is counted, never hidden.
  int clamps = 0;

  /// The offset applied to the most recent sample (unix ms − device ms).
  double? get offsetMs => _applied;

  /// The current minimum-latency estimate the offset is moving toward.
  double? get targetMs => _candidates.isEmpty ? null : _candidates.first.$2;

  /// Latency of the most recent packet above the current estimate.
  double? lastExcessMs;

  /// Maps one packet's sample times ([deviceMs], ascending, uint32) given
  /// the phone time it arrived. Returns unix ms per sample (fractional).
  List<double> mapPacket(List<int> deviceMs, DateTime receivedAt) {
    if (deviceMs.isEmpty) return const [];
    final ext = [for (final d in deviceMs) _unwrap(d)];
    final last = ext.last;
    final candidate = receivedAt.microsecondsSinceEpoch / 1000 - last;

    while (_candidates.isNotEmpty && _candidates.last.$2 >= candidate) {
      _candidates.removeLast();
    }
    _candidates.addLast((last, candidate));
    while (_candidates.first.$1 < last - window) {
      _candidates.removeFirst();
    }
    final target = _candidates.first.$2;
    lastExcessMs = candidate - target;

    var applied = _applied ?? candidate;
    final out = <double>[];
    for (final d in ext) {
      applied += (target - applied).clamp(-maxSlewMs, maxSlewMs);
      var unix = d + applied;
      final prev = _lastUnix;
      if (prev != null && unix <= prev) {
        clamps++;
        unix = prev + maxSlewMs;
      }
      _lastUnix = unix;
      out.add(unix);
    }
    _applied = applied;
    return out;
  }

  /// Unix ms for a device time on this session's clock (e.g. a temperature
  /// packet's `t_ms`), with the current offset; null before the first
  /// sensor packet. Does not move the clock.
  double? unixOf(int deviceMs) {
    final applied = _applied;
    final lastRaw = _lastRaw;
    if (applied == null || lastRaw == null) return null;
    // Signed distance from the newest sample, modulo 2^32.
    var d = (deviceMs - lastRaw) & 0xFFFFFFFF;
    if (d >= 0x80000000) d -= 0x100000000;
    return _ext + d + applied;
  }

  /// Device time extended past the uint32 wrap (49.7 days). Rule 9 already
  /// guarantees time only moves forward within a session.
  int _unwrap(int raw) {
    final prev = _lastRaw;
    _lastRaw = raw;
    if (prev == null) {
      _ext = raw;
    } else {
      _ext += (raw - prev) & 0xFFFFFFFF;
    }
    return _ext;
  }
}

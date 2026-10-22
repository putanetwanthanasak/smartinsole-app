/// Sensor `seq` continuity (wire `seq` is uint16, so 65535 wraps to 0).
///
/// `seq` restarts at 0 on every `START_STREAM` (BACKLOG 19), so tracking
/// restarts with each session ([newSession]). A session whose first accepted
/// packet has `seq` k > 0 lost its first k packets (BACKLOG 27); those are
/// counted in [missingAtStart], separate from gaps in the middle of a stream,
/// so a board that does not restart `seq` shows up as one clear number
/// rather than as gap noise.
class SeqTracker {
  int? _last;

  /// Gaps inside a stream, and the packets they skipped.
  int gaps = 0;
  int missing = 0;

  /// Packets missing before the first accepted packet of a session.
  int missingAtStart = 0;

  int? get lastSeq => _last;

  /// Every packet lost so far, at the start of a session or in the middle.
  int get totalMissing => missing + missingAtStart;

  /// Records an accepted packet and returns how many packets are missing
  /// just before it.
  int accept(int seq) {
    final last = _last;
    _last = seq;
    if (last == null) {
      missingAtStart += seq;
      return seq;
    }
    final expected = (last + 1) & 0xFFFF;
    if (seq == expected) return 0;
    final m = (seq - expected) & 0xFFFF;
    gaps++;
    missing += m;
    return m;
  }

  /// A new `START_STREAM`: the next packet is expected to be `seq` 0.
  void newSession() => _last = null;
}

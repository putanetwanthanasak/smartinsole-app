import 'dart:collection';

import 'packets.dart';
import 'parse_result.dart';

/// Per-foot counters for the debug screen and the checkpoint log. Nothing
/// that is dropped goes uncounted: every rejection and every rule-9 drop
/// lands here. Time-dependent values (rate, age) take `now` and are worked
/// out when read, never latched by a timer (rule 2).
class LinkStats {
  /// Sensor packets that passed every check and were emitted.
  int packets = 0;
  int tempPackets = 0;
  int statusPackets = 0;

  /// Parser rejections, by reason (sensor, temperature and status).
  final rejects = <RejectReason, int>{};

  /// Rule 9 check 1: arrived before this connection's START was acknowledged.
  int droppedBeforeStart = 0;

  /// Rule 9: delivered by an earlier connection's subscription.
  int droppedOldConnection = 0;

  /// Rule 9 check 2: `t0_ms` (or temperature `t_ms`) did not advance within
  /// the connection.
  int droppedNotForward = 0;

  /// Sensor `seq` gaps (wrap at 65535) and the packets they skipped.
  /// Counted for the checkpoint only; S4 owns real gap handling.
  int seqGaps = 0;
  int seqMissing = 0;

  /// Successful connect sequences (START acknowledged).
  int sessions = 0;

  /// Links that dropped while connected (not counting the user's own
  /// Disconnect).
  int linkLosses = 0;
  int failedAttempts = 0;
  int calibrationRereads = 0;

  int? lastSeq;
  DateTime? lastPacketAt;
  StatusPacket? lastStatus;
  TempPacket? lastTemp;
  List<double>? lastKpa;

  /// The insole's advertised name when it was chosen. Display only.
  String? advertisedName;
  String? calibrationDeviceId;

  final _arrivals = ListQueue<DateTime>();

  void countReject(RejectReason reason) =>
      rejects[reason] = (rejects[reason] ?? 0) + 1;

  int get totalRejects => rejects.values.fold(0, (a, b) => a + b);

  /// Records an emitted sensor packet's arrival.
  void packetArrived(DateTime at) {
    packets++;
    lastPacketAt = at;
    _arrivals.addLast(at);
    while (_arrivals.length > 200) {
      _arrivals.removeFirst();
    }
  }

  /// Emitted sensor packets per second over the [window] ending at [now].
  double packetRate(DateTime now, {Duration window = rateWindow}) {
    final from = now.subtract(window);
    final n = _arrivals.where((t) => t.isAfter(from)).length;
    return n / (window.inMilliseconds / 1000);
  }

  static const rateWindow = Duration(seconds: 10);

  /// Resets what belongs to one connection (the `seq` baseline).
  void newSession() => lastSeq = null;
}

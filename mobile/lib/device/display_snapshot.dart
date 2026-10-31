import '../ble/packets.dart';

/// What the UI may say about one foot's link, derived at read time
/// (rule 2).
enum FootConnection {
  /// Not connected and not trying (also: the user disconnected).
  notConnected,

  /// Searching, connecting, retrying, or streaming but no sample yet.
  connecting,

  /// Streaming and the newest sample is fresh.
  streaming,

  /// Streaming, but no sample for longer than `staleAfter`.
  stale,

  /// Stopped on purpose (wrong side, MTU too small, …); needs the user.
  problem,
}

/// One foot on the 10 Hz display path. Sensor values are only present while
/// the foot is [usable]: a stale or missing foot shows "no data", never its
/// last values as if they were current (rules 4 and 5).
class FootView {
  const FootView({
    required this.side,
    required this.connection,
    this.batteryPct,
    this.firmware,
    this.errorCode,
    this.kpa,
    this.saturated = false,
    this.calibrating = false,
    this.temp,
    this.lastSampleAt,
    this.lostPackets = 0,
  });

  final FootSide side;
  final FootConnection connection;

  /// From the latest status packet of this connection (null when not
  /// connected).
  final int? batteryPct;
  final String? firmware;
  final int? errorCode;

  /// kPa per FSR channel, the newest sample; null unless [usable].
  final List<double>? kpa;
  final bool saturated;
  final bool calibrating;

  /// Newest temperature reading of this connection; null unless [usable].
  final TempPacket? temp;

  /// Phone time the newest sample arrived (rule 3).
  final DateTime? lastSampleAt;

  /// Packets lost in this connection so far.
  final int lostPackets;

  bool get usable => connection == FootConnection.streaming;
}

/// Both feet at one moment, for the UI (10 Hz).
class DisplaySnapshot {
  const DisplaySnapshot({
    required this.at,
    required this.left,
    required this.right,
    required this.deltaC,
  });

  final DateTime at;
  final FootView left;
  final FootView right;

  /// ΔT per temperature site (index = zone index, NTC i next to FSR i),
  /// left minus right (contract §7.3), °C. A site's value is null unless
  /// both feet are usable and both feet's readings of that site are present
  /// with normal quality: a ΔT from one foot would be a fabricated clinical
  /// reading (rule 4).
  final List<double?> deltaC;

  /// The site with the largest |ΔT| (the lower index on a tie), or null
  /// when no site has a ΔT.
  int? get maxDeltaSite => maxAbsSite(deltaC);

  /// |ΔT| at [maxDeltaSite], or null.
  double? get maxAbsDeltaC {
    final s = maxDeltaSite;
    return s == null ? null : deltaC[s]!.abs();
  }

  FootView of(FootSide side) => side == FootSide.left ? left : right;
}

/// Index of the largest |v| in [values] (the lower index on a tie), or null
/// when every value is null.
int? maxAbsSite(List<double?> values) {
  int? best;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v == null) continue;
    if (best == null || v.abs() > values[best]!.abs()) best = i;
  }
  return best;
}

import '../ble/packets.dart';

/// One sample on the 50 Hz path (rule 10): the sensor values in app units,
/// with the raw ADC kept, and its unix time from `DeviceClock`.
class FootSample {
  const FootSample({
    required this.unixMs,
    required this.deviceMs,
    required this.fsrAdc,
    required this.fsrKpa,
    required this.accelG,
    required this.gyroDps,
  });

  /// Phone unix time of this sample, ms (fractional). Strictly increasing
  /// within a session, 20 ± 0.25 ms apart.
  final double unixMs;

  /// `t0_ms + i × 20` on the board's clock (rule 1), uint32.
  final int deviceMs;

  /// Raw ADC and kPa per FSR channel, channel index order (N channels).
  final List<int> fsrAdc;
  final List<double> fsrKpa;

  /// x, y, z in g and °/s.
  final List<double> accelG;
  final List<double> gyroDps;
}

/// One sensor packet of one foot on the 50 Hz path, unthrottled.
class FootBatch {
  const FootBatch({
    required this.side,
    required this.session,
    required this.seq,
    required this.missingBefore,
    required this.receivedAt,
    required this.saturated,
    required this.calibrating,
    required this.samples,
  });

  final FootSide side;

  /// Streaming session (one per `START_STREAM`); a new value means a new
  /// connection and a new clock.
  final int session;
  final int seq;

  /// Packets lost just before this one (a `seq` gap, or a lost start of
  /// stream). Research capture records it as a gap.
  final int missingBefore;

  /// Phone time the packet arrived (rule 3).
  final DateTime receivedAt;

  /// Packet flags: some ADC hit 4095 / a TARE was running.
  final bool saturated;
  final bool calibrating;
  final List<FootSample> samples;
}

/// Parsed wire packets, before any unit conversion except temperature (which
/// the device already sends in 0.01 °C). See `docs/BLE-INTERFACE.md`.
library;

enum FootSide { left, right }

enum DeviceState { idle, streaming, error }

enum TempQuality { normal, poorContact, sensorFault }

class SensorPacketHeader {
  const SensorPacketHeader({
    required this.seq,
    required this.t0Ms,
    required this.count,
    required this.saturated,
    required this.calibrating,
  });

  final int seq;

  /// Device time of the first sample, ms since device boot (not unix time).
  final int t0Ms;

  /// Samples in this packet, read from the wire (normally 8).
  final int count;
  final bool saturated;
  final bool calibrating;
}

class RawSensorSample {
  const RawSensorSample({
    required this.deviceMs,
    required this.fsrAdc,
    required this.accelRaw,
    required this.gyroRaw,
  });

  /// `t0_ms + i × 20` (rule 1), device clock.
  final int deviceMs;

  /// N raw ADC values (0–4095) in FSR channel index order.
  final List<int> fsrAdc;

  /// x, y, z.
  final List<int> accelRaw;
  final List<int> gyroRaw;
}

class SensorPacket {
  const SensorPacket({
    required this.header,
    required this.samples,
    required this.byteLength,
  });

  final SensorPacketHeader header;
  final List<RawSensorSample> samples;
  final int byteLength;
}

/// One temperature reading of all 8 sites of a foot (DATA-CONTRACT v1.6
/// §3.2). Site i is the NTC next to FSR i, so it shares the zone's index in
/// `footLayout.zones`.
class TempPacket {
  const TempPacket({
    required this.seq,
    required this.tMs,
    required this.celsius,
    required this.quality,
  });

  final int seq;
  final int tMs;

  /// Per site; null when the wire value is `-32768` ("could not read"):
  /// never show that as a number.
  final List<double?> celsius;

  /// Per site.
  final List<TempQuality> quality;

  int get siteCount => celsius.length;

  /// The site's temperature when it can be compared with the other foot: a
  /// value with `normal` quality, else null.
  double? usableC(int site) =>
      site < siteCount && quality[site] == TempQuality.normal
      ? celsius[site]
      : null;

  /// Every site has a value with `normal` quality.
  bool get allNormal =>
      [for (var i = 0; i < siteCount; i++) usableC(i)].every((c) => c != null);
}

class StatusPacket {
  const StatusPacket({
    required this.batteryPct,
    required this.batteryMv,
    required this.footSide,
    required this.fwMajor,
    required this.fwMinor,
    required this.state,
    required this.errorCode,
  });

  final int batteryPct;
  final int batteryMv;
  final FootSide footSide;
  final int fwMajor;
  final int fwMinor;
  final DeviceState state;

  /// 0 = none; see Data Contract appendix A. Kept raw so an unknown code is
  /// still reported rather than dropped.
  final int errorCode;
}

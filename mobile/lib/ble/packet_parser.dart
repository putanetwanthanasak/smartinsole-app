import 'dart:typed_data';

import 'ble_protocol.dart';
import 'packets.dart';
import 'parse_result.dart';

/// Pure parsers for the three notify/read packets (`docs/BLE-INTERFACE.md`).
/// No connection state, no side effects. Behaviour matches the web app's
/// `src/ts/data/blePacketParser.ts` on every vector in
/// `shared/test_vectors/`, with two deliberate differences, both stricter:
/// - an out-of-range enum byte (foot side, state, quality) rejects the
///   packet, where TS masks it into range. A masked `foot_side = 2` would
///   read as "left" and defeat rule 8;
/// - a sensor packet longer than its header's `count` accounts for is
///   rejected, where TS ignores the extra bytes. Otherwise a packet parsed
///   with the wrong FSR count could pass and put readings on the wrong
///   zones.

/// Parses a Sensor Stream packet whose samples carry [fsrCount] FSR channels
/// (N, from the calibration blob).
ParseResult<SensorPacket> parseSensorPacket(
  Uint8List bytes, {
  required int fsrCount,
}) {
  assert(fsrCount > 0);
  if (bytes.length < SensorLayout.headerBytes) {
    return Rejected(
      RejectReason.tooShort,
      'sensor packet has ${bytes.length} bytes, header needs '
      '${SensorLayout.headerBytes}',
      expectedBytes: SensorLayout.headerBytes,
      actualBytes: bytes.length,
    );
  }
  final data = ByteData.sublistView(bytes);
  final seq = data.getUint16(0, Endian.little);
  final t0Ms = data.getUint32(2, Endian.little);
  final count = data.getUint8(6);
  final flags = data.getUint8(7);

  final block = SensorLayout.sampleBytes(fsrCount);
  final expected = SensorLayout.headerBytes + count * block;
  if (bytes.length < expected) {
    return Rejected(
      RejectReason.truncated,
      'seq $seq: count $count × $block-byte samples needs $expected bytes, '
      'got ${bytes.length}',
      expectedBytes: expected,
      actualBytes: bytes.length,
    );
  }

  if (bytes.length > expected) {
    return Rejected(
      RejectReason.lengthMismatch,
      'seq $seq: count $count × $block-byte samples needs $expected bytes, '
      'got ${bytes.length} (wrong FSR count?)',
      expectedBytes: expected,
      actualBytes: bytes.length,
    );
  }

  final samples = List.generate(count, (i) {
    final base = SensorLayout.headerBytes + i * block;
    final imu = base + 2 * fsrCount;
    return RawSensorSample(
      deviceMs: t0Ms + i * SensorLayout.sampleSpacingMs,
      fsrAdc: List.generate(
        fsrCount,
        (ch) => data.getUint16(base + ch * 2, Endian.little),
      ),
      accelRaw: List.generate(
        3,
        (k) => data.getInt16(imu + k * 2, Endian.little),
      ),
      gyroRaw: List.generate(
        3,
        (k) => data.getInt16(imu + 6 + k * 2, Endian.little),
      ),
    );
  });

  return Parsed(
    SensorPacket(
      header: SensorPacketHeader(
        seq: seq,
        t0Ms: t0Ms,
        count: count,
        saturated: flags & SensorLayout.flagSaturated != 0,
        calibrating: flags & SensorLayout.flagCalibrating != 0,
      ),
      samples: samples,
      byteLength: bytes.length,
    ),
  );
}

/// Temperature v2 (DATA-CONTRACT v1.6 §3.2). Strict: exactly 32 bytes,
/// `count` 8 and every quality byte 0–2, else a named rejection. The old
/// 12-byte packet is never read as v2 (it would give made-up numbers).
ParseResult<TempPacket> parseTempPacket(Uint8List bytes) {
  if (bytes.length != TempLayout.packetBytes) {
    final legacy = bytes.length == TempLayout.legacyPacketBytes
        ? ' (the v1 forefoot/heel packet: firmware older than contract v1.6)'
        : '';
    return Rejected(
      RejectReason.tempLength,
      'temperature packet has ${bytes.length} bytes, needs exactly '
      '${TempLayout.packetBytes}$legacy',
      expectedBytes: TempLayout.packetBytes,
      actualBytes: bytes.length,
    );
  }
  final data = ByteData.sublistView(bytes);
  final count = data.getUint8(TempLayout.countOffset);
  if (count != TempLayout.siteCount) {
    return Rejected(
      RejectReason.tempCount,
      'temperature count $count, needs ${TempLayout.siteCount}',
    );
  }
  final quality = <TempQuality>[];
  for (var i = 0; i < TempLayout.siteCount; i++) {
    final q = data.getUint8(TempLayout.qualityOffset + i);
    if (q >= TempQuality.values.length) {
      return Rejected(
        RejectReason.invalidQuality,
        'temperature site $i quality byte $q',
      );
    }
    quality.add(TempQuality.values[q]);
  }
  return Parsed(
    TempPacket(
      seq: data.getUint16(0, Endian.little),
      tMs: data.getUint32(2, Endian.little),
      celsius: [
        for (var i = 0; i < TempLayout.siteCount; i++)
          _tempC(data.getInt16(TempLayout.tempOffset + 2 * i, Endian.little)),
      ],
      quality: quality,
    ),
  );
}

double? _tempC(int raw) =>
    raw == TempLayout.unreadableRaw ? null : raw / Scaling.tempRawPerC;

ParseResult<StatusPacket> parseStatusPacket(Uint8List bytes) {
  if (bytes.length < StatusLayout.packetBytes) {
    return Rejected(
      RejectReason.tooShort,
      'status packet has ${bytes.length} bytes, needs '
      '${StatusLayout.packetBytes}',
      expectedBytes: StatusLayout.packetBytes,
      actualBytes: bytes.length,
    );
  }
  final data = ByteData.sublistView(bytes);
  final sideByte = data.getUint8(3);
  if (sideByte >= FootSide.values.length) {
    return Rejected(
      RejectReason.invalidFootSide,
      'status foot_side byte $sideByte',
    );
  }
  final stateByte = data.getUint8(6);
  if (stateByte >= DeviceState.values.length) {
    return Rejected(RejectReason.invalidState, 'status state byte $stateByte');
  }
  return Parsed(
    StatusPacket(
      batteryPct: data.getUint8(0),
      batteryMv: data.getUint16(1, Endian.little),
      footSide: FootSide.values[sideByte],
      fwMajor: data.getUint8(4),
      fwMinor: data.getUint8(5),
      state: DeviceState.values[stateByte],
      errorCode: data.getUint8(7),
    ),
  );
}

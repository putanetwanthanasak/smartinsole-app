/// GATT UUIDs, control opcodes, packet layout and scaling constants for the
/// SmartInsole BLE interface. Every value is from `docs/BLE-INTERFACE.md`
/// (an extract of `docs/DATA-CONTRACT.md` §2–§5; the contract wins if the two
/// disagree). Nothing else in the app restates these numbers.
abstract final class BleUuids {
  static const service = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900';
  static const sensorStream = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45901';
  static const temperature = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45902';
  static const deviceStatus = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45903';
  static const control = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45904';
  static const calibration = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45905';
}

/// Control opcodes, written to [BleUuids.control].
abstract final class BleOpcode {
  static const startStream = 0x01;
  static const stopStream = 0x02;

  /// Payload: uint64 unix ms.
  static const syncTime = 0x03;

  /// Payload: uint8 Hz.
  static const setRate = 0x04;
  static const tare = 0x05;
  static const reboot = 0x06;

  /// `SYNC_TIME` is opcode + uint64 (9 bytes); the others are the opcode
  /// alone. The simulator ignores any other length (BACKLOG 24).
  static const syncTimeBytes = 9;
}

abstract final class SensorLayout {
  /// FSR channels on the study insole (DATA-CONTRACT v1.6 §3.1, one per
  /// site of `shared/sensor_layout.json`). The parser reads any N from the
  /// calibration blob; the connect sequence refuses an insole whose N is
  /// not this (`calibrationFsrCount`), so no zone is ever made up.
  static const fsrCount = 8;

  /// `seq` u16, `t0_ms` u32, `count` u8, `flags` u8.
  static const headerBytes = 8;

  /// accel x/y/z + gyro x/y/z, int16 each.
  static const imuBytes = 12;

  /// Normal samples per packet; the MTU fallback sends fewer.
  static const samplesPerPacket = 8;

  /// Rule 1: sample i is at `t0_ms + i × 20`.
  static const sampleSpacingMs = 20;

  static const flagSaturated = 0x01;
  static const flagCalibrating = 0x02;

  /// One sample block: N uint16 FSR values, then the IMU (FLUTTER-PLAN §5:
  /// `2N + 12` bytes, N from the calibration blob). The contract's 28-byte
  /// block is the N = 8 case.
  static int sampleBytes(int fsrCount) => 2 * fsrCount + imuBytes;

  /// Bytes of one packet carrying [samples] samples of [fsrCount] channels.
  static int packetBytes(int fsrCount, int samples) =>
      headerBytes + samples * sampleBytes(fsrCount);
}

/// MTU negotiation (contract §2.3): target 247; if 8 samples don't fit, the
/// device drops to 4 per packet; if 4 don't fit either, it sends nothing.
abstract final class MtuLayout {
  /// Requested on every connect and every reconnect.
  static const targetMtu = 247;

  /// ATT notification header (opcode + handle); payload = MTU − 3.
  static const attOverhead = 3;

  /// The contract's only fallback packet size.
  static const fallbackSamplesPerPacket = 4;

  /// Samples per packet the device will send at [mtu] with [fsrCount]
  /// channels: 8, 4, or 0 when even the fallback packet does not fit.
  static int samplesPerPacket(int mtu, int fsrCount) {
    final payload = mtu - attOverhead;
    for (final n in const [
      SensorLayout.samplesPerPacket,
      fallbackSamplesPerPacket,
    ]) {
      if (SensorLayout.packetBytes(fsrCount, n) <= payload) return n;
    }
    return 0;
  }

  /// Smallest MTU that fits the fallback packet.
  static int minUsableMtu(int fsrCount) =>
      SensorLayout.packetBytes(fsrCount, fallbackSamplesPerPacket) +
      attOverhead;
}

/// Temperature v2 (DATA-CONTRACT v1.6 §3.2): `seq` u16, `t_ms` u32,
/// `count` u8 (= [siteCount]), reserved u8, temperature int16 × 8 (0.01 °C),
/// quality u8 × 8. Site i is the NTC next to FSR i (`sensor_layout.json`).
/// The v1 packet (12 bytes, forefoot and heel only) is refused since v1.6.
abstract final class TempLayout {
  /// Exactly this many bytes; anything else is `tempLength`.
  static const packetBytes = 32;

  /// Sites per packet; any other `count` byte is `tempCount`.
  static const siteCount = 8;

  static const countOffset = 6;
  static const tempOffset = 8;
  static const qualityOffset = 24;

  /// The refused v1 packet's length, named in the rejection detail.
  static const legacyPacketBytes = 12;

  /// The device sends one temperature reading every 30 s (1/30 Hz).
  static const notifyPeriod = Duration(seconds: 30);

  /// Wire value meaning "could not read".
  static const unreadableRaw = -32768;
}

abstract final class StatusLayout {
  static const packetBytes = 8;
}

abstract final class Scaling {
  static const accelLsbPerG = 4096.0;
  static const gyroLsbPerDps = 32.8;
  static const tempRawPerC = 100.0;

  /// FSR divider supply voltage and ADC full scale (§5.1).
  static const supplyVoltage = 3.3;
  static const adcMax = 4095;
}

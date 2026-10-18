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
}

abstract final class SensorLayout {
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
  /// `2N + 12` bytes, N from the calibration blob). The contract's 24-byte
  /// block is the N = 6 case.
  static int sampleBytes(int fsrCount) => 2 * fsrCount + imuBytes;
}

abstract final class TempLayout {
  static const packetBytes = 12;

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

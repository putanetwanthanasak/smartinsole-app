// Packet encoders. Each writes exactly the contract's byte count and returns
// it; nothing is ever padded or truncated (report 021: the app rejects any
// sensor packet whose length isn't exactly 8 + count * (2N + 12)).
#pragma once

#include "protocol.h"

namespace insole {

struct Sample {
  uint16_t fsr[kMaxFsrCount];  // raw ADC 0–4095; only the first N are sent
  int16_t accel[3];            // 4096 LSB/g
  int16_t gyro[3];             // 32.8 LSB/(deg/s)
};

// One reading of every temperature site (index = FSR channel index).
struct TemperatureReading {
  int16_t temp[kTempSiteCount];     // 0.01 degC, kTempUnreadable if not read
  uint8_t quality[kTempSiteCount];  // 0 normal, 1 poor contact, 2 sensor fault
};

struct DeviceStatus {
  uint8_t batteryPct;
  uint16_t batteryMv;
  uint8_t footSide;  // 0 left, 1 right
  uint8_t fwMajor;
  uint8_t fwMinor;
  DeviceState state;
  uint8_t errorCode;
};

// `out` must hold sensorPacketSize(count, fsrCount) bytes.
size_t encodeSensor(uint8_t* out, uint16_t seq, uint32_t t0Ms, uint8_t flags,
                    const Sample* samples, uint8_t count, uint8_t fsrCount);

// `out` must hold kTemperatureBytes.
size_t encodeTemperature(uint8_t* out, uint16_t seq, uint32_t tMs,
                         const TemperatureReading& reading);

// `out` must hold kStatusBytes.
size_t encodeStatus(uint8_t* out, const DeviceStatus& status);

}  // namespace insole

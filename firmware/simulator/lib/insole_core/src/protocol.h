// Wire-format constants: docs/BLE-INTERFACE.md, Data Contract §2–3.
// Everything in lib/insole_core is plain C++ (no Arduino, no NimBLE) so it
// builds and is tested on the host too.
#pragma once

#include <cstddef>
#include <cstdint>

namespace insole {

constexpr const char* kServiceUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900";
constexpr const char* kSensorUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45901";
constexpr const char* kTemperatureUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45902";
constexpr const char* kStatusUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45903";
constexpr const char* kControlUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45904";
constexpr const char* kCalibrationUuid = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45905";

constexpr uint16_t kTargetMtu = 247;
constexpr uint16_t kAttHeaderBytes = 3;  // notification payload = MTU - 3

constexpr uint32_t kSamplePeriodMs = 20;  // 50 Hz; sample i is t0 + i * 20
constexpr uint8_t kSamplesPerPacket = 8;
constexpr uint8_t kFallbackSamplesPerPacket = 4;  // contract §2.3 MTU fallback
constexpr uint32_t kTemperaturePeriodMs = 30000;

constexpr uint8_t kMaxFsrCount = 8;
constexpr size_t kSensorHeaderBytes = 8;
constexpr size_t kTemperatureBytes = 12;
constexpr size_t kStatusBytes = 8;
constexpr size_t kMaxCalibrationBytes = 512;

constexpr size_t sampleSize(uint8_t fsrCount) { return 2u * fsrCount + 12u; }
constexpr size_t sensorPacketSize(uint8_t count, uint8_t fsrCount) {
  return kSensorHeaderBytes + count * sampleSize(fsrCount);
}
constexpr size_t kMaxSensorPacketBytes = sensorPacketSize(kSamplesPerPacket, kMaxFsrCount);

constexpr uint8_t kFlagSaturated = 0x01;
constexpr uint8_t kFlagCalibrating = 0x02;

constexpr int16_t kTempUnreadable = -32768;

enum class Opcode : uint8_t {
  StartStream = 0x01,
  StopStream = 0x02,
  SyncTime = 0x03,
  SetRate = 0x04,
  Tare = 0x05,
  Reboot = 0x06,
};

enum class DeviceState : uint8_t { Idle = 0, Streaming = 1, Error = 2 };

}  // namespace insole

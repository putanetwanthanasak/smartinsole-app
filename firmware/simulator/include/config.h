// Build-time configuration, set per env in platformio.ini.
#pragma once

#include "protocol.h"

// 0 = left, 1 = right (Device Status `foot_side`, Data Contract §3.3).
#ifndef FOOT_SIDE
#error "FOOT_SIDE must be set by the build (0 = left, 1 = right)"
#endif
static_assert(FOOT_SIDE == 0 || FOOT_SIDE == 1, "FOOT_SIDE must be 0 or 1");

// FSR channels per sample. Data Contract v1.6 fixes 8 (28-byte sample,
// 232-byte packet); the app refuses any other N at connect. Other values
// (the left_fsr6 env) are build checks of the 2N + 12 layout only.
#ifndef FSR_COUNT
#define FSR_COUNT 8
#endif
static_assert(FSR_COUNT >= 1 && FSR_COUNT <= insole::kMaxFsrCount,
              "FSR_COUNT must be 1..8");
static_assert(insole::sensorPacketSize(insole::kSamplesPerPacket, FSR_COUNT) <=
                  insole::kTargetMtu - insole::kAttHeaderBytes,
              "8 samples must fit one notification at MTU 247");

namespace config {
constexpr uint8_t kFootSide = FOOT_SIDE;
constexpr uint8_t kFsrCount = FSR_COUNT;
constexpr const char* kDeviceName = FOOT_SIDE == 0 ? "SMARTINSOLE-L" : "SMARTINSOLE-R";
constexpr const char* kDeviceId = FOOT_SIDE == 0 ? "SIM-L-001" : "SIM-R-001";
constexpr uint8_t kFwMajor = 0;
constexpr uint8_t kFwMinor = 1;
}  // namespace config

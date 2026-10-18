// Synthetic walking data: the default DataSource. Pure functions only.
#pragma once

#include "data_source.h"

namespace insole::synth {

constexpr uint32_t kGaitCycleMs = 1100;  // one stride, ~109 steps/min per foot
constexpr float kStanceFraction = 0.6f;  // stance 60 %, swing 40 %
constexpr uint8_t kBatteryFloorPct = 50; // stays well above BATTERY_LOW (< 15 %)
constexpr uint32_t kMsPerBatteryPct = 6u * 60u * 1000u;  // 100 % -> 50 % in 5 h

Sample gaitSample(uint32_t tMs, uint8_t footSide, uint8_t fsrCount);
TemperatureReading temperature(uint32_t tMs, uint8_t footSide);
BatteryReading battery(uint32_t tMs);

const DataSource& walking();

}  // namespace insole::synth

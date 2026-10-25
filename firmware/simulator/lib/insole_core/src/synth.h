// Synthetic walking data: the default DataSource. Pure functions only.
#pragma once

#include "data_source.h"

namespace insole::synth {

constexpr uint32_t kGaitCycleMs = 1100;  // one stride, ~109 steps/min per foot
constexpr float kStanceFraction = 0.6f;  // stance 60 %, swing 40 %
constexpr uint8_t kBatteryFloorPct = 50; // stays well above BATTERY_LOW (< 15 %)
constexpr uint32_t kMsPerBatteryPct = 6u * 60u * 1000u;  // 100 % -> 50 % in 5 h
// The walk's dynamic accel (the deviation from a still 1 g) is the base
// shape in synth.cpp times this, so the app's walking gate (contract 8.3.2:
// mean |a| - 1 g over motion.walkingWindowMs >= motion.walkingAccelG) is on
// through every window: lowest window about 0.17 g, mean about 0.34 g
// (BACKLOG 42, S8A). The base shape alone had a lowest window of 0.07 g.
constexpr float kWalkMotionScale = 3.0f;

Sample gaitSample(uint32_t tMs, uint8_t footSide, uint8_t fsrCount);
TemperatureReading temperature(uint32_t tMs, uint8_t footSide);
BatteryReading battery(uint32_t tMs);

const DataSource& walking();

}  // namespace insole::synth

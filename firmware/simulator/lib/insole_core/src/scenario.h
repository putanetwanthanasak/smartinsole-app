// Serial-command scenarios for the S7 phone check (decision 4): a single
// board can be made to raise TEMP_DELTA or PRESSURE_PEAK in the app
// without touching packets, BLE or the contract. Each scenario is a pure
// DataSource built on the normal walk (synth.h).
#pragma once

#include "data_source.h"

namespace insole::scenario {

enum class Id : uint8_t {
  normal,         // 'n': synth::walking() unchanged
  warmForefoot,   // 't': this board's forefoot +3.0 degC
  highMeta1,      // 'p': meta1 about 250 kPa with a long stance plateau
};

constexpr int16_t kWarmForefootCentiC = 300;

// meta1 (FSR index 1) plateau: about 249 kPa with the served calibration.
constexpr uint16_t kHighMeta1Adc = 3180;
// Stance fractions: ramp up, plateau, ramp down (a long plateau, so one
// step's pressure-time integral is well above pressure.ptiKpaS).
constexpr float kPlateauRise = 0.12f, kPlateauStart = 0.22f;
constexpr float kPlateauEnd = 0.82f, kPlateauFall = 0.92f;
// The dynamic part of the accel (deviation from a still 1 g) is scaled by
// this, so the app's walking gate (contract 8.3.2: mean |a| - 1 g over
// motion.walkingWindowMs >= motion.walkingAccelG) is on through every
// window. The normal walk's motion is gentler and does not keep it on.
constexpr float kHighMeta1MotionScale = 4.0f;

const DataSource& source(Id id);
const char* name(Id id);

// The scenario for a serial command character; false for any other char.
bool fromCommand(char c, Id* out);

// Pure pieces, for tests.
Sample highMeta1Sample(uint32_t tMs, uint8_t footSide, uint8_t fsrCount);
TemperatureReading warmTemperature(uint32_t tMs, uint8_t footSide);

}  // namespace insole::scenario

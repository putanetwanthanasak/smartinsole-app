#include "scenario.h"

#include <cmath>

#include "synth.h"

namespace insole::scenario {
namespace {

constexpr float kPi = 3.14159265f;

// 0..1 load of the meta1 plateau at stance fraction st.
float plateau(float st) {
  if (st <= kPlateauRise || st >= kPlateauFall) return 0;
  if (st < kPlateauStart) {
    return 0.5f * (1 - std::cos(kPi * (st - kPlateauRise) / (kPlateauStart - kPlateauRise)));
  }
  if (st <= kPlateauEnd) return 1;
  return 0.5f * (1 + std::cos(kPi * (st - kPlateauEnd) / (kPlateauFall - kPlateauEnd)));
}

}  // namespace

Sample highMeta1Sample(uint32_t tMs, uint8_t footSide, uint8_t fsrCount) {
  Sample s = synth::gaitSample(tMs, footSide, fsrCount);
  // Same stride and phase as the normal walk (synth.cpp).
  uint32_t shifted = tMs + (footSide == 1 ? synth::kGaitCycleMs / 2 : 0);
  float ph = static_cast<float>(shifted % synth::kGaitCycleMs) / synth::kGaitCycleMs;
  if (fsrCount > 1 && ph < synth::kStanceFraction) {
    float st = ph / synth::kStanceFraction;
    float adc = s.fsr[1] + (kHighMeta1Adc - s.fsr[1]) * plateau(st);
    if (adc > s.fsr[1]) s.fsr[1] = static_cast<uint16_t>(std::lround(adc));
  }
  // The walk's own motion keeps the walking gate on (synth.h, S8A).
  return s;
}

TemperatureReading warmTemperature(uint32_t tMs, uint8_t footSide) {
  TemperatureReading t = synth::temperature(tMs, footSide);
  t.temp[kWarmSite] = static_cast<int16_t>(t.temp[kWarmSite] + kWarmCentiC);
  return t;
}

const DataSource& source(Id id) {
  static const DataSource warm{synth::gaitSample, warmTemperature, synth::battery};
  static const DataSource high{highMeta1Sample, synth::temperature, synth::battery};
  switch (id) {
    case Id::warmSite: return warm;
    case Id::highMeta1: return high;
    case Id::normal: break;
  }
  return synth::walking();
}

const char* name(Id id) {
  switch (id) {
    case Id::warmSite: return "t (temperature site 1, MTH1, +3.0 degC)";
    case Id::highMeta1: return "p (meta1 ~250 kPa plateau)";
    case Id::normal: break;
  }
  return "n (normal walk)";
}

bool fromCommand(char c, Id* out) {
  switch (c) {
    case 'n': *out = Id::normal; return true;
    case 't': *out = Id::warmSite; return true;
    case 'p': *out = Id::highMeta1; return true;
    default: return false;
  }
}

}  // namespace insole::scenario

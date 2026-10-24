#include "scenario.h"

#include <cmath>

#include "synth.h"

namespace insole::scenario {
namespace {

constexpr float kPi = 3.14159265f;
constexpr float kAccelLsbPerG = 4096;

int16_t clampI16(float v) {
  if (v > 32767) return 32767;
  if (v < -32768) return -32768;
  return static_cast<int16_t>(std::lround(v));
}

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
  // Stronger walking motion: still 1 g (z) plus k x the normal deviation.
  float x = s.accel[0] / kAccelLsbPerG, y = s.accel[1] / kAccelLsbPerG;
  float z = s.accel[2] / kAccelLsbPerG;
  const float k = kHighMeta1MotionScale;
  s.accel[0] = clampI16(k * x * kAccelLsbPerG);
  s.accel[1] = clampI16(k * y * kAccelLsbPerG);
  s.accel[2] = clampI16((1 + k * (z - 1)) * kAccelLsbPerG);
  return s;
}

TemperatureReading warmTemperature(uint32_t tMs, uint8_t footSide) {
  TemperatureReading t = synth::temperature(tMs, footSide);
  t.forefoot = static_cast<int16_t>(t.forefoot + kWarmForefootCentiC);
  return t;
}

const DataSource& source(Id id) {
  static const DataSource warm{synth::gaitSample, warmTemperature, synth::battery};
  static const DataSource high{highMeta1Sample, synth::temperature, synth::battery};
  switch (id) {
    case Id::warmForefoot: return warm;
    case Id::highMeta1: return high;
    case Id::normal: break;
  }
  return synth::walking();
}

const char* name(Id id) {
  switch (id) {
    case Id::warmForefoot: return "t (forefoot +3.0 degC)";
    case Id::highMeta1: return "p (meta1 ~250 kPa plateau, strong walking motion)";
    case Id::normal: break;
  }
  return "n (normal walk)";
}

bool fromCommand(char c, Id* out) {
  switch (c) {
    case 'n': *out = Id::normal; return true;
    case 't': *out = Id::warmForefoot; return true;
    case 'p': *out = Id::highMeta1; return true;
    default: return false;
  }
}

}  // namespace insole::scenario

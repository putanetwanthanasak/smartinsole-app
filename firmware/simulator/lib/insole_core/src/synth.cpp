#include "synth.h"

#include <cmath>

namespace insole::synth {
namespace {

constexpr float kPi = 3.14159265f;

struct Channel {
  float center;  // where in stance (0..1) the channel peaks
  float width;   // stance fraction over which it is loaded
  float peakAdc;
};

// Contract FSR order (index 0..5): hallux, meta1, meta3, meta5, midfoot,
// heel. Heel strike -> midfoot -> lateral (meta5) -> medial roll-off -> toe.
constexpr Channel kSixChannels[6] = {
    {0.86f, 0.28f, 1700}, {0.70f, 0.36f, 2100}, {0.64f, 0.36f, 1900},
    {0.55f, 0.36f, 1500}, {0.40f, 0.40f, 900},  {0.16f, 0.32f, 2600},
};

constexpr float kBaselineAdc = 30;  // unloaded reading, just above offset_adc
constexpr float kNoiseAdc = 12;

Channel channelFor(uint8_t c, uint8_t fsrCount) {
  if (fsrCount == 6) return kSixChannels[c];
  // No position table exists for N != 6 yet (BACKLOG 15): spread the
  // channels evenly from toe (index 0) to heel (last index).
  float pos = fsrCount == 1 ? 0.5f : static_cast<float>(c) / (fsrCount - 1);
  return {0.86f - 0.70f * pos, 0.34f, 2000};
}

// Deterministic noise in [-1, 1] from (t, channel): no RNG state.
float noise(uint32_t t, uint32_t salt) {
  uint32_t x = t * 2654435761u ^ (salt + 1) * 2246822519u;
  x ^= x >> 15;
  x *= 2246822519u;
  x ^= x >> 13;
  return static_cast<float>(x & 0xffff) / 32767.5f - 1.0f;
}

int16_t clampI16(float v) {
  if (v > 32767) return 32767;
  if (v < -32768) return -32768;
  return static_cast<int16_t>(std::lround(v));
}

// Phase within the stride, 0..1. The right foot runs half a stride behind.
float phase(uint32_t tMs, uint8_t footSide) {
  uint32_t shifted = tMs + (footSide == 1 ? kGaitCycleMs / 2 : 0);
  return static_cast<float>(shifted % kGaitCycleMs) / kGaitCycleMs;
}

}  // namespace

Sample gaitSample(uint32_t tMs, uint8_t footSide, uint8_t fsrCount) {
  Sample s = {};
  float ph = phase(tMs, footSide);
  bool stance = ph < kStanceFraction;
  float st = ph / kStanceFraction;  // 0..1 through stance

  for (uint8_t c = 0; c < fsrCount && c < kMaxFsrCount; ++c) {
    float adc = kBaselineAdc + kNoiseAdc * noise(tMs, c);
    if (stance) {
      Channel ch = channelFor(c, fsrCount);
      float d = (st - ch.center) / ch.width;
      if (d > -0.5f && d < 0.5f) adc += ch.peakAdc * 0.5f * (1 + std::cos(2 * kPi * d));
    }
    if (adc < 0) adc = 0;
    if (adc > 4095) adc = 4095;
    s.fsr[c] = static_cast<uint16_t>(std::lround(adc));
  }

  // IMU: about 1 g down while standing; a heel-strike jolt at stance start;
  // forward swing in the swing phase. Enough motion to pass a walking gate.
  float sw = stance ? 0 : (ph - kStanceFraction) / (1 - kStanceFraction);
  float az = 1.0f, ax = 0, ay = 0, gy = 0;
  if (stance) {
    if (st < 0.08f) az += 0.9f * std::sin(kPi * st / 0.08f);
    ax = 0.10f * std::sin(2 * kPi * st);
  } else {
    az += 0.35f * std::sin(2 * kPi * sw);
    ax = 0.45f * std::sin(kPi * sw);
    gy = 220.0f * std::sin(kPi * sw);  // deg/s, shank swing
  }
  ay = 0.05f * std::sin(2 * kPi * ph);
  s.accel[0] = clampI16((ax + 0.02f * noise(tMs, 100)) * 4096);
  s.accel[1] = clampI16((ay + 0.02f * noise(tMs, 101)) * 4096);
  s.accel[2] = clampI16((az + 0.02f * noise(tMs, 102)) * 4096);
  s.gyro[0] = clampI16((15.0f * std::sin(2 * kPi * ph) + 2 * noise(tMs, 103)) * 32.8f);
  s.gyro[1] = clampI16((gy + 2 * noise(tMs, 104)) * 32.8f);
  s.gyro[2] = clampI16((8.0f * std::cos(2 * kPi * ph) + 2 * noise(tMs, 105)) * 32.8f);
  return s;
}

TemperatureReading temperature(uint32_t tMs, uint8_t footSide) {
  // Slow 10-minute drift. Right forefoot sits 0.4 degC warmer, well under
  // the 2.2 degC delta-T threshold, so no TEMP_DELTA from normal running.
  float drift = std::sin(2 * kPi * static_cast<float>(tMs % 600000u) / 600000.0f);
  float fore = 3180 + 30 * drift + (footSide == 1 ? 40 : 0);
  float heel = 3120 + 20 * drift + (footSide == 1 ? 25 : 0);
  return {clampI16(fore), clampI16(heel), 0};
}

BatteryReading battery(uint32_t tMs) {
  uint32_t used = tMs / kMsPerBatteryPct;
  uint8_t pct = used >= 100u - kBatteryFloorPct ? kBatteryFloorPct
                                                : static_cast<uint8_t>(100u - used);
  return {pct, static_cast<uint16_t>(3600 + 6 * pct)};  // 50 % = 3900 mV, 100 % = 4200 mV
}

const DataSource& walking() {
  static const DataSource source{gaitSample, temperature, battery};
  return source;
}

}  // namespace insole::synth

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

// Contract v1.6 FSR order (shared/sensor_layout.json): 0 hallux, 1 MTH1,
// 2 MTH2-3, 3 MTH5, 4 lateral midfoot, 5 heel centre, 6 medial arch,
// 7 lateral heel. Heel strike (lateral heel, heel centre) -> midfoot and a
// light medial-arch load in mid-stance -> lateral (MTH5) -> medial roll-off
// -> toe. Normal walking stays below the app's watch level
// (shared/thresholds.json pressure.watchKpa = 75) with margin. With the
// served calibration (contract §5.1 example) the peaks are about hallux 40,
// MTH1 50, MTH2-3 45, MTH5 32, midfoot 24, heel centre 60, medial arch 16
// and lateral heel 49 kPa, including baseline and noise. Higher pressure
// belongs to a scenario (BACKLOG 18). The midfoot is wide enough to carry
// the load from heel to forefoot: the summed kPa stays above the app's
// steps.contactKpa through the stance, so each stance is one step (S8A; a
// narrower midfoot split it into a blip and a shorter step). Indexes 0-5
// are the pre-v1.6 six-channel walk unchanged (the left_fsr6 env).
constexpr Channel kChannels[kMaxFsrCount] = {
    {0.86f, 0.28f, 1500}, {0.70f, 0.36f, 1710}, {0.64f, 0.36f, 1610},
    {0.55f, 0.36f, 1300}, {0.38f, 0.48f, 1100}, {0.16f, 0.32f, 1880},
    {0.40f, 0.40f, 800},  {0.13f, 0.30f, 1700},
};

constexpr float kBaselineAdc = 30;  // unloaded reading, just above offset_adc
constexpr float kNoiseAdc = 12;

Channel channelFor(uint8_t c, uint8_t fsrCount) {
  if (fsrCount == 6 || fsrCount == kMaxFsrCount) return kChannels[c];
  // Any other N (build checks only; the app refuses N != 8): spread the
  // channels evenly from toe (index 0) to heel (last index).
  float pos = fsrCount == 1 ? 0.5f : static_cast<float>(c) / (fsrCount - 1);
  return {0.86f - 0.70f * pos, 0.34f, 1610};  // about 45 kPa
}

// Resting sole temperature per site, 0.01 degC (index = FSR channel): the
// medial arch warmest, toes and heel coolest.
constexpr int16_t kSiteBaseCentiC[kTempSiteCount] = {
    3150, 3180, 3190, 3160, 3200, 3120, 3240, 3100,
};

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
  // forward swing in the swing phase; scaled by kWalkMotionScale.
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
  const float k = kWalkMotionScale;
  s.accel[0] = clampI16((k * ax + 0.02f * noise(tMs, 100)) * 4096);
  s.accel[1] = clampI16((k * ay + 0.02f * noise(tMs, 101)) * 4096);
  s.accel[2] = clampI16((1 + k * (az - 1) + 0.02f * noise(tMs, 102)) * 4096);
  s.gyro[0] = clampI16((15.0f * std::sin(2 * kPi * ph) + 2 * noise(tMs, 103)) * 32.8f);
  s.gyro[1] = clampI16((gy + 2 * noise(tMs, 104)) * 32.8f);
  s.gyro[2] = clampI16((8.0f * std::cos(2 * kPi * ph) + 2 * noise(tMs, 105)) * 32.8f);
  return s;
}

TemperatureReading temperature(uint32_t tMs, uint8_t footSide) {
  // Slow 10-minute drift, the same on both feet. The right foot sits
  // 0.25-0.40 degC warmer (forefoot sites most), well under the 2.2 degC
  // delta-T threshold, so no TEMP_DELTA from normal running.
  float drift = std::sin(2 * kPi * static_cast<float>(tMs % 600000u) / 600000.0f);
  TemperatureReading r = {};
  for (uint8_t i = 0; i < kTempSiteCount; ++i) {
    float rightWarmer = footSide == 1 ? (i <= 3 ? 40 : 25) : 0;
    r.temp[i] = clampI16(kSiteBaseCentiC[i] + 30 * drift + rightWarmer);
    r.quality[i] = 0;
  }
  return r;
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

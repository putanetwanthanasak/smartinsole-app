// Serial-command scenarios (S7 phone check): each must raise its alert in
// the app, read the app's way, with shared/thresholds.json's numbers.
#include <ArduinoJson.h>
#include <unity.h>

#include <cmath>
#include <fstream>
#include <vector>

#include "scenario.h"
#include "synth.h"

using namespace insole;

namespace {

JsonDocument gThresholds;

double th(const char* block, const char* key) { return gThresholds[block][key].as<double>(); }

// Contract §5.1 with the served calibration, as in test_synth.cpp.
double kpa(uint16_t adc) {
  int corrected = adc > 12 ? adc - 12 : 0;
  double v = (corrected < 1 ? 1 : corrected) / 4095.0 * 3.3;
  double r = 10000 * (3.3 - v) / v;
  if (r < 1e-6) r = 1e-6;
  return 123000 * std::pow(r, -1.05) / 0.000113 / 1000;
}

double accelDev(const Sample& s) {
  double x = s.accel[0] / 4096.0, y = s.accel[1] / 4096.0, z = s.accel[2] / 4096.0;
  return std::fabs(std::sqrt(x * x + y * y + z * z) - 1);
}

// The app's walking gate (mobile/lib/rules/walking_gate.dart): the lowest
// mean |a| - 1 g over any walkingWindowMs window of a minute's walk.
double lowestGateMean(Sample (*sample)(uint32_t, uint8_t, uint8_t), uint8_t side) {
  const int window = static_cast<int>(th("motion", "walkingWindowMs")) / kSamplePeriodMs;
  std::vector<double> dev;
  for (uint32_t t = 0; t < 60000; t += kSamplePeriodMs) dev.push_back(accelDev(sample(t, side, 6)));
  double lowest = 1e9;
  for (size_t i = 0; i + window <= dev.size(); ++i) {
    double sum = 0;
    for (int k = 0; k < window; ++k) sum += dev[i + k];
    lowest = std::fmin(lowest, sum / window);
  }
  return lowest;
}

void test_commands() {
  scenario::Id id = scenario::Id::normal;
  TEST_ASSERT_TRUE(scenario::fromCommand('t', &id));
  TEST_ASSERT_TRUE(id == scenario::Id::warmForefoot);
  TEST_ASSERT_TRUE(scenario::fromCommand('p', &id));
  TEST_ASSERT_TRUE(id == scenario::Id::highMeta1);
  TEST_ASSERT_TRUE(scenario::fromCommand('n', &id));
  TEST_ASSERT_TRUE(id == scenario::Id::normal);
  TEST_ASSERT_FALSE(scenario::fromCommand('?', &id));
  TEST_ASSERT_FALSE(scenario::fromCommand('\n', &id));
  TEST_ASSERT_TRUE(id == scenario::Id::normal);
}

void test_normal_is_the_walk_unchanged() {
  for (uint32_t t = 0; t < 5000; t += 20) {
    Sample a = scenario::source(scenario::Id::normal).sample(t, 0, 6);
    Sample b = synth::gaitSample(t, 0, 6);
    TEST_ASSERT_EQUAL_MEMORY(&b, &a, sizeof a);
  }
  TEST_ASSERT_EQUAL_PTR(&synth::walking(), &scenario::source(scenario::Id::normal));
}

void test_warm_forefoot_is_above_delta_c() {
  // TEMP_DELTA: |dT| > temperature.deltaC; the other board stays normal.
  double deltaC = th("temperature", "deltaC");
  for (uint8_t side : {0, 1}) {
    for (uint32_t t = 0; t < 3600000; t += 30000) {
      TemperatureReading warm = scenario::warmTemperature(t, side);
      TemperatureReading other = synth::temperature(t, 1 - side);
      TemperatureReading plain = synth::temperature(t, side);
      TEST_ASSERT_EQUAL(plain.forefoot + scenario::kWarmForefootCentiC, warm.forefoot);
      TEST_ASSERT_EQUAL(plain.heel, warm.heel);
      TEST_ASSERT_EQUAL(0, warm.quality);
      TEST_ASSERT_TRUE(std::abs(warm.forefoot - other.forefoot) / 100.0 > deltaC + 0.3);
    }
  }
}

void test_high_meta1_peak_pti_and_gate() {
  double alertKpa = th("pressure", "alertKpa");
  double ptiKpaS = th("pressure", "ptiKpaS");
  double contact = th("steps", "contactKpa");
  double minStance = th("steps", "minStanceMs"), maxStance = th("steps", "maxStanceMs");
  double gateG = th("motion", "walkingAccelG");
  TEST_ASSERT_TRUE(alertKpa > 0 && ptiKpaS > 0 && gateG > 0);
  for (uint8_t side : {0, 1}) {
    // Every stride: meta1 peaks between alertKpa and the scale's top, and
    // its pressure-time integral per stance is above ptiKpaS.
    double peak = 0, pti = 0, prev = -1;
    bool inStance = false;
    int steps = 0;
    uint32_t stanceStart = 0;
    for (uint32_t t = 0; t < 60000; t += kSamplePeriodMs) {
      Sample s = scenario::highMeta1Sample(t, side, 6);
      double sum = 0;
      for (int c = 0; c < 6; ++c) sum += kpa(s.fsr[c]);
      double m1 = kpa(s.fsr[1]);
      TEST_ASSERT_TRUE(s.fsr[1] < 4095);
      if (sum > contact) {
        if (!inStance) inStance = true, stanceStart = t, peak = 0, pti = 0, prev = -1;
        peak = std::fmax(peak, m1);
        if (prev >= 0) pti += (prev + m1) / 2 * kSamplePeriodMs / 1000.0;
        prev = m1;
      } else if (inStance) {
        inStance = false;
        double len = t - stanceStart;
        if (stanceStart == 0) continue;  // the first, cut-off stance
        ++steps;
        char msg[96];
        snprintf(msg, sizeof msg, "side %u step %d: %.0f ms, peak %.1f kPa, PTI %.1f kPa*s",
                 side, steps, len, peak, pti);
        TEST_ASSERT_TRUE_MESSAGE(len >= minStance && len <= maxStance, msg);
        TEST_ASSERT_TRUE_MESSAGE(peak > alertKpa + 25 && peak < 280, msg);
        TEST_ASSERT_TRUE_MESSAGE(pti > 1.2 * ptiKpaS, msg);
      }
    }
    TEST_ASSERT_TRUE(steps >= 50);
    // The walking gate is on through every window, with margin.
    double lowest = lowestGateMean(scenario::highMeta1Sample, side);
    char msg[64];
    snprintf(msg, sizeof msg, "side %u lowest gate mean %.3f g", side, lowest);
    TEST_ASSERT_TRUE_MESSAGE(lowest > gateG + 0.04, msg);
    // Accel stays inside the +-8 g range (no clamping).
    for (uint32_t t = 0; t < 1100; t += 20) {
      Sample s = scenario::highMeta1Sample(t, side, 6);
      for (int a = 0; a < 3; ++a) TEST_ASSERT_TRUE(std::abs(s.accel[a]) < 32000);
    }
  }
}

void test_high_meta1_other_channels_unchanged() {
  for (uint32_t t = 0; t < 5000; t += 20) {
    Sample a = scenario::highMeta1Sample(t, 0, 6), b = synth::gaitSample(t, 0, 6);
    for (int c = 0; c < 6; ++c) {
      if (c != 1) TEST_ASSERT_EQUAL(b.fsr[c], a.fsr[c]);
    }
    TEST_ASSERT_TRUE(a.fsr[1] >= b.fsr[1]);
    TEST_ASSERT_EQUAL_MEMORY(b.gyro, a.gyro, sizeof a.gyro);
  }
}

void test_normal_walk_gate_figure() {
  // Not a pass/fail: records the normal walk's lowest gate mean for the
  // S7 report (the normal walk is gentler than the app's gate).
  char msg[80];
  snprintf(msg, sizeof msg, "normal walk lowest gate mean: L %.3f g, R %.3f g (gate %.2f g)",
           lowestGateMean(synth::gaitSample, 0), lowestGateMean(synth::gaitSample, 1),
           th("motion", "walkingAccelG"));
  TEST_MESSAGE(msg);
}

}  // namespace

void setUp() {}
void tearDown() {}

int main() {
  std::ifstream in(THRESHOLDS_JSON);
  if (deserializeJson(gThresholds, in)) return 1;
  UNITY_BEGIN();
  RUN_TEST(test_commands);
  RUN_TEST(test_normal_is_the_walk_unchanged);
  RUN_TEST(test_warm_forefoot_is_above_delta_c);
  RUN_TEST(test_high_meta1_peak_pti_and_gate);
  RUN_TEST(test_high_meta1_other_channels_unchanged);
  RUN_TEST(test_normal_walk_gate_figure);
  return UNITY_END();
}

// Synthetic data models and the calibration blob.
#include <ArduinoJson.h>
#include <unity.h>

#include <cmath>
#include <cstring>
#include <fstream>

#include "calibration.h"
#include "synth.h"

using namespace insole;

namespace {

void test_adc_in_range_and_walking_shape() {
  for (uint8_t n : {4, 6, 8}) {
    for (uint8_t side : {0, 1}) {
      uint16_t peak[kMaxFsrCount] = {};
      uint16_t low[kMaxFsrCount];
      for (auto& v : low) v = 4095;
      for (uint32_t t = 0; t < 60000; t += kSamplePeriodMs) {
        Sample s = synth::gaitSample(t, side, n);
        for (uint8_t c = 0; c < n; ++c) {
          TEST_ASSERT_TRUE(s.fsr[c] <= 4095);
          if (s.fsr[c] > peak[c]) peak[c] = s.fsr[c];
          if (s.fsr[c] < low[c]) low[c] = s.fsr[c];
        }
        for (uint8_t c = n; c < kMaxFsrCount; ++c) TEST_ASSERT_EQUAL(0, s.fsr[c]);
      }
      for (uint8_t c = 0; c < n; ++c) {
        TEST_ASSERT_TRUE(peak[c] > 800);  // every channel is loaded in stance
        TEST_ASSERT_TRUE(peak[c] < 4095); // and never saturates
        TEST_ASSERT_TRUE(low[c] < 60);    // and unloads in swing
      }
    }
  }
}

// Contract §5.1 conversion with the served calibration (r_pulldown 10 kOhm,
// area 0.000113 m2, a 123000, b -1.05, offset_adc 12), in the TS/Dart order.
double kpa(uint16_t adc) {
  int corrected = adc > 12 ? adc - 12 : 0;
  double v = (corrected < 1 ? 1 : corrected) / 4095.0 * 3.3;
  double r = 10000 * (3.3 - v) / v;
  if (r < 1e-6) r = 1e-6;
  return 123000 * std::pow(r, -1.05) / 0.000113 / 1000;
}

void test_normal_walk_stays_below_watch_kpa() {
  std::ifstream in(THRESHOLDS_JSON);
  JsonDocument doc;
  TEST_ASSERT_FALSE(deserializeJson(doc, in));
  double watch = doc["pressure"]["watchKpa"].as<double>();
  TEST_ASSERT_TRUE(watch > 0);
  double limit = 0.85 * watch;  // margin: 63.75 kPa at watchKpa 75
  for (uint8_t n : {4, 6, 8}) {
    for (uint8_t side : {0, 1}) {
      double peak = 0;
      for (uint32_t t = 0; t < 600000; t += kSamplePeriodMs) {
        Sample s = synth::gaitSample(t, side, n);
        for (uint8_t c = 0; c < n; ++c) peak = std::fmax(peak, kpa(s.fsr[c]));
      }
      char msg[64];
      snprintf(msg, sizeof msg, "N=%u side=%u peak %.1f kPa", n, side, peak);
      TEST_ASSERT_TRUE_MESSAGE(peak < limit, msg);
      if (n >= 6) TEST_ASSERT_TRUE_MESSAGE(peak > 50, msg);  // heel still clearly loaded
    }
  }
}

void test_deterministic() {
  for (uint32_t t = 0; t < 5000; t += 20) {
    Sample a = synth::gaitSample(t, 1, 8), b = synth::gaitSample(t, 1, 8);
    TEST_ASSERT_EQUAL_MEMORY(&a, &b, sizeof a);
  }
}

void test_feet_alternate() {
  // Heel (index 5) peaks half a stride apart on the two feet.
  auto peakAt = [](uint8_t side) {
    uint32_t best = 0;
    uint16_t v = 0;
    for (uint32_t t = 0; t < synth::kGaitCycleMs; t += 10) {
      uint16_t h = synth::gaitSample(t, side, 8).fsr[5];
      if (h > v) v = h, best = t;
    }
    return best;
  };
  uint32_t d = (peakAt(0) + synth::kGaitCycleMs - peakAt(1)) % synth::kGaitCycleMs;
  TEST_ASSERT_UINT32_WITHIN(40, synth::kGaitCycleMs / 2, d);
}

void test_accel_moves_enough_to_be_walking() {
  // The app's walking gate (contract 8.3.2, mobile/lib/rules/
  // walking_gate.dart): mean |a| - 1 g over motion.walkingWindowMs must
  // reach motion.walkingAccelG. Every window of a minute's walk, both feet.
  std::ifstream in(THRESHOLDS_JSON);
  JsonDocument doc;
  TEST_ASSERT_FALSE(deserializeJson(doc, in));
  const double gate = doc["motion"]["walkingAccelG"].as<double>();
  const int window = doc["motion"]["walkingWindowMs"].as<int>() / 20;
  TEST_ASSERT_TRUE(gate > 0 && window > 0);
  for (uint8_t side : {0, 1}) {
    double dev[3000];
    int n = 0;
    for (uint32_t t = 0; t < 60000; t += 20, ++n) {
      Sample s = synth::gaitSample(t, side, 8);
      double g = std::sqrt(double(s.accel[0]) * s.accel[0] + double(s.accel[1]) * s.accel[1] +
                           double(s.accel[2]) * s.accel[2]) / 4096.0;
      dev[n] = std::fabs(g - 1);
    }
    double lowest = 1e9;
    for (int i = 0; i + window <= n; ++i) {
      double sum = 0;
      for (int k = 0; k < window; ++k) sum += dev[i + k];
      lowest = std::fmin(lowest, sum / window);
    }
    char msg[64];
    snprintf(msg, sizeof msg, "side %u lowest gate mean %.3f g", side, lowest);
    TEST_ASSERT_TRUE_MESSAGE(lowest >= gate, msg);
  }
}

void test_temperature_plausible_and_below_delta_threshold() {
  for (uint32_t t = 0; t < 3600000; t += 30000) {
    TemperatureReading l = synth::temperature(t, 0), r = synth::temperature(t, 1);
    for (uint8_t i = 0; i < kTempSiteCount; ++i) {
      TEST_ASSERT_INT_WITHIN(200, 3170, l.temp[i]);
      TEST_ASSERT_INT_WITHIN(200, 3170, r.temp[i]);
      TEST_ASSERT_EQUAL(0, l.quality[i]);
      TEST_ASSERT_EQUAL(0, r.quality[i]);
      TEST_ASSERT_TRUE(std::abs(r.temp[i] - l.temp[i]) < 220);  // < 2.2 degC
    }
  }
}

void test_eight_channel_anatomy() {
  // Lateral heel (7) loads at heel strike with the heel centre (5), before
  // the medial arch (6), which carries a light mid-stance load (< 25 kPa).
  auto peakTime = [](uint8_t c) {
    uint32_t best = 0;
    uint16_t v = 0;
    for (uint32_t t = 0; t < synth::kGaitCycleMs; t += 10) {
      uint16_t a = synth::gaitSample(t, 0, 8).fsr[c];
      if (a > v) v = a, best = t;
    }
    return best;
  };
  TEST_ASSERT_TRUE(peakTime(7) < peakTime(6));
  TEST_ASSERT_UINT32_WITHIN(60, peakTime(5), peakTime(7));
  TEST_ASSERT_TRUE(peakTime(6) < peakTime(1));
  double arch = 0, lateralHeel = 0;
  for (uint32_t t = 0; t < 60000; t += kSamplePeriodMs) {
    Sample s = synth::gaitSample(t, 0, 8);
    arch = std::fmax(arch, kpa(s.fsr[6]));
    lateralHeel = std::fmax(lateralHeel, kpa(s.fsr[7]));
  }
  TEST_ASSERT_TRUE(arch > 10 && arch < 25);
  TEST_ASSERT_TRUE(lateralHeel > 40 && lateralHeel < 60);
  // Indexes 0-5 of the 8-channel walk are the 6-channel walk unchanged.
  for (uint32_t t = 0; t < 5000; t += 20) {
    Sample a = synth::gaitSample(t, 0, 6), b = synth::gaitSample(t, 0, 8);
    for (int c = 0; c < 6; ++c) TEST_ASSERT_EQUAL(a.fsr[c], b.fsr[c]);
  }
}

void test_battery_never_below_50() {
  TEST_ASSERT_EQUAL(100, synth::battery(0).pct);
  TEST_ASSERT_EQUAL(4200, synth::battery(0).mv);
  uint8_t prev = 100;
  for (uint64_t t = 0; t <= 48ull * 3600 * 1000; t += 60000) {
    BatteryReading b = synth::battery(static_cast<uint32_t>(t));
    TEST_ASSERT_TRUE(b.pct >= synth::kBatteryFloorPct);
    TEST_ASSERT_TRUE(b.pct <= prev);
    TEST_ASSERT_EQUAL(3600 + 6 * b.pct, b.mv);
    prev = b.pct;
  }
  TEST_ASSERT_EQUAL(50, prev);
  TEST_ASSERT_EQUAL(50, synth::battery(UINT32_MAX).pct);  // millis() wrap, ~49.7 days
}

void test_calibration_json() {
  uint16_t defaults[kMaxFsrCount];
  for (auto& o : defaults) o = kDefaultOffsetAdc;
  for (uint8_t n : {1, 4, 6, 8}) {
    char buf[600] = {};
    size_t len = buildCalibrationJson(buf, sizeof buf, "SIM-L-001", n, defaults);
    TEST_ASSERT_TRUE(len > 0 && len <= kMaxCalibrationBytes);
    JsonDocument doc;
    TEST_ASSERT_FALSE(deserializeJson(doc, buf, len));
    TEST_ASSERT_EQUAL_STRING("SIM-L-001", doc["device_id"]);
    TEST_ASSERT_EQUAL(10000, doc["r_pulldown_ohm"].as<int>());
    // ArduinoJson keeps short decimals as float, so check the served text.
    TEST_ASSERT_NOT_NULL(strstr(buf, "\"sensor_area_m2\":0.000113,"));
    JsonArray ch = doc["channels"];
    TEST_ASSERT_EQUAL(n, ch.size());
    for (uint8_t i = 0; i < n; ++i) {
      TEST_ASSERT_EQUAL(i, ch[i]["index"].as<int>());
      TEST_ASSERT_EQUAL_DOUBLE(123000, ch[i]["a"].as<double>());
      TEST_ASSERT_DOUBLE_WITHIN(1e-6, -1.05, ch[i]["b"].as<double>());
      TEST_ASSERT_EQUAL(12, ch[i]["offset_adc"].as<int>());
    }
    if (n >= 6) TEST_ASSERT_TRUE(len > kTargetMtu - kAttHeaderBytes);  // a long read
  }
  char small[64];
  TEST_ASSERT_EQUAL(0, buildCalibrationJson(small, sizeof small, "SIM-L-001", 6, defaults));
}

void test_calibration_json_tared_offsets() {
  // Per-channel offsets are served as given; the widest case (N = 8,
  // four-digit offsets) still fits the 512-byte characteristic.
  uint16_t offsets[kMaxFsrCount] = {0, 18, 19, 20, 21, 22, 4095, 4095};
  for (uint8_t n : {6, 8}) {
    char buf[600] = {};
    size_t len = buildCalibrationJson(buf, sizeof buf, "SIM-R-001", n, offsets);
    TEST_ASSERT_TRUE(len > 0 && len <= kMaxCalibrationBytes);
    JsonDocument doc;
    TEST_ASSERT_FALSE(deserializeJson(doc, buf, len));
    JsonArray ch = doc["channels"];
    TEST_ASSERT_EQUAL(n, ch.size());
    for (uint8_t i = 0; i < n; ++i) TEST_ASSERT_EQUAL(offsets[i], ch[i]["offset_adc"].as<int>());
  }
}

}  // namespace

void setUp() {}
void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_adc_in_range_and_walking_shape);
  RUN_TEST(test_normal_walk_stays_below_watch_kpa);
  RUN_TEST(test_deterministic);
  RUN_TEST(test_feet_alternate);
  RUN_TEST(test_accel_moves_enough_to_be_walking);
  RUN_TEST(test_temperature_plausible_and_below_delta_threshold);
  RUN_TEST(test_eight_channel_anatomy);
  RUN_TEST(test_battery_never_below_50);
  RUN_TEST(test_calibration_json);
  RUN_TEST(test_calibration_json_tared_offsets);
  return UNITY_END();
}

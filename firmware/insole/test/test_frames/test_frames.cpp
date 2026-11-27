// What the real insole adds around the simulator core: the no-NTC
// temperature packet (checked against shared/test_vectors), the no-battery
// status, sample assembly, and the saturated flag at the C3's ceiling.
#include <unity.h>

#include <ArduinoJson.h>

#include <fstream>
#include <sstream>
#include <string>

#include "insole_frames.h"

using namespace insole;
using namespace insole_hw;

void setUp() {}
void tearDown() {}

namespace {

std::string hex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; ++i) {
    s += d[p[i] >> 4];
    s += d[p[i] & 15];
  }
  return s;
}

JsonDocument vectors(const char* file) {
  std::ifstream in(std::string(VECTORS_DIR) + "/" + file);
  TEST_ASSERT_TRUE_MESSAGE(in.good(), file);
  std::stringstream ss;
  ss << in.rdbuf();
  JsonDocument doc;
  TEST_ASSERT_FALSE(deserializeJson(doc, ss.str()));
  return doc;
}

uint16_t counts[kCalChannels] = {65, 120, 300, 888, 400, 50};
const int16_t kAccel[3] = {10, 20, 4096};
const int16_t kGyro[3] = {-3, 4, 5};

}  // namespace

void test_no_ntc_matches_vector() {
  JsonDocument doc = vectors("temperature_v2.json");
  const char* want = nullptr;
  for (JsonObject c : doc["cases"].as<JsonArray>())
    if (std::string(c["name"].as<const char*>()) == "unreadable_all") want = c["hex"];
  TEST_ASSERT_NOT_NULL(want);
  uint8_t out[kTemperatureBytes];
  size_t n = encodeTemperature(out, 5, 150000, noNtcReading());  // the vector's seq and t_ms
  TEST_ASSERT_EQUAL(26, n);
  TEST_ASSERT_EQUAL_STRING(want, hex(out, n).c_str());
}

void test_no_battery_status() {
  DeviceStatus st{kBatteryExternalPct, kBatteryExternalMv, 1, 0, 2, DeviceState::Idle, 0};
  uint8_t out[kStatusBytes];
  TEST_ASSERT_EQUAL(8, encodeStatus(out, st));
  TEST_ASSERT_EQUAL_STRING("ff00000100020000", hex(out, 8).c_str());
}

void test_make_sample() {
  constexpr AxisMap turned{{1, 0, 2}, {1, -1, 1}};
  Sample s = makeSample(counts, kAccel, kGyro, turned);
  for (uint8_t c = 0; c < kCalChannels; ++c) TEST_ASSERT_EQUAL_UINT16(counts[c], s.fsr[c]);
  TEST_ASSERT_EQUAL_INT16(20, s.accel[0]);
  TEST_ASSERT_EQUAL_INT16(-10, s.accel[1]);
  TEST_ASSERT_EQUAL_INT16(4096, s.accel[2]);
  TEST_ASSERT_EQUAL_INT16(4, s.gyro[0]);
  TEST_ASSERT_EQUAL_INT16(3, s.gyro[1]);
  TEST_ASSERT_EQUAL_INT16(5, s.gyro[2]);
}

void test_saturated_flag_per_packet() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  TEST_ASSERT_TRUE(s.start(0));
  SaturationFlag flag;
  OutPacket out;
  Sample smp = makeSample(counts, kAccel, kGyro, kIdentityAxes);
  uint32_t t = 0;
  // Packet 0: sample 3 hit the ceiling.
  for (int i = 0; i < 8; ++i, t += 20) {
    bool ready = flag.add(s, smp, i == 3, t, kCalChannels, out, false);
    TEST_ASSERT_EQUAL(i == 7, ready);
  }
  TEST_ASSERT_EQUAL(200, out.len);
  TEST_ASSERT_EQUAL_HEX8(kFlagSaturated, out.bytes[7]);
  // Packet 1: nothing saturated.
  for (int i = 0; i < 8; ++i, t += 20) flag.add(s, smp, false, t, kCalChannels, out, false);
  TEST_ASSERT_EQUAL_HEX8(0, out.bytes[7]);
  TEST_ASSERT_EQUAL(1, out.bytes[0]);  // seq 1
}

void test_saturated_with_calibrating_keeps_both_bits() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  SaturationFlag flag;
  OutPacket out;
  Sample smp = makeSample(counts, kAccel, kGyro, kIdentityAxes);
  for (int i = 0; i < 8; ++i) flag.add(s, smp, i == 0, 20 * i, kCalChannels, out, i == 5);
  TEST_ASSERT_EQUAL_HEX8(kFlagSaturated | kFlagCalibrating, out.bytes[7]);
}

void test_stop_and_mtu_drop_clear_the_flag() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  SaturationFlag flag;
  OutPacket out;
  Sample smp = makeSample(counts, kAccel, kGyro, kIdentityAxes);
  flag.add(s, smp, true, 0, kCalChannels, out, false);  // half a packet, saturated
  s.stop();
  flag.reset();  // ble_server does this on STOP
  s.start(1000);
  for (int i = 0; i < 8; ++i) flag.add(s, smp, false, 1000 + 20 * i, kCalChannels, out, false);
  TEST_ASSERT_EQUAL_HEX8(0, out.bytes[7]);

  // A packet dropped because the MTU shrank mid-fill takes its flag with it.
  for (int i = 0; i < 7; ++i) flag.add(s, smp, i == 0, 2000 + 20 * i, kCalChannels, out, false);
  s.mtu = 202;  // 200 no longer fits; the 8th sample completes and drops it
  TEST_ASSERT_FALSE(flag.add(s, smp, false, 2140, kCalChannels, out, false));
  s.mtu = 247;
  for (int i = 0; i < 8; ++i) flag.add(s, smp, false, 3000 + 20 * i, kCalChannels, out, false);
  TEST_ASSERT_EQUAL_HEX8(0, out.bytes[7]);
}

void test_not_streaming_does_nothing() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  SaturationFlag flag;
  OutPacket out;
  Sample smp = makeSample(counts, kAccel, kGyro, kIdentityAxes);
  TEST_ASSERT_FALSE(flag.add(s, smp, true, 0, kCalChannels, out, false));
  s.start(0);
  for (int i = 0; i < 8; ++i) flag.add(s, smp, false, 20 * i, kCalChannels, out, false);
  TEST_ASSERT_EQUAL_HEX8(0, out.bytes[7]);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_no_ntc_matches_vector);
  RUN_TEST(test_no_battery_status);
  RUN_TEST(test_make_sample);
  RUN_TEST(test_saturated_flag_per_packet);
  RUN_TEST(test_saturated_with_calibrating_keeps_both_bits);
  RUN_TEST(test_stop_and_mtu_drop_clear_the_flag);
  RUN_TEST(test_not_streaming_does_nothing);
  return UNITY_END();
}

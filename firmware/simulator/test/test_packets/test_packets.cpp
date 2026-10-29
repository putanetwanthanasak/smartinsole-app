// Encoders vs shared/test_vectors/: every packet the simulator could send
// must reproduce the vector's hex byte-for-byte. The vectors were generated
// from the web app's hardware-verified TS parser (see the vectors' README).
#include <ArduinoJson.h>
#include <unity.h>

#include <cmath>
#include <cstdio>
#include <fstream>
#include <set>
#include <string>

#include "packets.h"

using namespace insole;

namespace {

// Vector cases that are not encoder outputs: inputs the parser must reject.
// The simulator never produces them (no truncation, no padding).
const std::set<std::string> kNotEncodable = {
    "extra_trailing_bytes",     // longer than count accounts for (lengthMismatch)
    "truncated_header_says_8",  // shorter than count accounts for
    "truncated_one_byte_short",
    "shorter_than_header",
    "empty",
    "n8_one_byte_short",
    "n8_extra_trailing_bytes",
    "reserved_nonzero_ignored",  // temperature v2: the simulator sends reserved 0
    "short_7_bytes",             // status
};

JsonDocument load(const char* file) {
  std::string path = std::string(VECTORS_DIR) + "/" + file;
  std::ifstream in(path);
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, in);
  if (err) TEST_FAIL_MESSAGE((path + ": " + err.c_str()).c_str());
  return doc;
}

std::string toHex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; ++i) {
    s += d[p[i] >> 4];
    s += d[p[i] & 15];
  }
  return s;
}

bool skip(JsonObject c, int& skipped) {
  const char* name = c["name"];
  if (kNotEncodable.count(name)) {
    ++skipped;
    return true;
  }
  return false;
}

void checkHex(JsonObject c, const std::string& got, int& checked) {
  std::string name = c["name"].as<const char*>();
  std::string want = c["hex"].as<const char*>();
  TEST_ASSERT_EQUAL_STRING_MESSAGE(want.c_str(), got.c_str(), name.c_str());
  ++checked;
}

void runSensorFile(const char* file, int expectedChecked) {
  JsonDocument doc = load(file);
  int checked = 0, skipped = 0;
  for (JsonObject c : doc["cases"].as<JsonArray>()) {
    if (skip(c, skipped)) continue;
    TEST_ASSERT_TRUE_MESSAGE(c["expected"]["rejected"].isNull(), c["name"]);
    uint8_t n = c["fsr_count"];
    JsonObject h = c["expected"]["header"];
    uint8_t count = h["count"];
    uint8_t flags = (h["saturated"].as<bool>() ? kFlagSaturated : 0) |
                    (h["calibrating"].as<bool>() ? kFlagCalibrating : 0);
    Sample samples[kSamplesPerPacket] = {};
    JsonArray js = c["expected"]["samples"];
    TEST_ASSERT_EQUAL_MESSAGE(count, js.size(), c["name"]);
    for (uint8_t i = 0; i < count; ++i) {
      for (uint8_t k = 0; k < n; ++k) samples[i].fsr[k] = js[i]["fsr_adc"][k];
      for (int k = 0; k < 3; ++k) samples[i].accel[k] = js[i]["accel_raw"][k];
      for (int k = 0; k < 3; ++k) samples[i].gyro[k] = js[i]["gyro_raw"][k];
      // Rule 1: sample i is t0 + i * 20.
      TEST_ASSERT_EQUAL_UINT32_MESSAGE(h["t0_ms"].as<uint32_t>() + i * kSamplePeriodMs,
                                       js[i]["t_ms"].as<uint32_t>(), c["name"]);
    }
    uint8_t buf[kMaxSensorPacketBytes];
    size_t len = encodeSensor(buf, h["seq"], h["t0_ms"], flags, samples, count, n);
    TEST_ASSERT_EQUAL_MESSAGE(sensorPacketSize(count, n), len, c["name"]);
    checkHex(c, toHex(buf, len), checked);
  }
  printf("%s: %d encoded and matched, %d not encodable (parser-reject cases)\n", file,
         checked, skipped);
  TEST_ASSERT_EQUAL_MESSAGE(expectedChecked, checked, file);
}

void test_sensor_n6() { runSensorFile("sensor.json", 15); }
void test_sensor_n4() { runSensorFile("sensor_n4.json", 3); }
void test_sensor_n8() { runSensorFile("sensor_n8.json", 6); }

int16_t centi(JsonVariant c) {
  return c.isNull() ? kTempUnreadable : static_cast<int16_t>(std::lround(c.as<double>() * 100));
}

// Temperature v2 (contract v1.6 §3.2). The v1 file (temperature.json) is
// no longer encodable: the simulator sends v2 only.
void test_temperature_v2() {
  JsonDocument doc = load("temperature_v2.json");
  int checked = 0, skipped = 0;
  for (JsonObject c : doc["cases"].as<JsonArray>()) {
    JsonObject e = c["expected"];
    if (!e["rejected"].isNull()) {
      ++skipped;  // a packet the app must refuse
      continue;
    }
    if (skip(c, skipped)) continue;
    TEST_ASSERT_EQUAL_MESSAGE(kTempSiteCount, e["count"].as<int>(), c["name"]);
    TemperatureReading r = {};
    for (uint8_t i = 0; i < kTempSiteCount; ++i) {
      r.temp[i] = centi(e["celsius"][i]);
      r.quality[i] = e["quality"][i];
    }
    uint8_t buf[kTemperatureBytes];
    size_t len = encodeTemperature(buf, e["seq"], e["t_ms"], r);
    TEST_ASSERT_EQUAL(32, len);
    checkHex(c, toHex(buf, len), checked);
  }
  printf("temperature_v2.json: %d matched, %d not encodable\n", checked, skipped);
  TEST_ASSERT_EQUAL(7, checked);
}

void test_status() {
  JsonDocument doc = load("status.json");
  int checked = 0, skipped = 0;
  for (JsonObject c : doc["cases"].as<JsonArray>()) {
    if (skip(c, skipped)) continue;
    JsonObject e = c["expected"];
    DeviceStatus s{e["battery_pct"], e["battery_mv"],  e["foot_side"],
                   e["fw_major"],    e["fw_minor"],    static_cast<DeviceState>(e["state"].as<uint8_t>()),
                   e["error_code"]};
    uint8_t buf[kStatusBytes];
    size_t len = encodeStatus(buf, s);
    TEST_ASSERT_EQUAL(kStatusBytes, len);
    checkHex(c, toHex(buf, len), checked);
  }
  printf("status.json: %d matched, %d not encodable\n", checked, skipped);
  TEST_ASSERT_EQUAL(13, checked);
}

void test_packet_sizes() {
  TEST_ASSERT_EQUAL(200, sensorPacketSize(8, 6));
  TEST_ASSERT_EQUAL(104, sensorPacketSize(4, 6));
  TEST_ASSERT_EQUAL(232, sensorPacketSize(8, 8));  // the v1.6 insole
  TEST_ASSERT_EQUAL(120, sensorPacketSize(4, 8));
  TEST_ASSERT_EQUAL(28, sampleSize(8));
  TEST_ASSERT_EQUAL(32, kTemperatureBytes);
  TEST_ASSERT_TRUE(kMaxSensorPacketBytes <= kTargetMtu - kAttHeaderBytes);
}

}  // namespace

void setUp() {}
void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_packet_sizes);
  RUN_TEST(test_sensor_n6);
  RUN_TEST(test_sensor_n4);
  RUN_TEST(test_sensor_n8);
  RUN_TEST(test_temperature_v2);
  RUN_TEST(test_status);
  return UNITY_END();
}

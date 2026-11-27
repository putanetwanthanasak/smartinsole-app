// Calibration JSON (contract §5.1, Appendix C item 4): compact, <= 512 bytes,
// 6 channels; strict parse for the serial `cal set` command.
#include <unity.h>

#include <ArduinoJson.h>

#include <cstring>
#include <string>

#include "cal_json.h"

using namespace insole_hw;

void setUp() {}
void tearDown() {}

namespace {

std::string build(const CalData& c) {
  char buf[kMaxCalibrationBytes + 1];
  size_t n = buildCalibrationJson(c, buf, sizeof buf);
  return std::string(buf, n);
}

CalError parse(const std::string& s, CalData& out) {
  return parseCalibration(s.c_str(), s.size(), out);
}

std::string replace(std::string s, const std::string& from, const std::string& to) {
  size_t i = s.find(from);
  TEST_ASSERT_TRUE_MESSAGE(i != std::string::npos, from.c_str());
  return s.replace(i, from.size(), to);
}

}  // namespace

void test_test_calibration_json() {
  CalData c = testCalibration(1, 1000, 0.000113);
  std::string j = build(c);
  TEST_ASSERT_TRUE(j.size() > 0 && j.size() <= kMaxCalibrationBytes);
  const std::string head =
      "{\"device_id\":\"INSOLE-R-TEST\",\"r_pulldown_ohm\":1000,\"sensor_area_m2\":0.000113,"
      "\"channels\":[{\"index\":0,\"a\":123000,\"b\":-1.05,\"offset_adc\":0}";
  TEST_ASSERT_EQUAL_STRING(head.c_str(), j.substr(0, head.size()).c_str());
  TEST_ASSERT_TRUE(j.find(' ') == std::string::npos);   // compact
  TEST_ASSERT_TRUE(j.find('\n') == std::string::npos);
  JsonDocument doc;
  TEST_ASSERT_FALSE(deserializeJson(doc, j));
  TEST_ASSERT_EQUAL(6, doc["channels"].size());
  TEST_ASSERT_EQUAL(5, doc["channels"][5]["index"].as<int>());
  TEST_ASSERT_TRUE(isTestCalibration(c));
  TEST_ASSERT_EQUAL_STRING("INSOLE-L-TEST", testCalibration(0, 1000, 0.000113).deviceId);
}

void test_round_trip() {
  CalData c = testCalibration(1, 1000, 0.000113);
  for (uint8_t i = 0; i < kCalChannels; ++i) {
    c.ch[i].a = 98765.4 + i;
    c.ch[i].b = -1.234;
    c.ch[i].offsetAdc = static_cast<uint16_t>(400 + 37 * i);
  }
  std::strcpy(c.deviceId, "INSOLE-R-001");
  std::string j = build(c);
  CalData back{};
  TEST_ASSERT_EQUAL(static_cast<int>(CalError::None), static_cast<int>(parse(j, back)));
  TEST_ASSERT_EQUAL_STRING(j.c_str(), build(back).c_str());
  TEST_ASSERT_EQUAL_DOUBLE(98770.4, back.ch[5].a);  // the correctly rounded double
  TEST_ASSERT_EQUAL_UINT16(585, back.ch[5].offsetAdc);
  TEST_ASSERT_FALSE(isTestCalibration(back));
}

void test_spaced_input_is_rebuilt_compact() {
  std::string j = build(testCalibration(1, 1000, 0.000113));
  std::string spaced = replace(replace(j, "{\"device_id\"", "{\n  \"device_id\""), ",\"channels\"",
                               ",\n  \"channels\"");
  CalData c{};
  TEST_ASSERT_EQUAL(static_cast<int>(CalError::None), static_cast<int>(parse(spaced, c)));
  TEST_ASSERT_EQUAL_STRING(j.c_str(), build(c).c_str());
}

void test_refusals() {
  const std::string ok = build(testCalibration(1, 1000, 0.000113));
  CalData c{};
  auto expect = [&](CalError e, const std::string& s) {
    TEST_ASSERT_EQUAL_MESSAGE(static_cast<int>(e), static_cast<int>(parse(s, c)), s.c_str());
  };
  expect(CalError::NotJson, ok.substr(0, 300));                       // cut off (report 042, L1)
  expect(CalError::NotObject, "[1,2]");
  expect(CalError::UnknownKey, replace(ok, "{\"device_id\"", "{\"note\":1,\"device_id\""));
  expect(CalError::UnknownKey, replace(ok, "\"offset_adc\":0}]", "\"offset_adc\":0,\"x\":1}]"));
  expect(CalError::DeviceId, replace(ok, "INSOLE-R-TEST", ""));
  expect(CalError::DeviceId, replace(ok, "INSOLE-R-TEST", "A\\\"B"));
  expect(CalError::Pulldown, replace(ok, "\"r_pulldown_ohm\":1000", "\"r_pulldown_ohm\":1000.5"));
  expect(CalError::Pulldown, replace(ok, "\"r_pulldown_ohm\":1000", "\"r_pulldown_ohm\":0"));
  expect(CalError::Area, replace(ok, "0.000113", "0"));
  expect(CalError::Area, replace(ok, "0.000113", "\"x\""));
  // 5 channels, or v1.6's 8 (N != 6 is refused by the app:
  // calibrationFsrCount).
  size_t last = ok.rfind(",{\"index\":5");
  expect(CalError::Channels, ok.substr(0, last) + "]}");
  const std::string ch5 = ok.substr(last, ok.rfind("]}") - last);
  expect(CalError::Channels, replace(ok, "]}", replace(ch5, "\"index\":5", "\"index\":6") +
                                                   replace(ch5, "\"index\":5", "\"index\":7") + "]}"));
  expect(CalError::Index, replace(ok, "{\"index\":1,", "{\"index\":2,"));
  expect(CalError::Coefficient, replace(ok, "{\"index\":0,\"a\":123000", "{\"index\":0,\"a\":0"));
  expect(CalError::Coefficient, replace(ok, "{\"index\":0,\"a\":123000", "{\"index\":0,\"a\":true"));
  expect(CalError::Offset, replace(ok, "\"offset_adc\":0}]", "\"offset_adc\":4096}]"));
  expect(CalError::Offset, replace(ok, "\"offset_adc\":0}]", "\"offset_adc\":-1}]"));
}

void test_extra_digits_are_stored_rounded_and_visible() {
  // The board stores a/area at 6 and b at 4 significant digits; the stored
  // JSON differs from the input, which the laptop tool refuses.
  const std::string ok = build(testCalibration(1, 1000, 0.000113));
  for (const std::string& more :
       {replace(ok, "{\"index\":0,\"a\":123000", "{\"index\":0,\"a\":123000.7"),
        replace(ok, "\"b\":-1.05,\"offset_adc\":0}]", "\"b\":-1.0523,\"offset_adc\":0}]"),
        replace(ok, "0.000113", "0.0001134567")}) {
    CalData c{};
    TEST_ASSERT_EQUAL(static_cast<int>(CalError::None), static_cast<int>(parse(more, c)));
    TEST_ASSERT_TRUE(build(c) != more);
  }
  // Values within the agreed digits survive exactly, as text.
  const std::string six = replace(replace(ok, "{\"index\":0,\"a\":123000", "{\"index\":0,\"a\":98765.4"),
                                  "\"b\":-1.05,\"offset_adc\":0}]", "\"b\":-1.234,\"offset_adc\":0}]");
  CalData c{};
  TEST_ASSERT_EQUAL(static_cast<int>(CalError::None), static_cast<int>(parse(six, c)));
  TEST_ASSERT_EQUAL_STRING(six.c_str(), build(c).c_str());
}

void test_widest_fits_and_a_short_buffer_is_refused() {
  // Since v1.7 (6 channels) even the widest blob fits the 512-byte
  // characteristic: a 32-character id and every number at its widest
  // stored digits (it was over 512 with v1.6's 8 channels).
  CalData c = testCalibration(1, 1000, 0.000113);
  std::strcpy(c.deviceId, "INSOLE-R-0123456789-ABCDEFGHIJKL");  // 32 characters
  for (CalChannel& ch : c.ch) ch = {-1.23457e+08, -1.235e-05, 4095};
  char buf[kMaxCalibrationBytes + 1];
  size_t n = buildCalibrationJson(c, buf, sizeof buf);
  TEST_ASSERT_EQUAL(481, n);
  TEST_ASSERT_TRUE(n <= kMaxCalibrationBytes);
  char small[200];
  TEST_ASSERT_EQUAL(0, buildCalibrationJson(c, small, sizeof small));  // never cut off
}

void test_realistic_worst_case_fits() {
  // Six-digit a, four-digit b, four-digit offsets, a 13-character id: what
  // the hardware team is asked to send must fit.
  CalData c = testCalibration(1, 1000, 0.000113);
  std::strcpy(c.deviceId, "INSOLE-R-0001");
  for (CalChannel& ch : c.ch) ch = {123457, -1.235, 4095};
  std::string j = build(c);
  TEST_ASSERT_TRUE(j.size() > 0);
  TEST_ASSERT_TRUE(j.size() <= kMaxCalibrationBytes);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_test_calibration_json);
  RUN_TEST(test_round_trip);
  RUN_TEST(test_spaced_input_is_rebuilt_compact);
  RUN_TEST(test_refusals);
  RUN_TEST(test_extra_digits_are_stored_rounded_and_visible);
  RUN_TEST(test_widest_fits_and_a_short_buffer_is_refused);
  RUN_TEST(test_realistic_worst_case_fits);
  return UNITY_END();
}

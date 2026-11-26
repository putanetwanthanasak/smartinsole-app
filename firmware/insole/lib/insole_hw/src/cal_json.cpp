#include "cal_json.h"

#include <ArduinoJson.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace insole_hw {
namespace {

constexpr int kDigitsA = 6;
constexpr int kDigitsB = 4;
constexpr int kDigitsArea = 6;

// Formats `v` with at most `digits` significant digits; JSON-valid for any
// finite value (%g never prints inf/nan for finite input).
int fmt(char* out, size_t cap, double v, int digits) {
  return snprintf(out, cap, "%.*g", digits, v);
}

// The value stored for `v` at `digits` significant digits (correctly rounded
// double of the formatted text). ArduinoJson parses short decimals as float
// and keeps no exact text, so the board can't judge a 7th digit reliably:
// it stores at the agreed precision and `cal set` prints the stored JSON,
// which the laptop tool compares byte for byte with what it sent. A value
// sent with at most `digits` digits survives unchanged (float holds 6).
double canonical(double v, int digits) {
  char buf[40];
  fmt(buf, sizeof buf, v, digits);
  return std::strtod(buf, nullptr);
}

bool validDeviceId(const char* s) {
  size_t n = std::strlen(s);
  if (n == 0 || n > kMaxDeviceIdChars) return false;
  for (size_t i = 0; i < n; ++i) {
    char c = s[i];
    // Printable ASCII without the two characters JSON would need to escape.
    if (c < 0x20 || c > 0x7e || c == '"' || c == '\\') return false;
  }
  return true;
}

bool onlyKeys(JsonObjectConst o, const char* const* keys, size_t n) {
  for (JsonPairConst kv : o) {
    bool known = false;
    for (size_t i = 0; i < n; ++i) known = known || std::strcmp(kv.key().c_str(), keys[i]) == 0;
    if (!known) return false;
  }
  return true;
}

bool isNumber(JsonVariantConst v) { return v.is<double>() && !v.is<bool>(); }

}  // namespace

const char* calErrorText(CalError e) {
  switch (e) {
    case CalError::None: return "ok";
    case CalError::NotJson: return "not valid JSON";
    case CalError::NotObject: return "not a JSON object";
    case CalError::UnknownKey: return "unknown key (only device_id, r_pulldown_ohm, "
                                      "sensor_area_m2, channels; index, a, b, offset_adc)";
    case CalError::DeviceId: return "device_id must be 1-32 printable characters, no \" or \\";
    case CalError::Pulldown: return "r_pulldown_ohm must be a whole number of ohms, 1-10000000";
    case CalError::Area: return "sensor_area_m2 must be a number above 0";
    case CalError::Channels: return "channels must list exactly 6 entries";
    case CalError::Index: return "channel index must be 0-7 in order";
    case CalError::Coefficient: return "a and b must be numbers, a not 0";
    case CalError::Offset: return "offset_adc must be a whole number 0-4095";
    case CalError::TooLong: return "compact JSON longer than 512 bytes";
  }
  return "?";
}

size_t buildCalibrationJson(const CalData& cal, char* out, size_t cap) {
  size_t len = 0;
  auto put = [&](int n) {
    if (n < 0 || len + static_cast<size_t>(n) >= cap) return false;
    len += static_cast<size_t>(n);
    return true;
  };
  char area[24];
  fmt(area, sizeof area, cal.sensorAreaM2, kDigitsArea);
  if (!put(snprintf(out, cap,
                    "{\"device_id\":\"%s\",\"r_pulldown_ohm\":%lu,\"sensor_area_m2\":%s,"
                    "\"channels\":[",
                    cal.deviceId, static_cast<unsigned long>(cal.rPulldownOhm), area)))
    return 0;
  for (uint8_t c = 0; c < kCalChannels; ++c) {
    char a[24], b[24];
    fmt(a, sizeof a, cal.ch[c].a, kDigitsA);
    fmt(b, sizeof b, cal.ch[c].b, kDigitsB);
    if (!put(snprintf(out + len, cap - len, "%s{\"index\":%u,\"a\":%s,\"b\":%s,\"offset_adc\":%u}",
                      c ? "," : "", c, a, b, cal.ch[c].offsetAdc)))
      return 0;
  }
  if (!put(snprintf(out + len, cap - len, "]}"))) return 0;
  return len <= kMaxCalibrationBytes ? len : 0;
}

CalError parseCalibration(const char* text, size_t len, CalData& out) {
  JsonDocument doc;
  if (deserializeJson(doc, text, len)) return CalError::NotJson;
  if (!doc.is<JsonObjectConst>()) return CalError::NotObject;
  JsonObjectConst root = doc.as<JsonObjectConst>();
  static const char* const kTop[] = {"device_id", "r_pulldown_ohm", "sensor_area_m2", "channels"};
  if (!onlyKeys(root, kTop, 4)) return CalError::UnknownKey;

  CalData cal{};
  JsonVariantConst id = root["device_id"];
  if (!id.is<const char*>() || !validDeviceId(id.as<const char*>())) return CalError::DeviceId;
  std::strncpy(cal.deviceId, id.as<const char*>(), kMaxDeviceIdChars);

  JsonVariantConst rpd = root["r_pulldown_ohm"];
  if (!rpd.is<uint32_t>() || rpd.as<uint32_t>() < 1 || rpd.as<uint32_t>() > 10000000)
    return CalError::Pulldown;
  cal.rPulldownOhm = rpd.as<uint32_t>();

  JsonVariantConst area = root["sensor_area_m2"];
  if (!isNumber(area) || !(area.as<double>() > 0) || !std::isfinite(area.as<double>()))
    return CalError::Area;
  cal.sensorAreaM2 = canonical(area.as<double>(), kDigitsArea);

  JsonVariantConst chans = root["channels"];
  if (!chans.is<JsonArrayConst>() || chans.size() != kCalChannels) return CalError::Channels;
  static const char* const kChan[] = {"index", "a", "b", "offset_adc"};
  for (uint8_t c = 0; c < kCalChannels; ++c) {
    JsonVariantConst ch = chans[c];
    if (!ch.is<JsonObjectConst>()) return CalError::Channels;
    if (!onlyKeys(ch.as<JsonObjectConst>(), kChan, 4)) return CalError::UnknownKey;
    if (!ch["index"].is<uint8_t>() || ch["index"].as<uint8_t>() != c) return CalError::Index;
    JsonVariantConst a = ch["a"], b = ch["b"];
    if (!isNumber(a) || !isNumber(b) || !std::isfinite(a.as<double>()) ||
        !std::isfinite(b.as<double>()) || a.as<double>() == 0)
      return CalError::Coefficient;
    cal.ch[c].a = canonical(a.as<double>(), kDigitsA);
    cal.ch[c].b = canonical(b.as<double>(), kDigitsB);
    JsonVariantConst off = ch["offset_adc"];
    if (!off.is<uint16_t>() || off.as<uint16_t>() > 4095) return CalError::Offset;
    cal.ch[c].offsetAdc = off.as<uint16_t>();
  }
  char buf[kMaxCalibrationBytes + 1];
  if (buildCalibrationJson(cal, buf, sizeof buf) == 0) return CalError::TooLong;
  out = cal;
  return CalError::None;
}

CalData testCalibration(uint8_t footSide, uint32_t rPulldownOhm, double sensorAreaM2) {
  CalData cal{};
  std::snprintf(cal.deviceId, sizeof cal.deviceId, "INSOLE-%s-TEST", footSide == 0 ? "L" : "R");
  cal.rPulldownOhm = rPulldownOhm;
  cal.sensorAreaM2 = sensorAreaM2;
  for (CalChannel& ch : cal.ch) ch = {123000, -1.05, 0};
  return cal;
}

bool isTestCalibration(const CalData& cal) {
  size_t n = std::strlen(cal.deviceId);
  return n >= 5 && std::strcmp(cal.deviceId + n - 5, "-TEST") == 0;
}

}  // namespace insole_hw

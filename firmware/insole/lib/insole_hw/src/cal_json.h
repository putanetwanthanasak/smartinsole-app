// The calibration blob served on the Calibration characteristic (DATA-CONTRACT
// v1.6 §5.1 and Appendix C item 4): compact JSON, at most 512 bytes, exactly 8
// channels. Kept as numbers in NVS (cal_store) and rebuilt with a bounded
// number of digits, so its length is predictable.
//
// Digits: a and sensor_area_m2 are stored at 6 significant digits, b at 4,
// offset_adc an integer (the hardware team is asked to send them so;
// report 043). The board cannot check digits exactly (ArduinoJson parses
// short decimals as float), so `cal set` prints the stored JSON and the
// laptop tool refuses the result unless it matches what it sent, byte for
// byte.
#pragma once

#include <cstddef>
#include <cstdint>

namespace insole_hw {

constexpr size_t kMaxCalibrationBytes = 512;  // GATT attribute value limit
constexpr uint8_t kCalChannels = 8;           // contract v1.6: N = 8
constexpr size_t kMaxDeviceIdChars = 32;

struct CalChannel {
  double a;
  double b;
  uint16_t offsetAdc;  // wire counts (§5.1 addendum 2), set by TARE
};

struct CalData {
  char deviceId[kMaxDeviceIdChars + 1];
  uint32_t rPulldownOhm;
  double sensorAreaM2;
  CalChannel ch[kCalChannels];
};

enum class CalError : uint8_t {
  None,
  NotJson,
  NotObject,
  UnknownKey,
  DeviceId,
  Pulldown,
  Area,
  Channels,
  Index,
  Coefficient,
  Offset,
  TooLong,
};

const char* calErrorText(CalError e);

// Compact JSON into `out` (NUL-terminated); returns its length, or 0 if it is
// longer than 512 bytes or does not fit `cap`.
size_t buildCalibrationJson(const CalData& cal, char* out, size_t cap);

// Strict parse of a calibration JSON (from the serial `cal set` command):
// exact keys, 8 channels in index order, value ranges. Numbers are stored at
// the precision above. On success fills `out` and returns CalError::None;
// `out` is untouched otherwise. The rebuilt compact JSON must fit 512 bytes.
CalError parseCalibration(const char* text, size_t len, CalData& out);

// Test values until the hardware team's per-sensor fits exist: device_id
// INSOLE-<L|R>-TEST, the contract §5.1 example curve (a 123000, b -1.05) on
// every channel, offset_adc 0 until TARE. Such a board never records study
// data (user rule, 2026-11-09).
CalData testCalibration(uint8_t footSide, uint32_t rPulldownOhm, double sensorAreaM2);

// True for a device_id ending in "-TEST".
bool isTestCalibration(const CalData& cal);

}  // namespace insole_hw

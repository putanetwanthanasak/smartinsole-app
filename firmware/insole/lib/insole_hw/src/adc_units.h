// FSR divider voltage -> the wire unit (DATA-CONTRACT v1.6 §3.1 / §5.1,
// addendum 2, 2026-11-09): each fsr value is the divider's output voltage in
// 12-bit counts of the 3.3 V supply, count = round(mV x 4095 / 3300), from
// the chip's factory-calibrated millivolts. It is not the raw ADC code: the
// ESP32-C3 reads only up to 2.5 V at its highest attenuation (datasheet v2.4,
// Table 5-6), so its raw 4095 does not mean 3.3 V.
//
// Two ranges (report 043): with the 1 kOhm pull-down, everything up to the
// 200 kPa alert threshold sits below about 0.72 V, inside the low range
// (ATTEN0, 0-750 mV, +-10 mV) instead of the high range (ATTEN3, 0-2500 mV,
// +-35 mV). A first conversion in the high range picks the range.
#pragma once

#include <cstdint>

namespace insole_hw {

constexpr uint32_t kSupplyMv = 3300;   // contract §5.1: 4095 = 3.3 V
constexpr uint16_t kCountMax = 4095;
constexpr uint16_t kRawMax = 4095;     // the C3's 12-bit code ceiling
constexpr uint32_t kHighRangeTopMv = 2500;  // ATTEN3 effective range
constexpr uint32_t kLowRangeTopMv = 750;    // ATTEN0 effective range
// The high range's error is +-35 mV, so flag from 2450 mV on.
constexpr uint32_t kSaturatedMv = 2450;
// A high-range reading below 700 mV (+-35 mV) is at most 735 mV: inside the
// low range.
constexpr uint32_t kUseLowRangeBelowMv = 700;
// A low-range average this close to its code ceiling is not trusted; the
// high-range reading is kept instead.
constexpr uint16_t kLowRangeRawLimit = 4000;

// round(mv * 4095 / 3300), at most 4095.
constexpr uint16_t mvToCount(uint32_t mv) {
  uint32_t c = (mv * kCountMax + kSupplyMv / 2) / kSupplyMv;
  return c > kCountMax ? kCountMax : static_cast<uint16_t>(c);
}

constexpr bool useLowRange(uint32_t highRangeMv) { return highRangeMv < kUseLowRangeBelowMv; }

struct Reading {
  uint16_t count;   // the wire value
  uint32_t mv;      // what it came from
  bool lowRange;    // measured in the low range
  bool saturated;   // at the high range's ceiling: packet flags bit0
};

// Combines one channel's conversions. `highMv`/`highRawMax`: the high range
// (always measured). `haveLow`: whether the low range was measured (only when
// useLowRange(first high reading)); `lowMv`/`lowRawMax` then hold it.
Reading combine(uint32_t highMv, uint16_t highRawMax, bool haveLow, uint32_t lowMv,
                uint16_t lowRawMax);

}  // namespace insole_hw

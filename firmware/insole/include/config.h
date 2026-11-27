// Build-time configuration of the real insole (FW-1, report 043).
//
// The pin map, the mux channel of each sensor and the IMU axis map come from
// the hardware team (scratchpad questions B-D; report 043). Until they are
// filled in, PINMAP_FILLED_IN stays 0 and only the buildcheck env compiles:
// it halts at boot before touching any pin or the radio, and the upload
// guard refuses to flash it. A guessed pin never reaches a board.
#pragma once

#include <cstdint>

#include "axis_map.h"
#include "protocol.h"

#ifndef FOOT_SIDE
#error "FOOT_SIDE must be set by the build (0 = left, 1 = right)"
#endif
static_assert(FOOT_SIDE == 0 || FOOT_SIDE == 1, "FOOT_SIDE must be 0 or 1");

// The insole keeps its 8 Velostat pads; the firmware reads sites 0-5 only
// (DATA-CONTRACT v1.7, user decision 2026-11-25). The pads at v1.6's
// sites 6 (medial arch) and 7 (lateral heel) stay in the insole, unread.
#ifndef FSR_COUNT
#define FSR_COUNT 6
#endif
static_assert(FSR_COUNT == 6, "the real insole reads 6 FSR sites (contract v1.7)");

// ---- Filled in from the hardware team's answers --------------------------
#define PINMAP_FILLED_IN 0

#if !PINMAP_FILLED_IN && !defined(FW1_BUILD_CHECK)
#error "config.h: pin map not filled in yet (hardware team). Only the buildcheck env builds."
#endif

namespace config {

constexpr uint8_t kFootSide = FOOT_SIDE;
constexpr uint8_t kFsrCount = FSR_COUNT;
constexpr const char* kDeviceName = FOOT_SIDE == 0 ? "SMARTINSOLE-L" : "SMARTINSOLE-R";
// Our firmware track: the simulator is 0.1, the hardware team's 1.6, so
// Researcher › Diagnostics shows which firmware a board runs.
constexpr uint8_t kFwMajor = 0;
constexpr uint8_t kFwMinor = 2;
constexpr bool kBuildCheck =
#ifdef FW1_BUILD_CHECK
    true;
#else
    false;
#endif

constexpr int kNoPin = -1;

// Placeholders (buildcheck only). Every one is replaced from the hardware
// team's pin map before PINMAP_FILLED_IN becomes 1.
constexpr int kPinMuxS[4] = {5, 6, 7, 10};  // S0..S3
constexpr int kPinMuxEnable = kNoPin;       // active low; kNoPin if tied low
constexpr int kPinMuxSignal = 3;            // ADC1: GPIO0, 1, 3 or 4 only
constexpr int kPinSda = 20;
constexpr int kPinScl = 21;
constexpr int kPinSdCs = kNoPin;            // held high: the SD card stays off the bus
constexpr uint8_t kMpuAddress = 0x68;       // seen at boot in SR-1

// Mux channel (C00..C15) of each contract site, index = site:
// 0 hallux, 1 MTH1, 2 MTH2-3, 3 MTH5, 4 lateral midfoot, 5 heel centre
// (v1.7). Per foot (each foot's own board). Placeholders until the hardware
// team's pin map. On the right board the hallux press showed on C05 and C06
// together (report 043): the six channels chosen here must not include
// both halves of a bridged pair.
constexpr uint8_t kMuxChannelOfSite[2][kFsrCount] = {
    {0, 1, 2, 3, 4, 5},  // left (placeholder)
    {0, 1, 2, 3, 4, 5},  // right (placeholder; SR-1 press test, report 043)
};

// IMU chip axes -> insole frame (contract §5.2 addendum 2), per foot: the box
// clips on each shoe's lateral heel, so the chip sits differently on each
// side. Placeholders until the hardware team's orientation drawing.
constexpr insole_hw::AxisMap kAxisMap[2] = {insole_hw::kIdentityAxes,
                                            insole_hw::kIdentityAxes};

// FSR divider (hardware team, 2026-11-09): 1 kOhm pull-down. Sensor area:
// the contract example until measured (calibration track).
constexpr uint32_t kPulldownOhm = 1000;
constexpr double kSensorAreaM2 = 0.000113;

// Mux settling after switching, before the discarded conversion.
constexpr uint32_t kMuxSettleUs = 20;
constexpr uint8_t kAveragedReads = 4;

// ---- Checks ---------------------------------------------------------------
constexpr bool isAdc1(int p) { return p == 0 || p == 1 || p == 3 || p == 4; }
// GPIO11 VDD_SPI, GPIO12-17 in-package flash, GPIO18/19 USB (our serial and
// flashing port): never used.
constexpr bool reserved(int p) { return p >= 11 && p <= 19; }
constexpr bool okPin(int p) { return p == kNoPin || (p >= 0 && p <= 21 && !reserved(p)); }

static_assert(isAdc1(kPinMuxSignal),
              "mux SIG must be an ADC1 pin other than GPIO2 (strapping; an unloaded "
              "FSR's pull-down would hold it low at reset)");
static_assert(okPin(kPinMuxS[0]) && okPin(kPinMuxS[1]) && okPin(kPinMuxS[2]) &&
                  okPin(kPinMuxS[3]) && okPin(kPinMuxEnable) && okPin(kPinSda) &&
                  okPin(kPinScl) && okPin(kPinSdCs),
              "a pin is GPIO11-19 (flash or USB) or out of range");
static_assert(insole_hw::isProperRotation(kAxisMap[0]) && insole_hw::isProperRotation(kAxisMap[1]),
              "an axis map is not a rotation (a mirrored map is a typo: chips can't be mirrored)");
constexpr bool muxMapValid(const uint8_t* m) {
  for (int i = 0; i < kFsrCount; ++i) {
    if (m[i] > 15) return false;
    for (int j = 0; j < i; ++j)
      if (m[i] == m[j]) return false;
  }
  return true;
}
static_assert(muxMapValid(kMuxChannelOfSite[0]) && muxMapValid(kMuxChannelOfSite[1]),
              "each site needs its own mux channel 0-15");

}  // namespace config

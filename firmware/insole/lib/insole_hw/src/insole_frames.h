// What the real insole puts on the wire around the simulator's tested core
// (../simulator/lib/insole_core): one 50 Hz sample from real readings, the
// packet flag for the C3's ADC ceiling, and the values the contract defines
// for sensors this board does not have yet (report 043).
#pragma once

#include <cstdint>

#include "axis_map.h"
#include "cal_json.h"
#include "packets.h"
#include "stream_session.h"

namespace insole_hw {

// No NTC fitted: every site "could not be read" (-32768) with quality 2,
// sensor error (contract §3.2). The app shows "no data" per site, no ΔT.
insole::TemperatureReading noNtcReading();

// No battery (USB power on the bench): contract §3.3 addendum 2. Never a
// made-up charge level.
constexpr uint8_t kBatteryExternalPct = 255;
constexpr uint16_t kBatteryExternalMv = 0;

// One sample: the 6 wire counts in contract site order, and the IMU's raw
// chip axes mapped to the insole frame.
insole::Sample makeSample(const uint16_t counts[kCalChannels], const int16_t accelChip[3],
                          const int16_t gyroChip[3], const AxisMap& axes);

// insole_core sets flags bit0 only for a value of 4095, which the C3 never
// reaches in wire counts (its 2.5 V ceiling is about 3100). This wraps one
// session's addSample and sets bit0 on a packet holding any sample that hit
// the ceiling. Call reset() on that session's START, STOP, connect and
// disconnect.
class SaturationFlag {
 public:
  bool add(insole::StreamSession& s, const insole::Sample& sample, bool saturated, uint32_t tMs,
           uint8_t fsrCount, insole::OutPacket& out, bool calibrating);
  void reset() { pending_ = false; }

 private:
  bool pending_ = false;
};

}  // namespace insole_hw

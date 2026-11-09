// TARE (opcode 0x05) on the real insole: the mean of each channel over one
// second with nothing on the insole becomes its offset_adc (contract §5.1).
// The Velostat sensors read a finite, drifting value unloaded (report 043),
// so TARE is done at the start of every session, not once.
//
// If any channel moves more than kMaxSpreadCounts during the window (the
// insole was touched or loaded), the TARE fails and the old offsets stay:
// an offset taken under load would clamp real pressure to 0 kPa (report 042,
// L2).
#pragma once

#include <cstdint>

#include "cal_json.h"

namespace insole_hw {

class TareMean {
 public:
  static constexpr uint16_t kWindowSamples = 50;     // 1 s at 50 Hz
  static constexpr uint16_t kMaxSpreadCounts = 120;  // ~97 mV; bench-checked in FW-1

  enum class Outcome : uint8_t { Idle, Running, Done, Moved };

  bool active() const { return active_; }

  // Starts a TARE over the next kWindowSamples samples; false (nothing
  // changes) if one is already running.
  bool begin();

  // Feeds one sample's 8 wire counts. Returns Running while the window
  // fills, then Done (offsets() valid) or Moved (movedChannel() says which),
  // then Idle until the next begin().
  Outcome feed(const uint16_t counts[kCalChannels]);

  const uint16_t* offsets() const { return offsets_; }
  uint8_t movedChannel() const { return moved_; }
  uint16_t spread(uint8_t c) const { return static_cast<uint16_t>(max_[c] - min_[c]); }

 private:
  bool active_ = false;
  uint16_t seen_ = 0;
  uint32_t sum_[kCalChannels] = {};
  uint16_t min_[kCalChannels] = {};
  uint16_t max_[kCalChannels] = {};
  uint16_t offsets_[kCalChannels] = {};
  uint8_t moved_ = 0;
};

}  // namespace insole_hw

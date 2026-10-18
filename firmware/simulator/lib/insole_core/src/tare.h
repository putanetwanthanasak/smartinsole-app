// TARE (opcode 0x05): measures each channel's zero point, which the
// calibration blob then serves as `offset_adc` (contract §5.1).
//
// Real firmware averages a reading taken with the foot lifted off the
// insole. The simulator is always walking, so it takes each channel's
// minimum over one stride instead: in the swing phase that is the unloaded
// reading. While a tare runs, packets carry flags bit1 (calibrating).
#pragma once

#include "packets.h"

namespace insole {

class Tare {
 public:
  static constexpr uint16_t kWindowSamples = 55;  // one 1100 ms stride at 50 Hz

  bool active() const { return active_; }

  // Starts a tare over the next kWindowSamples samples. Returns false (and
  // changes nothing) if one is already running.
  bool begin(uint8_t fsrCount);

  // Feeds one sample. Returns true on the sample that completes the window;
  // offsets() is valid from then on. Does nothing when not active.
  bool feed(const Sample& s);

  const uint16_t* offsets() const { return offsets_; }

 private:
  bool active_ = false;
  uint8_t fsrCount_ = 0;
  uint16_t seen_ = 0;
  uint16_t min_[kMaxFsrCount] = {};
  uint16_t offsets_[kMaxFsrCount] = {};
};

}  // namespace insole

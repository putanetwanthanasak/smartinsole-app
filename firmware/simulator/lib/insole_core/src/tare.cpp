#include "tare.h"

namespace insole {

bool Tare::begin(uint8_t fsrCount) {
  if (active_) return false;
  active_ = true;
  fsrCount_ = fsrCount;
  seen_ = 0;
  for (auto& m : min_) m = 0xffff;
  return true;
}

bool Tare::feed(const Sample& s) {
  if (!active_) return false;
  for (uint8_t c = 0; c < fsrCount_; ++c)
    if (s.fsr[c] < min_[c]) min_[c] = s.fsr[c];
  if (++seen_ < kWindowSamples) return false;
  for (uint8_t c = 0; c < kMaxFsrCount; ++c) offsets_[c] = c < fsrCount_ ? min_[c] : 0;
  active_ = false;
  return true;
}

}  // namespace insole

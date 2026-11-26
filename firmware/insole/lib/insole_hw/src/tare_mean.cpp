#include "tare_mean.h"

namespace insole_hw {

bool TareMean::begin() {
  if (active_) return false;
  active_ = true;
  seen_ = 0;
  for (uint8_t c = 0; c < kCalChannels; ++c) {
    sum_[c] = 0;
    min_[c] = 0xffff;
    max_[c] = 0;
  }
  return true;
}

TareMean::Outcome TareMean::feed(const uint16_t counts[kCalChannels]) {
  if (!active_) return Outcome::Idle;
  for (uint8_t c = 0; c < kCalChannels; ++c) {
    sum_[c] += counts[c];
    if (counts[c] < min_[c]) min_[c] = counts[c];
    if (counts[c] > max_[c]) max_[c] = counts[c];
  }
  if (++seen_ < kWindowSamples) return Outcome::Running;
  active_ = false;
  for (uint8_t c = 0; c < kCalChannels; ++c) {
    if (spread(c) > kMaxSpreadCounts) {
      moved_ = c;
      return Outcome::Moved;
    }
  }
  for (uint8_t c = 0; c < kCalChannels; ++c)
    offsets_[c] = static_cast<uint16_t>((sum_[c] + kWindowSamples / 2) / kWindowSamples);
  return Outcome::Done;
}

}  // namespace insole_hw

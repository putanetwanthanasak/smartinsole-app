#include "adc_units.h"

namespace insole_hw {

Reading combine(uint32_t highMv, uint16_t highRawMax, bool haveLow, uint32_t lowMv,
                uint16_t lowRawMax) {
  Reading r{};
  bool low = haveLow && lowRawMax < kLowRangeRawLimit;
  r.mv = low ? lowMv : highMv;
  r.lowRange = low;
  r.count = mvToCount(r.mv);
  // Saturation is judged in the high range only: the low range is used only
  // well below its own ceiling.
  r.saturated = !low && (highMv >= kSaturatedMv || highRawMax >= kRawMax);
  return r;
}

}  // namespace insole_hw

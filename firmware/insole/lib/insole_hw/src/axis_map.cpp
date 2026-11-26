#include "axis_map.h"

namespace insole_hw {

void remap(const AxisMap& m, const int16_t chip[3], int16_t out[3]) {
  int16_t tmp[3];
  for (int i = 0; i < 3; ++i) {
    int32_t v = static_cast<int32_t>(chip[m.src[i]]) * m.sign[i];
    tmp[i] = static_cast<int16_t>(v > 32767 ? 32767 : v);
  }
  for (int i = 0; i < 3; ++i) out[i] = tmp[i];
}

}  // namespace insole_hw

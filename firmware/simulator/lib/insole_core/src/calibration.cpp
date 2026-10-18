#include "calibration.h"

#include <cstdio>

#include "protocol.h"

namespace insole {

size_t buildCalibrationJson(char* out, size_t cap, const char* deviceId, uint8_t fsrCount) {
  // Coefficients are the contract §5.1 example, the same for every channel.
  size_t len = 0;
  auto put = [&](int n) {
    if (n < 0 || len + static_cast<size_t>(n) >= cap) return false;
    len += static_cast<size_t>(n);
    return true;
  };
  if (!put(snprintf(out, cap, "{\"device_id\":\"%s\",\"r_pulldown_ohm\":10000,"
                              "\"sensor_area_m2\":0.000113,\"channels\":[",
                    deviceId)))
    return 0;
  for (uint8_t c = 0; c < fsrCount; ++c) {
    if (!put(snprintf(out + len, cap - len,
                      "%s{\"index\":%u,\"a\":123000,\"b\":-1.05,\"offset_adc\":12}",
                      c ? "," : "", c)))
      return 0;
  }
  if (!put(snprintf(out + len, cap - len, "]}"))) return 0;
  return len <= kMaxCalibrationBytes ? len : 0;
}

}  // namespace insole

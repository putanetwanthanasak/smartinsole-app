// IMU chip axes -> the insole frame (DATA-CONTRACT v1.6 §5.2, addendum 2):
// x toward the toes, y toward the wearer's left, z up out of the insole into
// the foot, right-handed, the same for both insoles. The box clips on each
// shoe's lateral heel, so the chip sits differently in each foot's box: one
// map per foot (config.h), from the hardware team's orientation drawing.
//
// Insole axis i = sign[i] x chip axis src[i]. A chip can be turned but never
// mirrored, so a valid map is a proper rotation (determinant +1); a map with
// determinant -1 is a typo in config.h. For a proper rotation the gyro maps
// exactly like the accelerometer.
#pragma once

#include <cstdint>

namespace insole_hw {

struct AxisMap {
  uint8_t src[3];  // chip axis (0 x, 1 y, 2 z) feeding insole axis 0, 1, 2
  int8_t sign[3];  // +1 or -1
};

constexpr AxisMap kIdentityAxes{{0, 1, 2}, {1, 1, 1}};

// +1 or -1 for a signed permutation, 0 if `m` is not one.
constexpr int determinant(const AxisMap& m) {
  for (int i = 0; i < 3; ++i) {
    if (m.src[i] > 2 || (m.sign[i] != 1 && m.sign[i] != -1)) return 0;
    for (int j = 0; j < i; ++j)
      if (m.src[i] == m.src[j]) return 0;
  }
  int inversions = 0;
  for (int i = 0; i < 3; ++i)
    for (int j = i + 1; j < 3; ++j)
      if (m.src[i] > m.src[j]) ++inversions;
  int d = inversions % 2 ? -1 : 1;
  for (int i = 0; i < 3; ++i) d *= m.sign[i];
  return d;
}

constexpr bool isProperRotation(const AxisMap& m) { return determinant(m) == 1; }

// Applies `m`; -(-32768) saturates to 32767.
void remap(const AxisMap& m, const int16_t chip[3], int16_t out[3]);

}  // namespace insole_hw

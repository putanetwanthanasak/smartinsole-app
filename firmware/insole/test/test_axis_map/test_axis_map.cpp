// IMU chip axes -> insole frame (contract §5.2 addendum 2).
#include <unity.h>

#include "axis_map.h"

using namespace insole_hw;

void setUp() {}
void tearDown() {}

void test_identity_is_a_rotation() {
  TEST_ASSERT_EQUAL(1, determinant(kIdentityAxes));
  TEST_ASSERT_TRUE(isProperRotation(kIdentityAxes));
}

void test_rotations_and_reflections() {
  // Chip turned 90 deg about z: insole x = chip y, insole y = -chip x.
  constexpr AxisMap turned{{1, 0, 2}, {1, -1, 1}};
  static_assert(isProperRotation(turned), "compile-time check works");
  TEST_ASSERT_EQUAL(1, determinant(turned));
  // Chip upside down (turned 180 deg about x): y and z flip.
  TEST_ASSERT_EQUAL(1, determinant(AxisMap{{0, 1, 2}, {1, -1, -1}}));
  // A mirror (one sign flipped) can't be a mounted chip: a config typo.
  TEST_ASSERT_EQUAL(-1, determinant(AxisMap{{0, 1, 2}, {1, 1, -1}}));
  TEST_ASSERT_EQUAL(-1, determinant(AxisMap{{1, 0, 2}, {1, 1, 1}}));
  TEST_ASSERT_FALSE(isProperRotation(AxisMap{{1, 0, 2}, {1, 1, 1}}));
  // Not a permutation, or a bad sign.
  TEST_ASSERT_EQUAL(0, determinant(AxisMap{{0, 0, 2}, {1, 1, 1}}));
  TEST_ASSERT_EQUAL(0, determinant(AxisMap{{0, 1, 3}, {1, 1, 1}}));
  TEST_ASSERT_EQUAL(0, determinant(AxisMap{{0, 1, 2}, {1, 0, 1}}));
}

void test_remap_values() {
  constexpr AxisMap turned{{1, 0, 2}, {1, -1, 1}};
  const int16_t chip[3] = {100, -200, 4096};
  int16_t out[3];
  remap(turned, chip, out);
  TEST_ASSERT_EQUAL_INT16(-200, out[0]);
  TEST_ASSERT_EQUAL_INT16(-100, out[1]);
  TEST_ASSERT_EQUAL_INT16(4096, out[2]);
}

void test_remap_in_place_and_saturating_negate() {
  constexpr AxisMap flipped{{0, 1, 2}, {1, -1, -1}};
  int16_t v[3] = {5, -32768, 32767};
  remap(flipped, v, v);
  TEST_ASSERT_EQUAL_INT16(5, v[0]);
  TEST_ASSERT_EQUAL_INT16(32767, v[1]);  // -(-32768) does not wrap
  TEST_ASSERT_EQUAL_INT16(-32767, v[2]);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_identity_is_a_rotation);
  RUN_TEST(test_rotations_and_reflections);
  RUN_TEST(test_remap_values);
  RUN_TEST(test_remap_in_place_and_saturating_negate);
  return UNITY_END();
}

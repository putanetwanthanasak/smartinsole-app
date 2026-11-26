// Wire unit (contract §3.1/§5.1 addendum 2) and the two ADC ranges.
#include <unity.h>

#include "adc_units.h"

using namespace insole_hw;

void setUp() {}
void tearDown() {}

void test_mv_to_count() {
  TEST_ASSERT_EQUAL_UINT16(0, mvToCount(0));
  TEST_ASSERT_EQUAL_UINT16(4095, mvToCount(3300));    // 4095 = 3.3 V
  TEST_ASSERT_EQUAL_UINT16(2048, mvToCount(1650));    // 2047.5 rounds up
  TEST_ASSERT_EQUAL_UINT16(1, mvToCount(1));          // 1.24 -> 1
  TEST_ASSERT_EQUAL_UINT16(65, mvToCount(52));        // ~10 kPa, 1 kOhm, example curve
  TEST_ASSERT_EQUAL_UINT16(888, mvToCount(716));      // ~200 kPa
  TEST_ASSERT_EQUAL_UINT16(3102, mvToCount(2500));    // the C3's ceiling
  TEST_ASSERT_EQUAL_UINT16(4095, mvToCount(3500));    // clamps
  TEST_ASSERT_EQUAL_UINT16(4095, mvToCount(100000));  // no overflow
}

void test_range_choice() {
  TEST_ASSERT_TRUE(useLowRange(0));
  TEST_ASSERT_TRUE(useLowRange(699));
  TEST_ASSERT_FALSE(useLowRange(700));
  TEST_ASSERT_FALSE(useLowRange(2400));
  // 700 mV + the high range's 35 mV error still sits inside the low range.
  TEST_ASSERT_LESS_THAN_UINT32(kLowRangeTopMv, kUseLowRangeBelowMv + 35);
}

void test_combine_low_range() {
  Reading r = combine(55, 92, true, 52, 290);
  TEST_ASSERT_TRUE(r.lowRange);
  TEST_ASSERT_EQUAL_UINT32(52, r.mv);
  TEST_ASSERT_EQUAL_UINT16(65, r.count);
  TEST_ASSERT_FALSE(r.saturated);
}

void test_combine_low_range_near_its_ceiling_keeps_high() {
  Reading r = combine(690, 1150, true, 748, 4050);
  TEST_ASSERT_FALSE(r.lowRange);
  TEST_ASSERT_EQUAL_UINT32(690, r.mv);
}

void test_combine_high_range_and_saturation() {
  Reading r = combine(1500, 2500, false, 0, 0);
  TEST_ASSERT_FALSE(r.lowRange);
  TEST_ASSERT_EQUAL_UINT16(mvToCount(1500), r.count);
  TEST_ASSERT_FALSE(r.saturated);
  TEST_ASSERT_TRUE(combine(2449, 3990, false, 0, 0).saturated == false);
  TEST_ASSERT_TRUE(combine(2450, 3995, false, 0, 0).saturated);
  TEST_ASSERT_TRUE(combine(2300, 4095, false, 0, 0).saturated);  // raw at the code ceiling
  // A saturated reading still carries its value; only the flag marks it.
  TEST_ASSERT_EQUAL_UINT16(mvToCount(2600), combine(2600, 4095, false, 0, 0).count);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_mv_to_count);
  RUN_TEST(test_range_choice);
  RUN_TEST(test_combine_low_range);
  RUN_TEST(test_combine_low_range_near_its_ceiling_keeps_high);
  RUN_TEST(test_combine_high_range_and_saturation);
  return UNITY_END();
}

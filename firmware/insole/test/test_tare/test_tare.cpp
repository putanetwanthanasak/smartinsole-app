// TARE on the real insole: the 1 s mean per channel, refused if the insole
// moved (an offset taken under load would clamp real pressure to 0 kPa).
#include <unity.h>

#include "tare_mean.h"

using namespace insole_hw;

void setUp() {}
void tearDown() {}

namespace {

TareMean::Outcome run(TareMean& t, uint16_t base, int wobble, int stepAt = -1, int step = 0) {
  TareMean::Outcome o = TareMean::Outcome::Running;
  for (int i = 0; i < TareMean::kWindowSamples; ++i) {
    uint16_t v[kCalChannels];
    for (uint8_t c = 0; c < kCalChannels; ++c)
      v[c] = static_cast<uint16_t>(base + 10 * c + (i % 2 ? wobble : -wobble) +
                                   (stepAt >= 0 && i >= stepAt && c == 3 ? step : 0));
    o = t.feed(v);
    if (i < TareMean::kWindowSamples - 1) TEST_ASSERT_EQUAL(TareMean::Outcome::Running, o);
  }
  return o;
}

}  // namespace

void test_idle_until_begin() {
  TareMean t;
  uint16_t v[kCalChannels] = {};
  TEST_ASSERT_FALSE(t.active());
  TEST_ASSERT_EQUAL(TareMean::Outcome::Idle, t.feed(v));
}

void test_mean_per_channel() {
  TareMean t;
  TEST_ASSERT_TRUE(t.begin());
  TEST_ASSERT_TRUE(t.active());
  TEST_ASSERT_FALSE(t.begin());  // already running
  TEST_ASSERT_EQUAL(TareMean::Outcome::Done, run(t, 800, 7));
  TEST_ASSERT_FALSE(t.active());
  for (uint8_t c = 0; c < kCalChannels; ++c) TEST_ASSERT_EQUAL_UINT16(800 + 10 * c, t.offsets()[c]);
  uint16_t v[kCalChannels] = {};
  TEST_ASSERT_EQUAL(TareMean::Outcome::Idle, t.feed(v));
}

void test_mean_rounds() {
  TareMean t;
  t.begin();
  for (int i = 0; i < TareMean::kWindowSamples; ++i) {
    uint16_t v[kCalChannels];
    for (uint8_t c = 0; c < kCalChannels; ++c) v[c] = static_cast<uint16_t>(i < 25 ? 100 : 101);
    t.feed(v);
  }
  TEST_ASSERT_EQUAL_UINT16(101, t.offsets()[0]);  // 100.5 rounds up
}

void test_moved_insole_keeps_old_offsets() {
  TareMean t;
  t.begin();
  TEST_ASSERT_EQUAL(TareMean::Outcome::Done, run(t, 500, 3));
  uint16_t before = t.offsets()[3];
  t.begin();
  // Channel 3 jumps by 300 counts halfway: someone touched the insole.
  TEST_ASSERT_EQUAL(TareMean::Outcome::Moved, run(t, 500, 3, 25, 300));
  TEST_ASSERT_EQUAL_UINT8(3, t.movedChannel());
  TEST_ASSERT_EQUAL_UINT16(before, t.offsets()[3]);
  TEST_ASSERT_TRUE(t.spread(3) > TareMean::kMaxSpreadCounts);
}

void test_spread_at_the_limit_passes() {
  TareMean t;
  t.begin();
  TEST_ASSERT_EQUAL(TareMean::Outcome::Done, run(t, 500, TareMean::kMaxSpreadCounts / 2));
  TEST_ASSERT_EQUAL_UINT16(TareMean::kMaxSpreadCounts, t.spread(0));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_idle_until_begin);
  RUN_TEST(test_mean_per_channel);
  RUN_TEST(test_mean_rounds);
  RUN_TEST(test_moved_insole_keeps_old_offsets);
  RUN_TEST(test_spread_at_the_limit_passes);
  return UNITY_END();
}

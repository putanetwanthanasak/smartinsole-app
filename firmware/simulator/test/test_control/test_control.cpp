// Control writes (contract §3.4) and TARE: exact payload lengths, the
// SYNC_TIME decode, unknown opcodes, and the zero point a tare measures.
#include <unity.h>

#include <initializer_list>

#include "control.h"
#include "synth.h"
#include "tare.h"

using namespace insole;

namespace {

Command parse(std::initializer_list<uint8_t> bytes) {
  uint8_t buf[16];
  size_t n = 0;
  for (uint8_t b : bytes) buf[n++] = b;
  return parseControl(buf, n);
}

void test_opcodes_with_exact_length() {
  TEST_ASSERT_EQUAL(CommandKind::Start, (parse({0x01}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Stop, (parse({0x02}).kind));
  TEST_ASSERT_EQUAL(CommandKind::SyncTime, (parse({0x03, 0, 0, 0, 0, 0, 0, 0, 0}).kind));
  TEST_ASSERT_EQUAL(CommandKind::SetRate, (parse({0x04, 50}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Tare, (parse({0x05}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Reboot, (parse({0x06}).kind));
}

void test_wrong_length_is_malformed() {
  TEST_ASSERT_EQUAL(CommandKind::Malformed, parseControl(nullptr, 0).kind);
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x01, 0x00}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x02, 0x02}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x03, 1, 2, 3, 4, 5, 6, 7}).kind));  // 7-byte time
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x03, 1, 2, 3, 4, 5, 6, 7, 8, 9}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x04}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x04, 50, 0}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x05, 0x00}).kind));
  TEST_ASSERT_EQUAL(CommandKind::Malformed, (parse({0x06, 0x06}).kind));
  TEST_ASSERT_EQUAL(0x06, (parse({0x06, 0x06}).opcode));
}

void test_unknown_opcodes() {
  // 0x10 SET_SCENARIO is backlog (BACKLOG 18), not implemented.
  for (uint8_t op : {0x00, 0x07, 0x10, 0x7f, 0xff}) {
    Command c = parse({op});
    TEST_ASSERT_EQUAL(CommandKind::Unknown, c.kind);
    TEST_ASSERT_EQUAL(op, c.opcode);
  }
}

void test_sync_time_little_endian() {
  // 2026-10-18T00:00:00Z = 1792281600000 ms = 0x1A14C4EE000
  uint64_t ms = 1792281600000ull;
  uint8_t buf[9] = {0x03};
  for (int i = 0; i < 8; ++i) buf[1 + i] = static_cast<uint8_t>(ms >> (8 * i));
  Command c = parseControl(buf, sizeof buf);
  TEST_ASSERT_EQUAL(CommandKind::SyncTime, c.kind);
  TEST_ASSERT_TRUE(c.unixMs == ms);
  Command top = (parse({0x03, 0, 0, 0, 0, 0, 0, 0, 0x80}));
  TEST_ASSERT_TRUE(top.unixMs == 0x8000000000000000ull);
}

void test_set_rate_value() {
  TEST_ASSERT_EQUAL(50, (parse({0x04, 50}).rateHz));
  TEST_ASSERT_EQUAL(25, (parse({0x04, 25}).rateHz));
  TEST_ASSERT_EQUAL(50, kSupportedRateHz);
}

void test_tare_takes_min_over_one_stride() {
  Tare tare;
  Sample s = {};
  TEST_ASSERT_FALSE(tare.feed(s));  // not active: ignored
  TEST_ASSERT_TRUE(tare.begin(6));
  TEST_ASSERT_FALSE(tare.begin(6));  // already running
  for (int i = 0; i < Tare::kWindowSamples; ++i) {
    for (uint8_t c = 0; c < 6; ++c) s.fsr[c] = static_cast<uint16_t>(100 + c * 10 + (i % 7));
    if (i == 20) s.fsr[2] = 5;
    bool done = tare.feed(s);
    TEST_ASSERT_EQUAL(i == Tare::kWindowSamples - 1, done);
  }
  TEST_ASSERT_FALSE(tare.active());
  const uint16_t want[6] = {100, 110, 5, 130, 140, 150};
  TEST_ASSERT_EQUAL_UINT16_ARRAY(want, tare.offsets(), 6);
  TEST_ASSERT_EQUAL(0, tare.offsets()[6]);  // unused channels
  TEST_ASSERT_TRUE(tare.begin(6));          // can run again
}

void test_tare_on_walking_gives_unloaded_baseline() {
  // Any start phase, both feet, N = 4/6/8: one stride always includes swing,
  // so every offset is the unloaded reading (synth baseline 30 +- noise 12),
  // never a loaded one.
  for (uint8_t n : {4, 6, 8}) {
    for (uint8_t side : {0, 1}) {
      for (uint32_t start = 0; start < 5000; start += 260) {
        Tare tare;
        tare.begin(n);
        uint32_t t = start;
        while (!tare.feed(synth::gaitSample(t, side, n))) t += kSamplePeriodMs;
        for (uint8_t c = 0; c < n; ++c) {
          TEST_ASSERT_TRUE(tare.offsets()[c] >= 18);
          TEST_ASSERT_TRUE(tare.offsets()[c] <= 42);
        }
      }
    }
  }
}

}  // namespace

void setUp() {}
void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_opcodes_with_exact_length);
  RUN_TEST(test_wrong_length_is_malformed);
  RUN_TEST(test_unknown_opcodes);
  RUN_TEST(test_sync_time_little_endian);
  RUN_TEST(test_set_rate_value);
  RUN_TEST(test_tare_takes_min_over_one_stride);
  RUN_TEST(test_tare_on_walking_gives_unloaded_baseline);
  return UNITY_END();
}

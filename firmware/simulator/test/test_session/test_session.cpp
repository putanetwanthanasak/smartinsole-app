// Per-connection streaming: packet sizing by MTU, seq/t0, temperature
// cadence, and that sessions never affect each other (needed for S2C's two
// concurrent centrals).
#include <unity.h>

#include "stream_session.h"
#include "synth.h"

using namespace insole;

namespace {

uint16_t u16(const uint8_t* p) { return p[0] | p[1] << 8; }
uint32_t u32(const uint8_t* p) { return u16(p) | static_cast<uint32_t>(u16(p + 2)) << 16; }

// Feeds samples on the 20 ms grid; returns how many packets came out.
int feed(StreamSession& s, uint32_t& t, int samples, uint8_t n, OutPacket* last = nullptr) {
  int packets = 0;
  OutPacket out;
  for (int i = 0; i < samples; ++i, t += kSamplePeriodMs) {
    if (s.addSample(synth::gaitSample(t, 0, n), t, n, out)) {
      ++packets;
      if (last) *last = out;
    }
  }
  return packets;
}

void test_samples_per_packet_by_mtu() {
  TEST_ASSERT_EQUAL(8, samplesPerPacket(247, 6));  // 200 <= 244
  TEST_ASSERT_EQUAL(8, samplesPerPacket(203, 6));  // 200 <= 200
  TEST_ASSERT_EQUAL(4, samplesPerPacket(202, 6));  // 200 > 199
  TEST_ASSERT_EQUAL(4, samplesPerPacket(185, 6));  // 104 <= 182
  TEST_ASSERT_EQUAL(0, samplesPerPacket(106, 6));  // 104 > 103
  TEST_ASSERT_EQUAL(0, samplesPerPacket(23, 6));   // default ATT MTU
  TEST_ASSERT_EQUAL(8, samplesPerPacket(247, 8));  // 232 <= 244
  TEST_ASSERT_EQUAL(8, samplesPerPacket(247, 4));
}

void check_exact_size(uint16_t mtu, uint8_t n, size_t wantLen, uint8_t wantCount) {
  StreamSession s;
  s.open(1);
  s.mtu = mtu;
  s.start(0);
  uint32_t t = 1000;
  OutPacket out;
  TEST_ASSERT_EQUAL(3, feed(s, t, wantCount * 3, n, &out));
  TEST_ASSERT_EQUAL(wantLen, out.len);
  TEST_ASSERT_EQUAL(wantCount, out.bytes[6]);
  TEST_ASSERT_EQUAL(sensorPacketSize(out.bytes[6], n), out.len);  // never padded
}

void test_packet_is_exactly_its_count() {
  check_exact_size(247, 6, 200, 8);
  check_exact_size(185, 6, 104, 4);
  check_exact_size(247, 4, 168, 8);
  check_exact_size(247, 8, 232, 8);
}

void test_mtu_too_small_sends_nothing() {
  StreamSession s;
  s.open(1);
  s.start(0);  // mtu still 23
  uint32_t t = 0;
  TEST_ASSERT_EQUAL(0, feed(s, t, 80, 6));
  TEST_ASSERT_EQUAL(80, s.samplesDroppedForMtu);
}

void test_seq_t0_and_wrap() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  uint32_t t = 5000;
  OutPacket out;
  OutPacket prev;
  bool first = true;
  for (int p = 0; p < 65537; ++p) {
    TEST_ASSERT_EQUAL(1, feed(s, t, 8, 6, &out));
    if (first) {
      TEST_ASSERT_EQUAL(0, u16(out.bytes));
      TEST_ASSERT_EQUAL(5000, u32(out.bytes + 2));
      first = false;
    } else {
      TEST_ASSERT_EQUAL_UINT16(static_cast<uint16_t>(u16(prev.bytes) + 1), u16(out.bytes));
      TEST_ASSERT_EQUAL_UINT32(u32(prev.bytes + 2) + 8 * kSamplePeriodMs, u32(out.bytes + 2));
    }
    prev = out;
  }
  TEST_ASSERT_EQUAL(0, u16(out.bytes));  // 65536 mod 65536
}

void test_not_streaming_sends_nothing() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  uint32_t t = 0;
  TEST_ASSERT_EQUAL(0, feed(s, t, 64, 6));
  s.start(t);
  TEST_ASSERT_EQUAL(8, feed(s, t, 64, 6));
  s.stop();
  TEST_ASSERT_EQUAL(0, feed(s, t, 64, 6));
}

void test_restart_resets_seq_and_drops_partial() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  uint32_t t = 0;
  OutPacket out;
  feed(s, t, 8 * 5 + 3, 6, &out);  // 5 packets + 3 buffered
  s.stop();
  s.start(t);
  TEST_ASSERT_EQUAL(1, feed(s, t, 8, 6, &out));
  TEST_ASSERT_EQUAL(0, u16(out.bytes));
  TEST_ASSERT_EQUAL(t - 8 * kSamplePeriodMs, u32(out.bytes + 2));
}

void test_temperature_at_start_then_every_30s() {
  StreamSession s;
  s.open(1);
  TemperatureReading r = synth::temperature(0, 0);
  OutPacket out;
  TEST_ASSERT_FALSE(s.temperatureDue(0, r, out));  // not streaming
  s.start(1000);
  TEST_ASSERT_TRUE(s.temperatureDue(1000, r, out));
  TEST_ASSERT_EQUAL(kTemperatureBytes, out.len);
  TEST_ASSERT_EQUAL(0, u16(out.bytes));
  TEST_ASSERT_FALSE(s.temperatureDue(1020, r, out));
  TEST_ASSERT_FALSE(s.temperatureDue(30999, r, out));
  TEST_ASSERT_TRUE(s.temperatureDue(31000, r, out));
  TEST_ASSERT_EQUAL(1, u16(out.bytes));
  TEST_ASSERT_EQUAL(31000, u32(out.bytes + 2));
}

void test_sessions_are_independent() {
  SessionTable table;
  StreamSession* a = table.open(10);
  StreamSession* b = table.open(11);
  TEST_ASSERT_NOT_NULL(a);
  TEST_ASSERT_NOT_NULL(b);
  TEST_ASSERT_TRUE(a != b);
  a->mtu = b->mtu = 247;
  a->start(0);
  b->start(0);
  TEST_ASSERT_TRUE(table.anyStreaming());

  uint32_t ta = 0, tb = 0;
  a->stop();  // A sends STOP_STREAM
  TEST_ASSERT_EQUAL(0, feed(*a, ta, 16, 6));
  TEST_ASSERT_EQUAL(2, feed(*b, tb, 16, 6));
  TEST_ASSERT_TRUE(table.anyStreaming());

  table.close(10);  // A disconnects
  TEST_ASSERT_NULL(table.find(10));
  TEST_ASSERT_EQUAL(b, table.find(11));
  TEST_ASSERT_EQUAL(2, feed(*b, tb, 16, 6));
  TEST_ASSERT_TRUE(table.anyStreaming());

  table.close(11);
  TEST_ASSERT_FALSE(table.anyStreaming());
}

void test_table_full_and_reuse() {
  SessionTable table;
  for (int i = 0; i < SessionTable::kMaxSessions; ++i) TEST_ASSERT_NOT_NULL(table.open(i));
  TEST_ASSERT_NULL(table.open(99));
  TEST_ASSERT_EQUAL(table.find(1), table.open(1));  // same conn -> same session
  table.close(1);
  StreamSession* s = table.open(99);
  TEST_ASSERT_NOT_NULL(s);
  TEST_ASSERT_FALSE(s->streaming());
  TEST_ASSERT_EQUAL(StreamSession::kDefaultMtu, s->mtu);
}

void test_saturated_flag() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  Sample sat = synth::gaitSample(0, 0, 6);
  sat.fsr[2] = 4095;
  OutPacket out;
  for (int i = 0; i < 8; ++i) s.addSample(i == 3 ? sat : synth::gaitSample(0, 0, 6), i * 20, 6, out);
  TEST_ASSERT_EQUAL(kFlagSaturated, out.bytes[7]);
}

void test_repeated_start_keeps_seq() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  TEST_ASSERT_TRUE(s.start(0));
  uint32_t t = 0;
  OutPacket out;
  feed(s, t, 8 * 3 + 2, 6, &out);  // seq 0..2 sent, 2 samples buffered
  TEST_ASSERT_FALSE(s.start(t));   // second START: no change
  TEST_ASSERT_EQUAL(1, feed(s, t, 6, 6, &out));
  TEST_ASSERT_EQUAL(3, u16(out.bytes));  // continues, not back to 0
  TEST_ASSERT_EQUAL(t - 8 * kSamplePeriodMs, u32(out.bytes + 2));
}

void test_calibrating_flag() {
  StreamSession s;
  s.open(1);
  s.mtu = 247;
  s.start(0);
  OutPacket out;
  // One calibrating sample anywhere in a packet sets bit1 on that packet.
  for (int i = 0; i < 8; ++i) s.addSample(synth::gaitSample(i * 20, 0, 6), i * 20, 6, out, i == 7);
  TEST_ASSERT_EQUAL(kFlagCalibrating, out.bytes[7]);
  // The next packet without one is clear again.
  for (int i = 8; i < 16; ++i) s.addSample(synth::gaitSample(i * 20, 0, 6), i * 20, 6, out, false);
  TEST_ASSERT_EQUAL(0, out.bytes[7]);
}

}  // namespace

void setUp() {}
void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_samples_per_packet_by_mtu);
  RUN_TEST(test_packet_is_exactly_its_count);
  RUN_TEST(test_mtu_too_small_sends_nothing);
  RUN_TEST(test_seq_t0_and_wrap);
  RUN_TEST(test_not_streaming_sends_nothing);
  RUN_TEST(test_restart_resets_seq_and_drops_partial);
  RUN_TEST(test_temperature_at_start_then_every_30s);
  RUN_TEST(test_sessions_are_independent);
  RUN_TEST(test_table_full_and_reuse);
  RUN_TEST(test_saturated_flag);
  RUN_TEST(test_repeated_start_keeps_seq);
  RUN_TEST(test_calibrating_flag);
  return UNITY_END();
}

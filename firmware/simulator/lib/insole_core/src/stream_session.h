// Streaming state, kept per connection rather than globally. One central's
// STOP_STREAM or disconnect only ever touches its own session, so the stream
// to any other central carries on. S2C raises the connection limit to two
// centrals without changing this file.
#pragma once

#include "packets.h"

namespace insole {

// Samples per sensor packet for a link MTU: 8 if they fit one notification,
// else 4 (contract §2.3 fallback), else 0 (cannot stream; never truncate).
uint8_t samplesPerPacket(uint16_t mtu, uint8_t fsrCount);

struct OutPacket {
  uint8_t bytes[kMaxSensorPacketBytes];
  size_t len = 0;
};

class StreamSession {
 public:
  static constexpr uint16_t kNoConnection = 0xffff;
  static constexpr uint16_t kDefaultMtu = 23;

  uint16_t connHandle = kNoConnection;
  uint16_t mtu = kDefaultMtu;
  bool sensorSubscribed = false;
  bool temperatureSubscribed = false;
  bool statusSubscribed = false;

  // Counters for the serial log; never reset while connected.
  uint32_t packetsSent = 0;
  uint32_t samplesDroppedForMtu = 0;

  bool inUse() const { return connHandle != kNoConnection; }
  bool streaming() const { return streaming_; }

  void open(uint16_t conn);  // on connect: fresh state, not streaming
  void close();              // on disconnect

  // START_STREAM: seq restarts at 0, a temperature packet is due at once.
  void start(uint32_t nowMs);
  // STOP_STREAM: drops any half-filled packet.
  void stop();

  // Adds one sample taken at device time `tMs`. When a packet is complete,
  // writes it to `out` and returns true. Does nothing unless streaming.
  bool addSample(const Sample& s, uint32_t tMs, uint8_t fsrCount, OutPacket& out);

  // Writes a temperature packet to `out` (len 12) when one is due.
  bool temperatureDue(uint32_t nowMs, const TemperatureReading& r, OutPacket& out);

 private:
  bool streaming_ = false;
  uint16_t seq_ = 0;
  uint16_t tempSeq_ = 0;
  uint32_t nextTempMs_ = 0;
  uint8_t fill_ = 0;
  uint8_t target_ = 0;  // samples in the packet being filled
  uint32_t t0_ = 0;
  Sample buf_[kSamplesPerPacket] = {};
};

class SessionTable {
 public:
  static constexpr int kMaxSessions = 3;

  StreamSession* open(uint16_t conn);  // nullptr if full
  StreamSession* find(uint16_t conn);
  void close(uint16_t conn);
  bool anyStreaming() const;

  StreamSession* begin() { return sessions_; }
  StreamSession* end() { return sessions_ + kMaxSessions; }

 private:
  StreamSession sessions_[kMaxSessions];
};

}  // namespace insole

#include "stream_session.h"

namespace insole {

uint8_t samplesPerPacket(uint16_t mtu, uint8_t fsrCount) {
  if (mtu < kAttHeaderBytes) return 0;
  size_t payload = mtu - kAttHeaderBytes;
  if (sensorPacketSize(kSamplesPerPacket, fsrCount) <= payload) return kSamplesPerPacket;
  if (sensorPacketSize(kFallbackSamplesPerPacket, fsrCount) <= payload)
    return kFallbackSamplesPerPacket;
  return 0;
}

void StreamSession::open(uint16_t conn) {
  *this = StreamSession();
  connHandle = conn;
}

void StreamSession::close() { *this = StreamSession(); }

bool StreamSession::start(uint32_t nowMs) {
  if (streaming_) return false;
  streaming_ = true;
  seq_ = 0;
  tempSeq_ = 0;
  nextTempMs_ = nowMs;
  fill_ = 0;
  return true;
}

void StreamSession::stop() {
  streaming_ = false;
  fill_ = 0;
}

bool StreamSession::addSample(const Sample& s, uint32_t tMs, uint8_t fsrCount,
                              OutPacket& out, bool calibrating) {
  if (!streaming_) return false;
  if (fill_ == 0) {
    // The packet size is fixed when its first sample arrives, from the MTU
    // in force then.
    target_ = samplesPerPacket(mtu, fsrCount);
    if (target_ == 0) {
      ++samplesDroppedForMtu;
      return false;
    }
    t0_ = tMs;
    calibrating_ = false;
  }
  calibrating_ |= calibrating;
  buf_[fill_++] = s;
  if (fill_ < target_) return false;

  uint8_t flags = calibrating_ ? kFlagCalibrating : 0;
  for (uint8_t i = 0; i < fill_; ++i)
    for (uint8_t c = 0; c < fsrCount; ++c)
      if (buf_[i].fsr[c] >= 4095) flags |= kFlagSaturated;

  out.len = encodeSensor(out.bytes, seq_, t0_, flags, buf_, fill_, fsrCount);
  ++seq_;  // uint16_t: wraps 65535 -> 0
  fill_ = 0;
  if (out.len > static_cast<size_t>(mtu - kAttHeaderBytes)) {
    // The MTU shrank while this packet was filling: drop it rather than let
    // the stack truncate it.
    samplesDroppedForMtu += target_;
    return false;
  }
  ++packetsSent;
  return true;
}

bool StreamSession::temperatureDue(uint32_t nowMs, const TemperatureReading& r,
                                   OutPacket& out) {
  if (!streaming_ || static_cast<int32_t>(nowMs - nextTempMs_) < 0) return false;
  out.len = encodeTemperature(out.bytes, tempSeq_++, nowMs, r);
  nextTempMs_ += kTemperaturePeriodMs;
  return true;
}

StreamSession* SessionTable::open(uint16_t conn) {
  if (StreamSession* s = find(conn)) return s;
  for (StreamSession& s : sessions_) {
    if (!s.inUse()) {
      s.open(conn);
      return &s;
    }
  }
  return nullptr;
}

StreamSession* SessionTable::find(uint16_t conn) {
  for (StreamSession& s : sessions_)
    if (s.inUse() && s.connHandle == conn) return &s;
  return nullptr;
}

void SessionTable::close(uint16_t conn) {
  if (StreamSession* s = find(conn)) s->close();
}

bool SessionTable::anyStreaming() const {
  for (const StreamSession& s : sessions_)
    if (s.inUse() && s.streaming()) return true;
  return false;
}

}  // namespace insole

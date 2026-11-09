#include "insole_frames.h"

namespace insole_hw {

insole::TemperatureReading noNtcReading() {
  insole::TemperatureReading r{};
  for (uint8_t i = 0; i < insole::kTempSiteCount; ++i) {
    r.temp[i] = insole::kTempUnreadable;
    r.quality[i] = 2;
  }
  return r;
}

insole::Sample makeSample(const uint16_t counts[kCalChannels], const int16_t accelChip[3],
                          const int16_t gyroChip[3], const AxisMap& axes) {
  insole::Sample s{};
  for (uint8_t c = 0; c < kCalChannels; ++c) s.fsr[c] = counts[c];
  remap(axes, accelChip, s.accel);
  remap(axes, gyroChip, s.gyro);
  return s;
}

bool SaturationFlag::add(insole::StreamSession& s, const insole::Sample& sample, bool saturated,
                         uint32_t tMs, uint8_t fsrCount, insole::OutPacket& out,
                         bool calibrating) {
  if (!s.streaming()) {
    pending_ = false;
    return false;
  }
  uint32_t droppedBefore = s.samplesDroppedForMtu;
  pending_ = pending_ || saturated;
  bool ready = s.addSample(sample, tMs, fsrCount, out, calibrating);
  if (ready) {
    if (pending_) out.bytes[7] |= insole::kFlagSaturated;  // header byte 7: flags
    pending_ = false;
  } else if (s.samplesDroppedForMtu != droppedBefore) {
    pending_ = false;  // the packet it belonged to was dropped
  }
  return ready;
}

}  // namespace insole_hw

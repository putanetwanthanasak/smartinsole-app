#include "packets.h"

namespace insole {
namespace {

uint8_t* putU16(uint8_t* p, uint16_t v) {
  p[0] = static_cast<uint8_t>(v);
  p[1] = static_cast<uint8_t>(v >> 8);
  return p + 2;
}

uint8_t* putI16(uint8_t* p, int16_t v) { return putU16(p, static_cast<uint16_t>(v)); }

uint8_t* putU32(uint8_t* p, uint32_t v) {
  p = putU16(p, static_cast<uint16_t>(v));
  return putU16(p, static_cast<uint16_t>(v >> 16));
}

}  // namespace

size_t encodeSensor(uint8_t* out, uint16_t seq, uint32_t t0Ms, uint8_t flags,
                    const Sample* samples, uint8_t count, uint8_t fsrCount) {
  uint8_t* p = putU16(out, seq);
  p = putU32(p, t0Ms);
  *p++ = count;
  *p++ = flags;
  for (uint8_t i = 0; i < count; ++i) {
    const Sample& s = samples[i];
    for (uint8_t c = 0; c < fsrCount; ++c) p = putU16(p, s.fsr[c]);
    for (int16_t v : s.accel) p = putI16(p, v);
    for (int16_t v : s.gyro) p = putI16(p, v);
  }
  return static_cast<size_t>(p - out);
}

size_t encodeTemperature(uint8_t* out, uint16_t seq, uint32_t tMs,
                         const TemperatureReading& reading) {
  uint8_t* p = putU16(out, seq);
  p = putU32(p, tMs);
  *p++ = kTempSiteCount;  // count
  *p++ = 0;               // reserved
  for (int16_t v : reading.temp) p = putI16(p, v);
  for (uint8_t q : reading.quality) *p++ = q;
  return static_cast<size_t>(p - out);
}

size_t encodeStatus(uint8_t* out, const DeviceStatus& status) {
  uint8_t* p = out;
  *p++ = status.batteryPct;
  p = putU16(p, status.batteryMv);
  *p++ = status.footSide;
  *p++ = status.fwMajor;
  *p++ = status.fwMinor;
  *p++ = static_cast<uint8_t>(status.state);
  *p++ = status.errorCode;
  return static_cast<size_t>(p - out);
}

}  // namespace insole

#include "mpu6050.h"

#include <Arduino.h>
#include <Wire.h>

#include "config.h"

namespace imu {
namespace {

constexpr uint8_t kSmplrtDiv = 0x19;
constexpr uint8_t kConfig = 0x1A;
constexpr uint8_t kGyroConfig = 0x1B;
constexpr uint8_t kAccelConfig = 0x1C;
constexpr uint8_t kAccelXoutH = 0x3B;
constexpr uint8_t kPwrMgmt1 = 0x6B;
constexpr uint8_t kWhoAmI = 0x75;

bool write(uint8_t reg, uint8_t v) {
  Wire.beginTransmission(config::kMpuAddress);
  Wire.write(reg);
  Wire.write(v);
  return Wire.endTransmission() == 0;
}

int readByte(uint8_t reg) {
  Wire.beginTransmission(config::kMpuAddress);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return -1;
  if (Wire.requestFrom(config::kMpuAddress, static_cast<uint8_t>(1)) != 1) return -1;
  return Wire.read();
}

}  // namespace

bool begin() {
  Wire.begin(config::kPinSda, config::kPinScl, 400000);
  Wire.setTimeOut(3);  // ms: a stuck bus must not stall the 50 Hz tick
  return configure();
}

bool configure() {
  int who = readByte(kWhoAmI);
  bool ok = who == 0x68 &&
            write(kPwrMgmt1, 0x01) &&     // wake, clock from the X gyro PLL
            write(kSmplrtDiv, 0x00) &&    // 1 kHz with the DLPF on
            write(kConfig, 0x04) &&       // DLPF_CFG 4: accel 21 Hz, gyro 20 Hz
            write(kGyroConfig, 0x10) &&   // FS_SEL 2: +-1000 deg/s, 32.8 LSB/(deg/s)
            write(kAccelConfig, 0x10);    // AFS_SEL 2: +-8 g, 4096 LSB/g
  Serial.printf("[imu] MPU6050 at 0x%02x: WHO_AM_I 0x%02x, %s\n", config::kMpuAddress,
                who < 0 ? 0 : who, ok ? "configured" : "NOT RESPONDING (error_code 1)");
  return ok;
}

bool read(int16_t accel[3], int16_t gyro[3]) {
  Wire.beginTransmission(config::kMpuAddress);
  Wire.write(kAccelXoutH);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(config::kMpuAddress, static_cast<uint8_t>(14)) != 14) return false;
  uint8_t b[14];
  for (uint8_t& v : b) v = static_cast<uint8_t>(Wire.read());
  auto be = [&](int i) { return static_cast<int16_t>(b[i] << 8 | b[i + 1]); };
  for (int i = 0; i < 3; ++i) {
    accel[i] = be(2 * i);
    gyro[i] = be(8 + 2 * i);  // bytes 6-7 are the chip's temperature
  }
  return true;
}

}  // namespace imu

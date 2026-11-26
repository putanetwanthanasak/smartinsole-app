// MPU6050 over I2C, set to the contract's scales (§5.2): accel +-8 g
// (4096 LSB/g), gyro +-1000 deg/s (32.8 LSB/(deg/s)). Internal rate 1 kHz with
// the ~20 Hz low-pass (DLPF_CFG 4), so nothing above 25 Hz aliases into the
// 50 Hz samples; read once per tick, so a reading is at most 1 ms old.
#pragma once

#include <cstdint>

namespace imu {

// Starts I2C and configures the chip; false if it does not answer
// WHO_AM_I 0x68.
bool begin();

// Configures the chip again (after read errors), on the bus begin() started.
// Same task as read(). Up to ~20 ms if the chip is absent.
bool configure();

// Burst-reads accel and gyro (chip axes, raw). False on an I2C error; the
// caller then sends zeros and error_code 1 (contract Appendix A).
bool read(int16_t accel[3], int16_t gyro[3]);

}  // namespace imu

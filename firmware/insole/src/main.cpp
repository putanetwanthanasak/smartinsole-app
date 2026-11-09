// SmartInsole firmware for the hardware team's real insole (FW-1, report
// 043): ESP32-C3, 8 Velostat sensors through a 16-channel mux, MPU6050.
// Same BLE protocol core as the simulator (../simulator/lib/insole_core).
// One board = one foot, chosen at build time (platformio.ini envs).
#include <Arduino.h>

#include <atomic>
#include <cstring>

#include "ble_server.h"
#include "cal_store.h"
#include "config.h"
#include "fsr_mux.h"
#include "insole_frames.h"
#include "mpu6050.h"

namespace {

constexpr uint32_t kTicksPerSecond = 1000 / insole::kSamplePeriodMs;
constexpr uint32_t kLogEverySeconds = 10;
constexpr uint32_t kImuRetrySeconds = 5;
// Contract Appendix A: 1 = IMU not responding.
constexpr uint8_t kErrorImu = 1;

std::atomic<bool> gRawLog{false};
bool gImuOk = false;

// Once a second with `raw on`: the 1 s mean of each site in the wire unit,
// for the calibration bench (report 043, calibration track).
struct RawMean {
  uint32_t sum[8] = {};
  uint16_t min[8], max[8];
  uint8_t lowMask = 0;
  bool saturated = false;
  uint32_t n = 0;
  void add(const fsr::Frame& f) {
    for (int i = 0; i < 8; ++i) {
      sum[i] += f.counts[i];
      if (n == 0 || f.counts[i] < min[i]) min[i] = f.counts[i];
      if (n == 0 || f.counts[i] > max[i]) max[i] = f.counts[i];
    }
    lowMask |= f.lowRangeMask;
    saturated = saturated || f.saturated;
    ++n;
  }
  void print(uint32_t tMs) {
    Serial.printf("[raw] t %lu n %lu mean", static_cast<unsigned long>(tMs),
                  static_cast<unsigned long>(n));
    for (int i = 0; i < 8; ++i) Serial.printf(" %lu", static_cast<unsigned long>((sum[i] + n / 2) / n));
    Serial.printf(" min");
    for (int i = 0; i < 8; ++i) Serial.printf(" %u", min[i]);
    Serial.printf(" max");
    for (int i = 0; i < 8; ++i) Serial.printf(" %u", max[i]);
    Serial.printf(" low 0x%02x sat %d\n", lowMask, saturated ? 1 : 0);
    *this = RawMean();
  }
};

// 50 Hz sample clock. vTaskDelayUntil keeps a fixed phase, so sample k's
// device time is exactly epoch + k * 20 ms and never drifts (rule 1). Reads
// the 8 sites (about 2 ms), then the IMU (one 14-byte burst), so the IMU
// reading is at most ~2 ms after the pressure reading.
void tickTask(void*) {
  const TickType_t period = pdMS_TO_TICKS(insole::kSamplePeriodMs);
  TickType_t wake = xTaskGetTickCount();
  uint32_t tMs = millis();
  uint32_t tick = 0;
  RawMean raw;
  const insole_hw::AxisMap& axes = config::kAxisMap[config::kFootSide];
  for (;;) {
    fsr::Frame f;
    fsr::read(f);
    int16_t accel[3] = {0, 0, 0}, gyro[3] = {0, 0, 0};
    if (gImuOk && !imu::read(accel, gyro)) {
      gImuOk = false;
      accel[0] = accel[1] = accel[2] = gyro[0] = gyro[1] = gyro[2] = 0;
      Serial.printf("[imu] read failed: zeros and error_code %u until it answers\n", kErrorImu);
    }
    ble::pushSample(insole_hw::makeSample(f.counts, accel, gyro, axes), f.saturated, tMs);
    if (gRawLog.load()) raw.add(f);

    if (++tick % kTicksPerSecond == 0) {
      uint32_t seconds = tick / kTicksPerSecond;
      if (!gImuOk && seconds % kImuRetrySeconds == 0) gImuOk = imu::configure();
      ble::updateStatus(gImuOk ? 0 : kErrorImu);
      if (gRawLog.load() && raw.n > 0) raw.print(tMs);
      if (seconds % kLogEverySeconds == 0) ble::logSessions();
    }
    vTaskDelayUntil(&wake, period);
    tMs += insole::kSamplePeriodMs;
  }
}

void printCalibration(const char* prefix) {
  char buf[insole_hw::kMaxCalibrationBytes + 1];
  size_t n = cal_store::json(buf, sizeof buf);
  Serial.printf("%s%.*s\n", prefix, static_cast<int>(n), buf);
}

void printHelp() {
  Serial.printf("[cmd] cal | cal set <json> | cal test | raw on | raw off | ?\n");
}

// Line commands. `cal set` answers with the stored JSON on one line starting
// "[cal] stored ", which the laptop tool compares byte for byte with what it
// sent (the board stores a and area at 6 significant digits, b at 4).
void handleLine(char* line) {
  if (std::strcmp(line, "cal") == 0) {
    printCalibration("[cal] current ");
  } else if (std::strncmp(line, "cal set ", 8) == 0) {
    const char* json = line + 8;
    insole_hw::CalData cal;
    insole_hw::CalError e = insole_hw::parseCalibration(json, std::strlen(json), cal);
    if (e != insole_hw::CalError::None) {
      Serial.printf("[cal] refused: %s (nothing changed)\n", insole_hw::calErrorText(e));
      return;
    }
    bool saved = cal_store::replace(cal);
    ble::republishCalibration();
    if (!saved) Serial.printf("[cal] WARNING: NVS save failed; lost at reboot\n");
    printCalibration("[cal] stored ");
  } else if (std::strcmp(line, "cal test") == 0) {
    bool saved = cal_store::resetToTest();
    ble::republishCalibration();
    if (!saved) Serial.printf("[cal] WARNING: NVS save failed\n");
    printCalibration("[cal] stored ");
  } else if (std::strcmp(line, "raw on") == 0) {
    gRawLog.store(true);
    Serial.printf("[raw] on: 1 s mean/min/max per site (wire unit), low-range mask, saturated\n");
  } else if (std::strcmp(line, "raw off") == 0) {
    gRawLog.store(false);
    Serial.printf("[raw] off\n");
  } else if (line[0] != '\0') {
    printHelp();
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);  // logging never stalls the 50 Hz task (HWCDC)
  delay(200);
  Serial.printf("\n[boot] SmartInsole FW-1 fw %u.%u, side %s, %u sites\n", config::kFwMajor,
                config::kFwMinor, config::kFootSide == 0 ? "L" : "R", config::kFsrCount);
  if (config::kBuildCheck) {
    // Placeholder pins: touch nothing (no pin, no radio). Never flashed: the
    // upload guard refuses this env.
    Serial.printf("[boot] BUILD CHECK image: pin map not filled in. Halted.\n");
    for (;;) delay(1000);
  }
  if (config::kPinSdCs != config::kNoPin) {
    pinMode(config::kPinSdCs, OUTPUT);
    digitalWrite(config::kPinSdCs, HIGH);  // SD card not used: keep it off the bus
  }
  if (!fsr::begin(config::kFootSide))
    Serial.printf("[adc] WARNING: no factory calibration; readings are not trustworthy\n");
  gImuOk = imu::begin();
  cal_store::begin(config::kFootSide);
  ble::begin();
  printHelp();
  xTaskCreate(tickTask, "tick", 6144, nullptr, 5, nullptr);
}

void loop() {
  static char line[insole_hw::kMaxCalibrationBytes + 64];
  static size_t len = 0;
  static bool overflow = false;
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r') continue;
    if (c == '\n') {
      line[len] = '\0';
      if (overflow)
        Serial.printf("[cmd] line longer than %u bytes, ignored\n",
                      static_cast<unsigned>(sizeof line - 1));
      else
        handleLine(line);
      len = 0;
      overflow = false;
    } else if (len < sizeof line - 1) {
      line[len++] = c;
    } else {
      overflow = true;
    }
  }
  vTaskDelay(pdMS_TO_TICKS(20));
}

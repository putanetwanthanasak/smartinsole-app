#include "cal_store.h"

#include <Arduino.h>
#include <Preferences.h>

#include "config.h"

namespace cal_store {
namespace {

// Our own namespace: the hardware team's sketch may have left NVS entries.
constexpr const char* kNamespace = "fw1cal";
constexpr const char* kKey = "cal";
constexpr uint32_t kMagic = 0x43414C31;  // "CAL1"

struct Stored {
  uint32_t magic;
  uint32_t size;
  insole_hw::CalData data;
};

uint8_t gSide = 1;
insole_hw::CalData gCal;
SemaphoreHandle_t gLock = nullptr;

struct Lock {
  Lock() { xSemaphoreTake(gLock, portMAX_DELAY); }
  ~Lock() { xSemaphoreGive(gLock); }
};

bool save() {
  Preferences nvs;
  if (!nvs.begin(kNamespace, false)) return false;
  Stored s{kMagic, sizeof(insole_hw::CalData), gCal};
  bool ok = nvs.putBytes(kKey, &s, sizeof s) == sizeof s;
  nvs.end();
  return ok;
}

insole_hw::CalData testCal() {
  return insole_hw::testCalibration(gSide, config::kPulldownOhm, config::kSensorAreaM2);
}

}  // namespace

void begin(uint8_t footSide) {
  gLock = xSemaphoreCreateMutex();
  gSide = footSide;
  gCal = testCal();
  Preferences nvs;
  bool loaded = false;
  if (nvs.begin(kNamespace, true)) {
    Stored s;
    if (nvs.getBytesLength(kKey) == sizeof s && nvs.getBytes(kKey, &s, sizeof s) == sizeof s &&
        s.magic == kMagic && s.size == sizeof(insole_hw::CalData)) {
      char buf[insole_hw::kMaxCalibrationBytes + 1];
      // Only what would serve as valid JSON is used.
      if (insole_hw::buildCalibrationJson(s.data, buf, sizeof buf) > 0) {
        gCal = s.data;
        loaded = true;
      }
    }
    nvs.end();
  }
  Serial.printf("[cal] %s: device_id %s%s\n", loaded ? "loaded from NVS" : "test values",
                gCal.deviceId,
                insole_hw::isTestCalibration(gCal) ? " (TEST: never for study data)" : "");
}

insole_hw::CalData current() {
  Lock l;
  return gCal;
}

size_t json(char* out, size_t cap) {
  Lock l;
  return insole_hw::buildCalibrationJson(gCal, out, cap);
}

bool replace(const insole_hw::CalData& cal) {
  Lock l;
  gCal = cal;
  return save();
}

bool setOffsets(const uint16_t offsets[insole_hw::kCalChannels]) {
  Lock l;
  for (uint8_t c = 0; c < insole_hw::kCalChannels; ++c) gCal.ch[c].offsetAdc = offsets[c];
  return save();
}

bool resetToTest() {
  Lock l;
  gCal = testCal();
  return save();
}

}  // namespace cal_store

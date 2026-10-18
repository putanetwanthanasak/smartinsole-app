// SmartInsole BLE simulator (docs/BLE-INTERFACE.md). One board = one foot,
// chosen at build time (platformio.ini envs `left` / `right`).
#include <Arduino.h>

#include "ble_server.h"
#include "config.h"
#include "synth.h"

namespace {

// The only place the data source is chosen; a scenario mode replaces this.
const insole::DataSource& gSource = insole::synth::walking();

constexpr uint32_t kTicksPerSecond = 1000 / insole::kSamplePeriodMs;
constexpr uint32_t kLogEverySeconds = 10;

// 50 Hz sample clock. vTaskDelayUntil keeps a fixed phase, so sample k's
// device time is exactly epoch + k * 20 ms and never drifts (rule 1).
void tickTask(void*) {
  const TickType_t period = pdMS_TO_TICKS(insole::kSamplePeriodMs);
  TickType_t wake = xTaskGetTickCount();
  uint32_t tMs = millis();
  uint32_t tick = 0;
  for (;;) {
    insole::Sample s = gSource.sample(tMs, config::kFootSide, config::kFsrCount);
    insole::TemperatureReading t = gSource.temperature(tMs, config::kFootSide);
    ble::pushSample(s, t, tMs);

    if (++tick % kTicksPerSecond == 0) {
      ble::updateStatus(gSource.battery(tMs));
      if (tick % (kTicksPerSecond * kLogEverySeconds) == 0) ble::logSessions();
    }
    vTaskDelayUntil(&wake, period);
    tMs += insole::kSamplePeriodMs;
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.printf("\n[boot] SmartInsole simulator fw %u.%u, side %s, fsr_count %u\n",
                config::kFwMajor, config::kFwMinor, config::kFootSide == 0 ? "L" : "R",
                config::kFsrCount);
  ble::begin(config::kFsrCount);
  xTaskCreatePinnedToCore(tickTask, "tick", 6144, nullptr, 5, nullptr, 1);
}

void loop() { vTaskDelay(portMAX_DELAY); }

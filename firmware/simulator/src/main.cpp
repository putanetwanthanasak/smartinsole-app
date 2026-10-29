// SmartInsole BLE simulator (docs/BLE-INTERFACE.md). One board = one foot,
// chosen at build time (platformio.ini envs `left` / `right`).
#include <Arduino.h>

#include <atomic>

#include "ble_server.h"
#include "config.h"
#include "scenario.h"
#include "synth.h"

namespace {

// The data source: the normal walk unless a serial command (loop()) picks
// another scenario. Swapped whole, so a sample never mixes two scenarios.
std::atomic<insole::scenario::Id> gScenario{insole::scenario::Id::normal};

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
    const insole::DataSource& gSource = insole::scenario::source(gScenario.load());
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
  Serial.printf("[scenario] %s  (commands: n t p ?)\n",
                insole::scenario::name(gScenario.load()));
  ble::begin(config::kFsrCount);
  xTaskCreatePinnedToCore(tickTask, "tick", 6144, nullptr, 5, nullptr, 1);
}

// Serial commands (S7 phone check): n normal, t temperature site 1 (MTH1)
// +3 degC, p meta1 ~250 kPa, ? show. Non-blocking; the 50 Hz task never waits.
void loop() {
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    insole::scenario::Id id;
    if (insole::scenario::fromCommand(c, &id)) {
      gScenario.store(id);
      Serial.printf("[scenario] %s\n", insole::scenario::name(id));
    } else if (c == '?') {
      Serial.printf("[scenario] %s  (commands: n t p ?)\n",
                    insole::scenario::name(gScenario.load()));
    }
  }
  vTaskDelay(pdMS_TO_TICKS(50));
}

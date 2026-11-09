// NimBLE glue for the real insole: advertising, the GATT service, connection
// callbacks and per-connection notifications. Adapted from the simulator's
// ble_server (firmware/simulator/src, unchanged) with real data: the
// calibration from NVS, TARE as the 1 s mean with a moved-insole check, the
// saturated flag at the C3's ceiling, temperature v2 "no NTC", battery 255.
#pragma once

#include "packets.h"

namespace ble {

void begin();

// Called by the 50 Hz tick with one sample at device time `tMs`.
// `saturated`: some channel hit the C3's ADC ceiling (packet flags bit0).
void pushSample(const insole::Sample& s, bool saturated, uint32_t tMs);

// Called once a second: refreshes the status value, notifies on change.
void updateStatus(uint8_t errorCode);

// Re-serves the calibration after a serial `cal set` / `cal test`.
void republishCalibration();

// Prints one line per connection to Serial.
void logSessions();

}  // namespace ble

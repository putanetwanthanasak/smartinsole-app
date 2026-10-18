// NimBLE glue: advertising, the GATT service, connection callbacks and
// per-connection notifications. Holds no data generation of its own; main.cpp
// pushes samples in from the DataSource.
#pragma once

#include "data_source.h"

namespace ble {

void begin(uint8_t fsrCount);

// Called by the 50 Hz tick with one sample at device time `tMs`.
void pushSample(const insole::Sample& s, const insole::TemperatureReading& temp, uint32_t tMs);

// Called once a second: refreshes the status value, notifies on change.
void updateStatus(const insole::BatteryReading& battery);

// Prints one line per connection to Serial.
void logSessions();

}  // namespace ble

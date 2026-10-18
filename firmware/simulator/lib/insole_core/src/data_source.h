// Where the simulator's sensor values come from. The BLE code only ever
// calls through a DataSource, so a future scenario mode (0x10 SET_SCENARIO,
// backlog) can swap in a different one without touching the BLE side.
// Every function is pure: same inputs, same outputs, no hidden state.
#pragma once

#include "packets.h"

namespace insole {

struct BatteryReading {
  uint8_t pct;
  uint16_t mv;
};

struct DataSource {
  // One 50 Hz sample at device time `tMs` (ms since boot).
  Sample (*sample)(uint32_t tMs, uint8_t footSide, uint8_t fsrCount);
  TemperatureReading (*temperature)(uint32_t tMs, uint8_t footSide);
  BatteryReading (*battery)(uint32_t tMs);
};

}  // namespace insole

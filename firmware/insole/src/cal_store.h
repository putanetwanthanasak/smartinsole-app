// The calibration in NVS: the hardware team's per-sensor a/b once they exist
// (loaded with the serial `cal set` command), the test values until then,
// and offset_adc from each TARE. Served as compact JSON (cal_json.h).
#pragma once

#include <cstddef>

#include "cal_json.h"

namespace cal_store {

// Every function is safe to call from any task (the tick task saves TARE
// offsets; the serial loop runs `cal set`).

// Loads from NVS, or the test calibration if nothing valid is stored.
void begin(uint8_t footSide);

// A copy: the stored calibration can change under another task.
insole_hw::CalData current();

// Compact JSON of current(); returns its length (0 never happens for data
// that passed parseCalibration or came from testCalibration).
size_t json(char* out, size_t cap);

// Replaces the calibration (validated) and saves it. False if NVS failed.
bool replace(const insole_hw::CalData& cal);

// New offsets from a TARE; saves them.
bool setOffsets(const uint16_t offsets[insole_hw::kCalChannels]);

// Back to the test values (offsets 0); saves.
bool resetToTest();

}  // namespace cal_store

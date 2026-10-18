// Calibration blob served on the Calibration characteristic (Data Contract
// §5.1). Static for now; TARE updating offset_adc and NVS storage are S2C.
#pragma once

#include <cstddef>
#include <cstdint>

namespace insole {

// Writes the JSON text (no NUL counted) into `out`; returns its length, or
// 0 if it would not fit in `cap` or in the 512-byte characteristic.
size_t buildCalibrationJson(char* out, size_t cap, const char* deviceId, uint8_t fsrCount);

}  // namespace insole

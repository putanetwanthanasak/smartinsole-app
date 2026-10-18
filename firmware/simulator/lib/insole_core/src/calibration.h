// Calibration blob served on the Calibration characteristic (Data Contract
// §5.1). The curve coefficients are fixed; `offset_adc` comes from TARE
// (tare.h), kept in NVS by the BLE glue.
#pragma once

#include <cstddef>
#include <cstdint>

namespace insole {

// offset_adc before any TARE has been stored (the contract §5.1 example).
constexpr uint16_t kDefaultOffsetAdc = 12;

// Writes the JSON text (no NUL counted) into `out`; returns its length, or
// 0 if it would not fit in `cap` or in the 512-byte characteristic.
// `offsets` holds fsrCount values.
size_t buildCalibrationJson(char* out, size_t cap, const char* deviceId, uint8_t fsrCount,
                            const uint16_t* offsets);

}  // namespace insole

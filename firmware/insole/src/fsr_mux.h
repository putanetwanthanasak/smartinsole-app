// The 8 FSR (Velostat) channels through the 16-channel mux into one ADC1 pin.
// Each reading becomes the contract's wire unit (adc_units.h): the divider
// voltage in counts of 3.3 V, from the chip's factory calibration, with the
// low range used below 700 mV.
#pragma once

#include <cstdint>

namespace fsr {

struct Frame {
  uint16_t counts[8];    // contract site order
  bool saturated;        // some channel at the C3's 2.5 V ceiling
  uint8_t lowRangeMask;  // bit i: site i measured in the low range
};

// Configures the mux pins and the ADC; logs which factory calibration the
// chip has. Returns false if the chip has no eFuse calibration (the mV would
// be off by up to +-10 %; the log says so and readings still flow).
bool begin(uint8_t footSide);

// Reads all 8 sites (about 2 ms). Called from the 50 Hz tick only.
void read(Frame& out);

const char* calibrationScheme();

}  // namespace fsr

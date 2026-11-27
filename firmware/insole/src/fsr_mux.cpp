#include "fsr_mux.h"

#include <Arduino.h>
#include <driver/adc.h>
#include <esp_adc_cal.h>

#include "adc_units.h"
#include "config.h"

namespace fsr {
namespace {

// The C3's ADC1 channel n is GPIOn for n = 0..4.
const adc1_channel_t kChannel = static_cast<adc1_channel_t>(config::kPinMuxSignal);
esp_adc_cal_characteristics_t gHigh;  // ATTEN3 (12 dB), 0-2500 mV
esp_adc_cal_characteristics_t gLow;   // ATTEN0 (0 dB), 0-750 mV
esp_adc_cal_value_t gScheme = ESP_ADC_CAL_VAL_DEFAULT_VREF;
const uint8_t* gMap = config::kMuxChannelOfSite[1];
adc_atten_t gAtten = ADC_ATTEN_DB_12;

void setAtten(adc_atten_t a) {
  if (a == gAtten) return;
  adc1_config_channel_atten(kChannel, a);
  gAtten = a;
}

void select(uint8_t ch) {
  for (int b = 0; b < 4; ++b) digitalWrite(config::kPinMuxS[b], (ch >> b) & 1 ? HIGH : LOW);
}

}  // namespace

bool begin(uint8_t footSide) {
  gMap = config::kMuxChannelOfSite[footSide];
  for (int p : config::kPinMuxS) {
    pinMode(p, OUTPUT);
    digitalWrite(p, LOW);
  }
  if (config::kPinMuxEnable != config::kNoPin) {
    pinMode(config::kPinMuxEnable, OUTPUT);
    digitalWrite(config::kPinMuxEnable, LOW);  // enabled
  }
  adc1_config_width(ADC_WIDTH_BIT_12);
  adc1_config_channel_atten(kChannel, ADC_ATTEN_DB_12);
  gAtten = ADC_ATTEN_DB_12;
  gScheme = esp_adc_cal_characterize(ADC_UNIT_1, ADC_ATTEN_DB_12, ADC_WIDTH_BIT_12, 1100, &gHigh);
  esp_adc_cal_characterize(ADC_UNIT_1, ADC_ATTEN_DB_0, ADC_WIDTH_BIT_12, 1100, &gLow);
  Serial.printf("[adc] GPIO%d, factory calibration: %s\n", config::kPinMuxSignal,
                calibrationScheme());
  return gScheme == ESP_ADC_CAL_VAL_EFUSE_TP || gScheme == ESP_ADC_CAL_VAL_EFUSE_TP_FIT;
}

const char* calibrationScheme() {
  switch (gScheme) {
    case ESP_ADC_CAL_VAL_EFUSE_TP_FIT: return "eFuse two-point + curve fitting";
    case ESP_ADC_CAL_VAL_EFUSE_TP: return "eFuse two-point";
    case ESP_ADC_CAL_VAL_EFUSE_VREF: return "eFuse Vref";
    default: return "NONE (default Vref: millivolts may be off by up to 10 %)";
  }
}

void read(Frame& out) {
  out.saturated = false;
  out.lowRangeMask = 0;
  for (uint8_t site = 0; site < config::kFsrCount; ++site) {
    select(gMap[site]);
    delayMicroseconds(config::kMuxSettleUs);

    setAtten(ADC_ATTEN_DB_12);
    adc1_get_raw(kChannel);  // discarded: the sampling capacitor follows the new channel
    int first = adc1_get_raw(kChannel);
    uint32_t firstMv = esp_adc_cal_raw_to_voltage(first, &gHigh);

    uint32_t highMv, lowMv = 0;
    uint16_t highMax = static_cast<uint16_t>(first), lowMax = 0;
    bool haveLow = insole_hw::useLowRange(firstMv);
    if (haveLow) {
      highMv = firstMv;
      setAtten(ADC_ATTEN_DB_0);
      adc1_get_raw(kChannel);  // discarded after the range switch
      uint32_t sum = 0;
      for (uint8_t i = 0; i < config::kAveragedReads; ++i) {
        int r = adc1_get_raw(kChannel);
        sum += r;
        if (r > lowMax) lowMax = static_cast<uint16_t>(r);
      }
      lowMv = esp_adc_cal_raw_to_voltage((sum + config::kAveragedReads / 2) / config::kAveragedReads,
                                         &gLow);
    } else {
      uint32_t sum = first;
      for (uint8_t i = 1; i < config::kAveragedReads; ++i) {
        int r = adc1_get_raw(kChannel);
        sum += r;
        if (r > highMax) highMax = static_cast<uint16_t>(r);
      }
      highMv = esp_adc_cal_raw_to_voltage(
          (sum + config::kAveragedReads / 2) / config::kAveragedReads, &gHigh);
    }
    insole_hw::Reading r = insole_hw::combine(highMv, highMax, haveLow, lowMv, lowMax);
    out.counts[site] = r.count;
    out.saturated = out.saturated || r.saturated;
    if (r.lowRange) out.lowRangeMask |= 1u << site;
  }
}

}  // namespace fsr

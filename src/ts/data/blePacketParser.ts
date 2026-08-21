// data/blePacketParser.ts — pure parsing/scaling functions for the
// SmartInsole BLE wire format. No GATT, no connection state, no side
// effects — every function here takes bytes (or, for calibration, text) and
// returns a plain structure or throws. See WebBleDataSource.ts for the
// connection lifecycle that calls these; keeping that split means the wire
// format can be read and checked (byte offsets against
// docs/BLE-INTERFACE.md) without a real device, a simulator, or even a
// browser that supports Web Bluetooth.
//
// All offsets, sizes, and scaling factors are from docs/BLE-INTERFACE.md /
// docs/DATA-CONTRACT.md — see bleProtocol.ts for the named constants none of
// this restates as bare literals.

import { FSR_CHANNEL_ORDER } from '../constants.js';
import {
  SENSOR_HEADER_BYTES, SENSOR_SAMPLE_BLOCK_BYTES, TEMP_PACKET_BYTES,
  TEMP_UNREADABLE_RAW, STATUS_PACKET_BYTES, ACCEL_LSB_PER_G, GYRO_LSB_PER_DPS,
  TEMP_RAW_PER_C,
} from './bleProtocol.js';

// ─── Sensor Stream packet ────────────────────────────────────────

export interface SensorPacketHeader {
  seq: number;
  t0Ms: number;
  /** Samples in THIS packet — normally 8, but the contract's own MTU-fallback path sends fewer in a shorter, still-valid packet. Read from the wire, never assumed. */
  count: number;
  saturated: boolean;
  calibrating: boolean;
}

export interface RawSensorSample {
  /** 6 raw ADC values, 0-4095, in FSR_CHANNEL_ORDER index order. Not yet kPa — see adcToKpa. */
  fsrAdc: number[];
  accelRaw: [number, number, number];
  gyroRaw: [number, number, number];
}

export interface ParsedSensorPacket {
  header: SensorPacketHeader;
  /** header.count entries when not truncated; empty when truncated (a truncated packet's sample bytes cannot be trusted, so none are parsed from it). */
  samples: RawSensorSample[];
  expectedBytes: number;
  actualBytes: number;
  /** actualBytes < expectedBytes — hard requirement #2: a real failure mode, not a parse edge case. */
  truncated: boolean;
}

/** Null only when the packet is too short to even read its own header (can't determine `count`, so can't tell expected vs. actual). */
export function parseSensorPacket(dv: DataView): ParsedSensorPacket | null {
  if (dv.byteLength < SENSOR_HEADER_BYTES) return null;

  const seq = dv.getUint16(0, true);
  const t0Ms = dv.getUint32(2, true);
  const count = dv.getUint8(6);
  const flags = dv.getUint8(7);
  const header: SensorPacketHeader = {
    seq, t0Ms, count,
    saturated: (flags & 0b01) !== 0,
    calibrating: (flags & 0b10) !== 0,
  };

  const expectedBytes = SENSOR_HEADER_BYTES + count * SENSOR_SAMPLE_BLOCK_BYTES;
  const actualBytes = dv.byteLength;
  const truncated = actualBytes < expectedBytes;

  const samples: RawSensorSample[] = [];
  if (!truncated) {
    for (let i = 0; i < count; i++) {
      const base = SENSOR_HEADER_BYTES + i * SENSOR_SAMPLE_BLOCK_BYTES;
      const fsrAdc: number[] = [];
      for (let ch = 0; ch < FSR_CHANNEL_ORDER.length; ch++) fsrAdc.push(dv.getUint16(base + ch * 2, true));
      const accelRaw: [number, number, number] = [
        dv.getInt16(base + 12, true), dv.getInt16(base + 14, true), dv.getInt16(base + 16, true),
      ];
      const gyroRaw: [number, number, number] = [
        dv.getInt16(base + 18, true), dv.getInt16(base + 20, true), dv.getInt16(base + 22, true),
      ];
      samples.push({ fsrAdc, accelRaw, gyroRaw });
    }
  }

  return { header, samples, expectedBytes, actualBytes, truncated };
}

export function accelRawToG(raw: number): number { return raw / ACCEL_LSB_PER_G; }
export function gyroRawToDps(raw: number): number { return raw / GYRO_LSB_PER_DPS; }

// ─── Temperature packet ──────────────────────────────────────────

export interface ParsedTempPacket {
  seq: number;
  tMs: number;
  /** null when the wire value is the TEMP_UNREADABLE_RAW sentinel — never render this as 0 or as a number. */
  forefootC: number | null;
  heelC: number | null;
  quality: 0 | 1 | 2;
}

export function parseTempPacket(dv: DataView): ParsedTempPacket | null {
  if (dv.byteLength < TEMP_PACKET_BYTES) return null;
  const rawForefoot = dv.getInt16(6, true);
  const rawHeel = dv.getInt16(8, true);
  return {
    seq: dv.getUint16(0, true),
    tMs: dv.getUint32(2, true),
    forefootC: rawForefoot === TEMP_UNREADABLE_RAW ? null : rawForefoot / TEMP_RAW_PER_C,
    heelC: rawHeel === TEMP_UNREADABLE_RAW ? null : rawHeel / TEMP_RAW_PER_C,
    quality: (dv.getUint8(10) & 0b11) as 0 | 1 | 2,
  };
}

// ─── Device Status packet ────────────────────────────────────────

export interface ParsedStatusPacket {
  batteryPct: number;
  batteryMv: number;
  footSide: 0 | 1;
  fwMajor: number;
  fwMinor: number;
  state: 0 | 1 | 2;
  errorCode: number;
}

export function parseStatusPacket(dv: DataView): ParsedStatusPacket | null {
  if (dv.byteLength < STATUS_PACKET_BYTES) return null;
  return {
    batteryPct: dv.getUint8(0),
    batteryMv: dv.getUint16(1, true),
    footSide: (dv.getUint8(3) & 1) as 0 | 1,
    fwMajor: dv.getUint8(4),
    fwMinor: dv.getUint8(5),
    state: (dv.getUint8(6) & 0b11) as 0 | 1 | 2,
    errorCode: dv.getUint8(7),
  };
}

// ─── Calibration blob (JSON, read from CHAR_CALIB_UUID) ──────────

export interface CalibrationChannel { index: number; a: number; b: number; offsetAdc: number; }
export interface Calibration {
  deviceId: string;
  rPulldownOhm: number;
  sensorAreaM2: number;
  channels: CalibrationChannel[];
}

/**
 * Throws on anything malformed — hard requirement #5: a bad calibration
 * blob is a hard connect failure, never a fallback to a plausible-looking
 * default curve.
 */
export function parseCalibrationJSON(text: string): Calibration {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    throw new Error(`Calibration blob is not valid JSON: ${(e as Error).message}`);
  }
  if (typeof raw !== 'object' || raw === null) {
    throw new Error('Calibration blob is not a JSON object');
  }
  const r = raw as Record<string, unknown>;
  if (typeof r.device_id !== 'string') throw new Error('Calibration blob missing string device_id');
  if (typeof r.r_pulldown_ohm !== 'number') throw new Error('Calibration blob missing numeric r_pulldown_ohm');
  if (typeof r.sensor_area_m2 !== 'number') throw new Error('Calibration blob missing numeric sensor_area_m2');
  if (!Array.isArray(r.channels)) throw new Error('Calibration blob missing channels array');

  const channels: CalibrationChannel[] = r.channels.map((c, i) => {
    if (typeof c !== 'object' || c === null) throw new Error(`Calibration channels[${i}] is not an object`);
    const cc = c as Record<string, unknown>;
    if (typeof cc.index !== 'number' || typeof cc.a !== 'number' || typeof cc.b !== 'number'
      || typeof cc.offset_adc !== 'number') {
      throw new Error(`Calibration channels[${i}] missing numeric index/a/b/offset_adc`);
    }
    return { index: cc.index, a: cc.a, b: cc.b, offsetAdc: cc.offset_adc };
  });

  if (channels.length !== FSR_CHANNEL_ORDER.length) {
    throw new Error(
      `Calibration blob has ${channels.length} channels, expected ${FSR_CHANNEL_ORDER.length} (FSR_CHANNEL_ORDER)`,
    );
  }

  return { deviceId: r.device_id, rPulldownOhm: r.r_pulldown_ohm, sensorAreaM2: r.sensor_area_m2, channels };
}

const SUPPLY_VOLTAGE = 3.3;
const ADC_MAX = 4095;

/**
 * docs/BLE-INTERFACE.md "FSR scaling" formula, now WITH offset_adc applied
 * (resolved — was an open gap in report 005, fixed in report 006) AND WITH
 * the Pa->kPa conversion applied (resolved — found and confirmed by
 * instrumented logging in report 007, fixed here in report 008):
 *   adc_corrected = max(0, adc_raw - offset_adc)
 *   V_out = (adc_corrected/4095) x 3.3; R_fsr = R_pulldown x (3.3-V_out)/V_out;
 *   F_newton = a x R_fsr^b; P_kPa = F_newton / A_sensor / 1000.
 *
 * `offset_adc` is the zero-point: the raw ADC reading from that channel
 * under no load. It's the stored result of a TARE (control opcode 0x05,
 * "ปรับ zero-point ของ FSR") — the contract defines no second zero-point
 * mechanism, so TARE's result and this field are the same concept. Clamped
 * at 0, not left negative: a reading below the channel's own recorded
 * zero-point means drift or sensor noise, not negative pressure.
 *
 * `F_newton / A_sensor` (N / m²) is Pascals, not kilopascals — the
 * documented formula never showed the /1000 step despite the field being
 * called `P_kPa`. Confirmed against instrumented hardware logs (report
 * 007/008): reported "anomaly" values that looked like raw ADC passed
 * through with a decimal fraction were actually this — e.g. rawAdc=345
 * produced 5411 Pa by hand and 5385.22 logged, not the ~5.41 kPa expected.
 *
 * Both fixes change measured kPa values from earlier implementations —
 * anything computed before report 006 reads high by offset_adc; anything
 * computed before this fix (report 008) reads ~1000x too high.
 *
 * The `Math.min`/`Math.max` clamps in the body below are numeric-safety
 * only (adc_corrected=0 would make V_out=0 -> division by zero; adc=4095
 * makes R_fsr=0, and a negative `b` makes 0^b = Infinity) — not a
 * calibration decision.
 */
/**
 * The zero-point-corrected ADC value — `max(0, adc_raw - offset_adc)`,
 * exported on its own so callers that need to reason about this
 * intermediate (not just the final kPa) don't have to duplicate the clamp.
 * Currently one caller: WebBleDataSource.ts's saturation-curve sanity
 * check (see docs/reports/009-*.md) tracks this value across consecutive
 * samples per channel — it needs the corrected ADC, not the raw one, since
 * that's the quantity the FSR formula actually responds to.
 */
export function correctAdc(rawAdc: number, offsetAdc: number): number {
  return Math.max(0, rawAdc - offsetAdc);
}

export function adcToKpa(rawAdc: number, channel: CalibrationChannel, cal: Calibration): number {
  const corrected = correctAdc(rawAdc, channel.offsetAdc);
  const adc = Math.min(ADC_MAX, Math.max(1, corrected));
  const vOut = (adc / ADC_MAX) * SUPPLY_VOLTAGE;
  const rFsr = Math.max(1e-6, (cal.rPulldownOhm * (SUPPLY_VOLTAGE - vOut)) / vOut);
  const fNewton = channel.a * Math.pow(rFsr, channel.b);
  return fNewton / cal.sensorAreaM2 / 1000;
}

/**
 * Heuristic-only sanity check for the FSR curve's known steep non-linearity
 * near ADC saturation (see docs/reports/008-*.md: illustrative — not
 * measured — values showed a 33% adc_corrected increase, 3000->4000,
 * producing a 15x kPa increase, 195->3067). Not a validity check on any
 * single reading, and NOT a claim about what a "correct" ceiling is — real
 * calibration curve validation across the full ADC range is blocked on PCB
 * arrival (see docs/BACKLOG.md). This only flags a SUSPICIOUS JUMP between
 * two consecutive readings of the SAME channel: a small increase in
 * adc_corrected producing a disproportionately large jump in computed kPa
 * — exactly the pattern already observed, cheap to detect, and worth
 * surfacing rather than silently trusting a possibly-poor curve fit right
 * at the alert threshold (PRESSURE_ALERT_KPA) where it matters most.
 *
 * Deliberately does not clamp or reject the value — only reports whether
 * it looks suspicious. The caller decides what to do with that (currently:
 * log a dev-only console warning, see WebBleDataSource.ts).
 */
export function isSuspiciousKpaJump(
  prevAdcCorrected: number,
  prevKpa: number,
  nextAdcCorrected: number,
  nextKpa: number,
  adcRatioThreshold = 1.5,
  kpaRatioThreshold = 5,
): boolean {
  if (prevAdcCorrected <= 0 || prevKpa <= 0) return false;
  const adcRatio = nextAdcCorrected / prevAdcCorrected;
  const kpaRatio = nextKpa / prevKpa;
  return adcRatio < adcRatioThreshold && kpaRatio > kpaRatioThreshold;
}

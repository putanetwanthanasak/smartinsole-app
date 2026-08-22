// data/types.ts — wire-level shapes from the external Data Contract, plus the
// snapshot vocabulary DeviceManager exposes to the UI.
//
// The three contract types (SensorSample / TempReading / DeviceStatus) match the
// contract exactly and must not be reshaped to suit the UI. In particular
// `fsrKpa` is an INDEXED array in FSR_CHANNEL_ORDER, while the UI renders a
// name-keyed FootPressure — converting between the two is DeviceManager's job,
// not the renderers'.
//
// Re-checked field-for-field against Data Contract v1.1 §6 (docs/DATA-CONTRACT.md)
// once the placeholder was filled in — SensorSample, TempReading, and
// DeviceStatus below match the contract's TypeScript block exactly, no changes
// needed. The contract also specifies a RiskAssessment/RiskZone/GaitClass shape
// (§6) that does not exist in this codebase yet — see docs/BACKLOG.md item 8.

import type { FootSide, FootPressure } from '../types.js';

/** Per-side link state. 'stale' = connected but no sample for STALE_AFTER_MS. */
export type ConnectionState =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'stale'
  | 'error';

/** Every subscribe call returns one of these. Call it in unmount(). */
export type Unsubscribe = () => void;

// ─── Contract types ───────────────────────────────────────────

export interface SensorSample {
  tUnixMs: number;
  side: FootSide;
  /** 6 values, in FSR_CHANNEL_ORDER (hallux, meta1, meta3, meta5, midfoot, heel). */
  fsrKpa: number[];
  accelG: [number, number, number];
  gyroDps: [number, number, number];
}

export interface TempReading {
  tUnixMs: number;
  side: FootSide;
  forefootC: number | null;
  heelC: number | null;
  /** 0 = ปกติ (normal), 1 = สัมผัสไม่ดี (poor contact), 2 = เซนเซอร์ผิดพลาด (sensor error). Per Data Contract §temperature packet / BLE-INTERFACE.md — 0 is GOOD, not unusable. See docs/reports/011-*.md: this comment was previously inverted and every consumer trusted it. */
  quality: 0 | 1 | 2;
}

export interface DeviceStatus {
  side: FootSide;
  batteryPct: number;
  connected: boolean;
  firmware: string;
  errorCode: number;
}

// ─── Snapshot vocabulary ──────────────────────────────────────

/**
 * Everything known about one foot at one instant.
 *
 * `state` is always present — a side that is connecting, errored or disconnected
 * still needs to say so on screen. The DATA fields are what go null when there
 * is nothing to show; never infer "no device" from `pressure === null` alone,
 * because a connected-but-stale side also has usable-looking state with old data.
 */
export interface SideSnapshot {
  side: FootSide;
  state: ConnectionState;
  /** Latest sample converted to the UI's name-keyed shape. */
  pressure: FootPressure | null;
  sample: SensorSample | null;
  temp: TempReading | null;
  status: DeviceStatus | null;
  lastSampleMs: number | null;
}

/** True when this side is connected and its data is fresh enough to render. */
export function isUsable(s: SideSnapshot | null): s is SideSnapshot {
  return !!s && s.state === 'connected';
}

export interface CombinedSnapshot {
  tUnixMs: number;
  left: SideSnapshot | null;
  right: SideSnapshot | null;
  /**
   * Forefoot ΔT, in °C — non-null ONLY when both sides are usable and both
   * report a forefoot temperature. A ΔT derived from one foot is not a rounded
   * number, it is a fabricated clinical reading, so this stays null instead.
   */
  deltaForefootC: number | null;
}

/**
 * One converted sample, emitted at the SOURCE's real rate (50 Hz per side,
 * unthrottled) rather than DeviceManager's 10 Hz UI-render rate. See
 * `DeviceManager.onRawSample` — for anything that needs to measure the
 * signal (a rolling-window peak, model input, a data-collection export),
 * not just display it. `pressure` is pre-converted (never raw `fsrKpa`) for
 * the same reason `SideSnapshot.pressure` is: nothing outside DeviceManager
 * may touch the wire-indexed array directly.
 *
 * `accelG`/`gyroDps` were added alongside `pressure` for capture.ts (see
 * docs/reports/010-*.md) — the research-capture CSV schema needs both per
 * the Data Contract's Model A input (§7.1), and gait.ts's PAI (the only
 * other onRawSample consumer at the time these were added) only ever read
 * `.pressure`, so this is additive: existing consumers are unaffected.
 */
export interface RawPressureSample {
  side: FootSide;
  /**
   * Arrival time (Date.now() when DeviceManager received this sample), matching every
   * other timestamp in this file — never the device's own clock. Use for
   * staleness/freshness checks (this is what gait.ts's PAI windowing keys off of).
   * NOT evenly spaced within a packet — WebBleDataSource emits all 8 samples of one BLE
   * notification synchronously, so consecutive samples in the same packet can carry
   * near-identical values here. See deviceTUnixMs for the field that IS evenly spaced.
   */
  tUnixMs: number;
  /**
   * Device-timeline time: t0_ms + i×20 from the packet header, corrected for this
   * connection's clock offset (WebBleDataSource.handleSensorValue's `deviceMs`, carried
   * through unchanged as SensorSample.tUnixMs). Evenly spaced within a packet, unlike
   * tUnixMs above. Use for anything needing true intra-packet sample spacing — currently
   * only CSV export / cross-stream (L/R) alignment (capture/recorder.ts). See
   * docs/reports/012-*.md for why this field exists separately from tUnixMs.
   */
  deviceTUnixMs: number;
  pressure: FootPressure;
  accelG: [number, number, number];
  gyroDps: [number, number, number];
}

// ─── Temperature history ──────────────────────────────────────

/**
 * One bucketed temperature point for ONE foot.
 *
 * Replaces the old UI-side TempHistoryPoint, which put both feet in a single row
 * (`leftForefoot` / `rightForefoot`) and dropped the heel channel entirely. That
 * shape could not express "left present, right absent" — a row had to invent a
 * value for the missing side or be discarded whole, losing the side that was
 * fine. Per-side series make absence representable, and a null channel here is
 * what the chart draws as a gap rather than interpolating across.
 */
export interface TempHistoryPoint {
  tUnixMs: number;
  forefootC: number | null;
  heelC: number | null;
}

export interface TempHistory {
  left: TempHistoryPoint[];
  right: TempHistoryPoint[];
}

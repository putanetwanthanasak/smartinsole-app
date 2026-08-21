// pressureColor.ts — Pressure value (kPa) → color + severity helpers

import type { SeverityLevel } from './types.js';
import {
  PRESSURE_RAMP_KPA, PRESSURE_WATCH_KPA, PRESSURE_ALERT_KPA,
} from './constants.js';

/**
 * Map a pressure value in kPa to its colour along the six-stop ramp.
 *
 *   < 25      blue        ┐
 *   < 50      green       ├ safe tier   (< 75 kPa)
 *   < 75      light green ┘
 *   < 137.5   amber       ┐ watch tier  (75–199 kPa)
 *   < 200     light red   ┘
 *   >= 200    red           alert tier
 *
 * Every breakpoint comes from PRESSURE_RAMP_KPA, which is itself derived from the
 * two contract thresholds — so the colour a zone gets and the tier it reports can
 * never disagree. Comparisons are strict `<` at the tier boundaries specifically
 * so that a value sitting exactly on 75 or 200 takes the *higher* tier's colour,
 * matching pressureSeverity() below.
 */
export function pressureColor(v: number): string {
  if (v < PRESSURE_RAMP_KPA.low)       return '#85B7EB';
  if (v < PRESSURE_RAMP_KPA.mid)       return '#97C459';
  if (v < PRESSURE_RAMP_KPA.watch)     return '#C0DD97';
  if (v < PRESSURE_RAMP_KPA.watchHigh) return '#FAC775';
  if (v < PRESSURE_RAMP_KPA.alert)     return '#F09595';
  return '#E24B4A';
}

export interface SeverityInfo {
  level: SeverityLevel;
  th: string;
  en: string;
  tone: 'safe' | 'warn' | 'danger';
}

/**
 * Map a pressure value in kPa to a severity bucket with Thai + English labels.
 * The two boundaries are the contract's two tiers, inclusive.
 */
export function pressureSeverity(v: number): SeverityInfo {
  if (v >= PRESSURE_ALERT_KPA) return { level: 'danger',  th: 'อันตราย',   en: 'Danger',  tone: 'danger' };
  if (v >= PRESSURE_WATCH_KPA) return { level: 'warning', th: 'เฝ้าระวัง', en: 'Caution', tone: 'warn'   };
  return                              { level: 'safe',    th: 'ปกติ',       en: 'Normal',  tone: 'safe'   };
}

/**
 * Short Thai-language recommendation text for a given pressure value in kPa.
 *
 * Four messages over three tiers, so the wide watch tier is split at its midpoint
 * (watchHigh) to keep all four. This preserves the old index-based ladder, whose
 * boundaries were 81 / 75 / 56: the 81 was not a clinical number at all — it was
 * one past the colour ramp's final breakpoint (80), i.e. "the fill has gone fully
 * red". Its true meaning was "top of the ramp", which is now the alert tier.
 */
export function pressureAdvice(v: number): string {
  if (v >= PRESSURE_RAMP_KPA.alert)     return 'แรงกดสูงมาก — ควรพักเท้าทันทีและเปลี่ยนรองเท้า';
  if (v >= PRESSURE_RAMP_KPA.watchHigh) return 'แรงกดอยู่ในช่วงอันตราย — ลดการเดินและตรวจรองเท้า';
  if (v >= PRESSURE_RAMP_KPA.watch)     return 'แรงกดเริ่มสูง — ระวังอย่ายืนนานในท่าเดียว';
  return 'แรงกดอยู่ในเกณฑ์ปลอดภัย';
}

/** Tone → semantic CSS color variable. */
export function toneColor(tone: 'safe' | 'warn' | 'danger'): string {
  if (tone === 'danger') return 'var(--status-danger)';
  if (tone === 'warn')   return 'var(--status-caution)';
  return 'var(--status-safe)';
}
export function toneSoft(tone: 'safe' | 'warn' | 'danger'): string {
  if (tone === 'danger') return 'var(--status-danger-soft)';
  if (tone === 'warn')   return 'var(--status-caution-soft)';
  return 'var(--status-safe-soft)';
}

/** Map raw skin temperature to a color along blue → red. */
export function tempColor(t: number): string {
  if (t < 29)   return '#85B7EB';
  if (t < 30)   return '#9FC6E0';
  if (t < 31)   return '#C0DD97';
  if (t < 31.5) return '#FAC775';
  if (t < 32.2) return '#F09595';
  return '#E24B4A';
}

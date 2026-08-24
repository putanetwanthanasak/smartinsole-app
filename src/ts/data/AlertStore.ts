// data/AlertStore.ts — the app's alert log.
//
// Alerts are generated from real threshold crossings on the DeviceManager
// snapshot, not written by hand in a screen. The store subscribes once at module
// load and keeps accruing while the user is on any screen (or none), because an
// alert the user was not looking at is exactly the alert that matters.

import { MOCK_DATA } from '../mockData.js';
import {
  PRESSURE_WATCH_KPA, PRESSURE_ALERT_KPA, TEMP_DELTA_THRESHOLD, ZONES,
  MIN_CONFIDENCE, GAIT_ADVISORY,
} from '../constants.js';
import type { AlertEntry, FootSide, FootPressure } from '../types.js';
import { deviceManager } from './DeviceManager.js';
import { isUsable } from './types.js';
import type { CombinedSnapshot, Unsubscribe } from './types.js';
import { getGaitPrediction } from './gaitPrediction.js';

/** Data Contract: the same code may not re-fire inside this window. */
const REPEAT_SUPPRESSION_MS = 30 * 60 * 1000;

const SIDE_TH: Record<FootSide, string> = { left: 'ซ้าย', right: 'ขวา' };

// ─── Time formatting ──────────────────────────────────────────

export type DayBucket = 'today' | 'yesterday' | 'older';

function startOfDay(t: number): number {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/** Whole days between two instants, by calendar day rather than elapsed hours. */
export function dayOffset(tUnixMs: number, now: number = Date.now()): number {
  return Math.round((startOfDay(now) - startOfDay(tUnixMs)) / 86400000);
}

export function bucketOf(tUnixMs: number, now: number = Date.now()): DayBucket {
  const d = dayOffset(tUnixMs, now);
  if (d <= 0) return 'today';
  if (d === 1) return 'yesterday';
  return 'older';
}

/**
 * Display string, derived from the timestamp rather than stored alongside it.
 * Reproduces exactly what the old hardcoded strings said: 'HH:MM' today,
 * 'เมื่อวาน HH:MM' yesterday, 'N วันก่อน HH:MM' before that.
 */
export function formatAlertTime(tUnixMs: number, now: number = Date.now()): string {
  const d = new Date(tUnixMs);
  const hhmm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  const off = dayOffset(tUnixMs, now);
  if (off <= 0) return hhmm;
  if (off === 1) return `เมื่อวาน ${hhmm}`;
  return `${off} วันก่อน ${hhmm}`;
}

// ─── Store ────────────────────────────────────────────────────

type Listener = (alerts: AlertEntry[]) => void;

class AlertStore {
  private alerts: AlertEntry[] = [];
  private lastFiredAt = new Map<string, number>();
  private listeners = new Set<Listener>();
  private nextId = 1000;
  private started = false;

  constructor() {
    // Seed with the existing mock log so the screen is not empty on first run.
    // Timestamps are anchored to "now" so the rendered strings match what the
    // hardcoded ones used to say.
    for (const a of MOCK_DATA.recentAlerts) this.alerts.push({ ...a });
    this.alerts.sort((x, y) => y.tUnixMs - x.tUnixMs);
  }

  /** Begin watching the device stream. Idempotent. */
  start(): void {
    if (this.started) return;
    this.started = true;
    deviceManager.onSnapshot(s => this.evaluate(s));
  }

  list(): AlertEntry[] { return [...this.alerts]; }
  unacknowledgedCount(): number { return this.alerts.filter(a => !a.acknowledged).length; }

  subscribe(cb: Listener): Unsubscribe {
    this.listeners.add(cb);
    cb(this.list());
    return () => { this.listeners.delete(cb); };
  }

  acknowledge(id: number): void {
    const a = this.alerts.find(x => x.id === id);
    if (!a || a.acknowledged) return;
    a.acknowledged = true;
    this.emit();
  }

  private emit(): void {
    const snapshot = this.list();
    for (const cb of [...this.listeners]) cb(snapshot);
  }

  /**
   * Data Contract §8.3.1 — the gait-pattern advisory layer. NOT an alert
   * rule: only appends explanatory text to a message from a rule that
   * already fired, at the zone that triggered it. Never raises an alert on
   * its own, never touches severity/statusLevel. Returns `message`
   * unchanged if no prediction is available, confidence is below
   * MIN_CONFIDENCE, or the predicted pattern isn't relevant to `zoneId`.
   */
  private withGaitAdvisory(message: string, zoneId: keyof FootPressure): string {
    const pred = getGaitPrediction();
    if (!pred || pred.confidence < MIN_CONFIDENCE) return message;
    const advisory = GAIT_ADVISORY[pred.pattern];
    if (!advisory) return message;
    if (advisory.zones !== 'any' && !advisory.zones.includes(zoneId)) return message;
    return `${message} ${advisory.th}`;
  }

  private raise(code: string, entry: Omit<AlertEntry, 'id' | 'acknowledged'>): void {
    const now = Date.now();
    const last = this.lastFiredAt.get(code);
    if (last !== undefined && now - last < REPEAT_SUPPRESSION_MS) return;
    this.lastFiredAt.set(code, now);
    this.alerts.unshift({ ...entry, id: this.nextId++, acknowledged: false });
    if (this.alerts.length > 100) this.alerts.length = 100;
    this.emit();
  }

  // ─── Threshold evaluation ───────────────────────────────────

  private evaluate(snap: CombinedSnapshot): void {
    for (const side of ['left', 'right'] as FootSide[]) {
      const s = side === 'left' ? snap.left : snap.right;
      if (!isUsable(s) || !s.pressure) continue;

      // Worst zone on this foot decides the tier, so one foot raises at most one
      // pressure alert per tier per window — rather than one per zone, which
      // would fire ten near-identical entries the moment an insole connects.
      let worstZone = ZONES[0];
      let worst = -Infinity;
      for (const z of ZONES) {
        const v = s.pressure[z.id];
        if (v > worst) { worst = v; worstZone = z; }
      }

      if (worst >= PRESSURE_ALERT_KPA) {
        this.raise(`pressure.alert.${side}`, {
          tUnixMs: Date.now(), type: 'pressure', severity: 'danger',
          message: this.withGaitAdvisory(
            `แรงกดเกินเกณฑ์อันตรายที่${worstZone.labelTH}เท้า${SIDE_TH[side]} ${Math.round(worst)} kPa — ควรพักเท้าทันทีและตรวจรองเท้า`,
            worstZone.id,
          ),
        });
      } else if (worst >= PRESSURE_WATCH_KPA) {
        this.raise(`pressure.watch.${side}`, {
          tUnixMs: Date.now(), type: 'pressure', severity: 'warning',
          message: this.withGaitAdvisory(
            `แรงกดเริ่มสูงที่${worstZone.labelTH}เท้า${SIDE_TH[side]} ${Math.round(worst)} kPa — ระวังอย่ายืนนานในท่าเดียว`,
            worstZone.id,
          ),
        });
      }
    }

    const dT = snap.deltaForefootC;
    if (dT !== null && dT > TEMP_DELTA_THRESHOLD) {
      this.raise('temp.delta', {
        tUnixMs: Date.now(), type: 'temperature', severity: 'danger',
        message: `ผลต่างอุณหภูมิเท้าหน้า ${dT.toFixed(1)}°C เกินเกณฑ์ ${TEMP_DELTA_THRESHOLD}°C — ควรพบแพทย์ภายใน 24–48 ชั่วโมง`,
      });
    }
  }
}

export const alertStore = new AlertStore();
alertStore.start();

// data/AlertStore.ts — the app's alert log.
//
// Alerts are generated from real threshold crossings on the DeviceManager
// snapshot, not written by hand in a screen. The store subscribes once at module
// load and keeps accruing while the user is on any screen (or none), because an
// alert the user was not looking at is exactly the alert that matters.

import { MOCK_DATA } from '../mockData.js';
import {
  PRESSURE_WATCH_KPA, PRESSURE_ALERT_KPA, TEMP_DELTA_THRESHOLD, ZONES,
  MIN_CONFIDENCE, GAIT_ADVISORY, TEMP_DELTA_CONSECUTIVE_READINGS,
  WALKING_ACCEL_G, WALKING_WINDOW_MS,
} from '../constants.js';
import type { AlertEntry, FootSide, FootPressure } from '../types.js';
import { deviceManager } from './DeviceManager.js';
import { isUsable } from './types.js';
import type { CombinedSnapshot, RawPressureSample, Unsubscribe } from './types.js';
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

/** One accel-magnitude sample kept for the PRESSURE_PEAK walking gate. */
interface MotionSample { t: number; mag: number; }

/** Data Contract §8.3 "ต่อเนื่อง ≥ 2 ครั้งวัด" — consecutive-OVER-THRESHOLD-READING tracking for temp.delta. See docs/BACKLOG.md item 10. */
interface TempDeltaState {
  streak: number;
  /**
   * The newest of the two sides' underlying TempReading.tUnixMs that this
   * streak last accounted for. A "reading" is a new temperature SAMPLE
   * arriving (real hardware: ~1/30 Hz per the contract's packet spec, not
   * the 10 Hz onSnapshot tick) — keying off this, not off onSnapshot ticks,
   * is what stops ~50 identical 10Hz re-evaluations of the SAME underlying
   * temp sample from counting as 50 separate "consecutive readings."
   */
  lastReadingKey: number | null;
}

class AlertStore {
  private alerts: AlertEntry[] = [];
  private lastFiredAt = new Map<string, number>();
  private listeners = new Set<Listener>();
  private nextId = 1000;
  private started = false;

  private motionBuf: Record<FootSide, MotionSample[]> = { left: [], right: [] };
  private tempDeltaState: TempDeltaState = { streak: 0, lastReadingKey: null };

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
    // Unthrottled (up to 50 Hz/side) — see onRawSample()'s own comment for
    // why this needs the raw stream, not onSnapshot, and why the handler
    // below must stay O(1)-cheap per DeviceManager.onRawSample's cost note.
    deviceManager.onRawSample(s => this.onRawSample(s));
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

  /**
   * PRESSURE_PEAK's walking gate (Data Contract §8.3: "Peak > 200 kPa
   * ขณะเดิน" — "while walking"; missing entirely until this pass, see
   * docs/BACKLOG.md item 10). Pushes one accel-magnitude sample into that
   * side's rolling buffer and prunes anything older than WALKING_WINDOW_MS.
   *
   * Deliberately O(1)-amortized and does nothing else — per
   * DeviceManager.onRawSample's own cost note, this runs synchronously on
   * the main thread up to 50 Hz/side, before the sample handler that
   * triggered it returns. The actual gate check (isWalking, O(window size))
   * happens lazily in evaluate(), which only runs at the throttled 10 Hz
   * onSnapshot rate — not here.
   */
  private onRawSample(s: RawPressureSample): void {
    const [x, y, z] = s.accelG;
    const mag = Math.sqrt(x * x + y * y + z * z);
    const buf = this.motionBuf[s.side];
    buf.push({ t: s.tUnixMs, mag });
    const cutoff = s.tUnixMs - WALKING_WINDOW_MS;
    let i = 0;
    while (i < buf.length && buf[i].t < cutoff) i++;
    if (i > 0) buf.splice(0, i);
  }

  /**
   * "Walking" = mean deviation of accel magnitude from 1g (gravity), over
   * the last WALKING_WINDOW_MS, at or above WALKING_ACCEL_G. Magnitude, not
   * a fixed axis, because a foot-mounted IMU's orientation relative to
   * gravity rotates through the gait cycle — magnitude is the invariant
   * that stays ~1g at rest regardless of how the foot happens to be
   * oriented. A MEAN over the window, not a single-sample peak, is what
   * makes this "sustained" rather than trigger-happy on one noisy tick —
   * see this pass's report for why that also makes it robust against
   * MockDataSource's per-tick independent random jitter, which averages out
   * near zero over a window instead of registering as sustained motion.
   *
   * No stride segmentation, no gait-cycle awareness — deliberately, per
   * this pass's brief ("doesn't need gait-cycle segmentation").
   */
  private isWalking(side: FootSide): boolean {
    const buf = this.motionBuf[side];
    if (buf.length === 0) return false;
    const meanDeviation = buf.reduce((sum, m) => sum + Math.abs(m.mag - 1), 0) / buf.length;
    return meanDeviation >= WALKING_ACCEL_G;
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

      // PRESSURE_PEAK (the alert tier) requires actual walking motion, per
      // Data Contract §8.3 ("...ขณะเดิน") — see docs/BACKLOG.md item 10 and
      // isWalking()'s comment. PRESSURE_WATCH has no such condition in the
      // contract, so a static high reading correctly still surfaces at the
      // watch tier (informational, no push notification) even while seated:
      // that's not a fallback for a "failed" alert check, it's PRESSURE_WATCH
      // firing on exactly the single-reading condition it's always had.
      if (worst >= PRESSURE_ALERT_KPA && this.isWalking(side)) {
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

    this.evaluateTempDelta(snap);
  }

  /**
   * Data Contract §8.3's TEMP_DELTA condition: ΔT > threshold on
   * TEMP_DELTA_CONSECUTIVE_READINGS consecutive MEASUREMENTS, not the
   * throttled 10 Hz onSnapshot tick this method is called from — a real
   * temperature packet arrives far slower (contract: ~1/30 Hz) than
   * onSnapshot re-evaluates, so counting snapshot ticks would count the same
   * one underlying reading dozens of times. `tempDeltaState.lastReadingKey`
   * (the newer of the two sides' own TempReading.tUnixMs) is what detects a
   * genuinely NEW reading has arrived; ticks that re-observe the same
   * reading are no-ops here. See docs/BACKLOG.md item 10.
   */
  private evaluateTempDelta(snap: CombinedSnapshot): void {
    const dT = snap.deltaForefootC;
    if (dT === null) {
      // Disconnect, one side unusable, or a bad-quality reading — reset,
      // don't just leave the streak hanging for whenever data returns.
      this.tempDeltaState = { streak: 0, lastReadingKey: null };
      return;
    }

    // deltaForefootC !== null guarantees both sides are usable with a valid
    // forefootC (see DeviceManager's deltaT()) — both temp objects and their
    // tUnixMs are safe to read here.
    const readingKey = Math.max(snap.left!.temp!.tUnixMs, snap.right!.temp!.tUnixMs);
    if (readingKey !== this.tempDeltaState.lastReadingKey) {
      // A genuinely new measurement — update the streak, resetting to 0 on
      // ANY under-threshold reading (not just on disconnect), per this
      // pass's brief.
      this.tempDeltaState.streak = dT > TEMP_DELTA_THRESHOLD ? this.tempDeltaState.streak + 1 : 0;
      this.tempDeltaState.lastReadingKey = readingKey;
    }

    if (this.tempDeltaState.streak >= TEMP_DELTA_CONSECUTIVE_READINGS) {
      this.raise('temp.delta', {
        tUnixMs: Date.now(), type: 'temperature', severity: 'danger',
        message: `ผลต่างอุณหภูมิเท้าหน้า ${dT.toFixed(1)}°C เกินเกณฑ์ ${TEMP_DELTA_THRESHOLD}°C — ควรพบแพทย์ภายใน 24–48 ชั่วโมง`,
      });
    }
  }
}

export const alertStore = new AlertStore();
alertStore.start();

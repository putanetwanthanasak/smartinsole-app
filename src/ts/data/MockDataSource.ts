// data/MockDataSource.ts — an IDataSource for one foot, driven by PRESETS.
//
// This is the only place in the data layer that knows PRESETS exist. It stands
// in for a BLE peripheral: it takes a few hundred ms to "connect", then streams
// samples at SAMPLE_HZ until disconnected.

import type { FootSide, FootPressure, PresetName } from '../types.js';
import { PRESETS } from '../mockData.js';
import { MOCK_DATA } from '../mockData.js';
import { FSR_CHANNEL_ORDER, PRESSURE_RAMP_KPA } from '../constants.js';
import type { IDataSource } from './IDataSource.js';
import type {
  ConnectionState, Unsubscribe, SensorSample, TempReading, DeviceStatus,
} from './types.js';

/** Real hardware streams at 50 Hz; match it so the throttle is exercised properly. */
const SAMPLE_HZ = 50;
const TEMP_INTERVAL_MS = 1000;
const STATUS_INTERVAL_MS = 5000;
const CONNECT_DELAY_MS = 350;

/** Max drift of the per-zone random walk, in kPa. Kept far below any band width. */
const JITTER_KPA = 1.2;
const JITTER_STEP = 0.45;
const TEMP_JITTER_C = 0.03;

/**
 * The colour-ramp band a value sits in, as [lo, hi).
 *
 * Jitter is clamped inside the value's own band so that no amount of it can
 * change a zone's colour, its severity tier, or whether it counts as high-risk.
 * Without this the presets would flicker: `forefoot` right meta3 sits at 202,
 * two kPa above the alert line, and `heavyHeel` left meta3 sits exactly on 75 —
 * both would cross a boundary on the first downward tick and the preset table
 * that is our regression baseline (0 / 2 / 2 / 4 high-risk zones) would stop
 * holding. Numbers still visibly move; the tiers they belong to never do.
 */
function bandOf(v: number): [number, number] {
  const R = PRESSURE_RAMP_KPA;
  if (v < R.low)       return [0, R.low];
  if (v < R.mid)       return [R.low, R.mid];
  if (v < R.watch)     return [R.mid, R.watch];
  if (v < R.watchHigh) return [R.watch, R.watchHigh];
  if (v < R.alert)     return [R.watchHigh, R.alert];
  return [R.alert, Number.POSITIVE_INFINITY];
}

type Listener<T> = (v: T) => void;

function emitter<T>() {
  const ls = new Set<Listener<T>>();
  return {
    add(cb: Listener<T>): Unsubscribe { ls.add(cb); return () => { ls.delete(cb); }; },
    emit(v: T) { for (const cb of [...ls]) cb(v); },
    get size() { return ls.size; },
  };
}

export class MockDataSource implements IDataSource {
  readonly side: FootSide;

  private state: ConnectionState = 'disconnected';
  private preset: PresetName;

  private sampleTimer: ReturnType<typeof setInterval> | null = null;
  private tempTimer: ReturnType<typeof setInterval> | null = null;
  private statusTimer: ReturnType<typeof setInterval> | null = null;
  private connectTimer: ReturnType<typeof setTimeout> | null = null;

  /** Per-zone random-walk offset, so values drift rather than flicker. */
  private drift: Record<string, number> = {};

  private samples = emitter<SensorSample>();
  private temps = emitter<TempReading>();
  private statuses = emitter<DeviceStatus>();
  private states = emitter<ConnectionState>();

  constructor(side: FootSide, initialPreset: PresetName = 'diabetic') {
    this.side = side;
    this.preset = initialPreset;
    for (const k of FSR_CHANNEL_ORDER) this.drift[k] = 0;
  }

  // ─── IDataSource ────────────────────────────────────────────

  getState(): ConnectionState { return this.state; }

  onSample(cb: (s: SensorSample) => void): Unsubscribe { return this.samples.add(cb); }
  onTemp(cb: (t: TempReading) => void): Unsubscribe { return this.temps.add(cb); }
  onStatus(cb: (d: DeviceStatus) => void): Unsubscribe { return this.statuses.add(cb); }
  onStateChange(cb: (s: ConnectionState) => void): Unsubscribe { return this.states.add(cb); }

  connect(): Promise<void> {
    if (this.state === 'connected' || this.state === 'connecting') return Promise.resolve();
    this.setState('connecting');
    return new Promise(resolve => {
      this.connectTimer = setTimeout(() => {
        this.connectTimer = null;
        this.setState('connected');
        this.backfillTempHistory();
        this.startStreaming();
        this.emitStatus();
        this.emitTemp();
        resolve();
      }, CONNECT_DELAY_MS);
    });
  }

  disconnect(): Promise<void> {
    this.stopTimers();
    this.setState('disconnected');
    return Promise.resolve();
  }

  // ─── Mock-only control. Deliberately NOT on IDataSource: a real device has
  //     no notion of a scenario preset, and nothing above the seam may depend
  //     on this existing. ────────────────────────────────────────
  setPreset(p: PresetName): void {
    this.preset = p;
    for (const k of FSR_CHANNEL_ORDER) this.drift[k] = 0;
  }

  getPreset(): PresetName { return this.preset; }

  /** Test/diagnostic helper: total live subscribers across all four channels. */
  subscriberCount(): number {
    return this.samples.size + this.temps.size + this.statuses.size + this.states.size;
  }

  // ─── Internals ──────────────────────────────────────────────

  private setState(s: ConnectionState): void {
    if (this.state === s) return;
    this.state = s;
    this.states.emit(s);
  }

  private startStreaming(): void {
    this.stopStreamTimers();
    this.sampleTimer = setInterval(() => this.emitSample(), Math.round(1000 / SAMPLE_HZ));
    this.tempTimer = setInterval(() => this.emitTemp(), TEMP_INTERVAL_MS);
    this.statusTimer = setInterval(() => this.emitStatus(), STATUS_INTERVAL_MS);
  }

  private stopStreamTimers(): void {
    if (this.sampleTimer) { clearInterval(this.sampleTimer); this.sampleTimer = null; }
    if (this.tempTimer) { clearInterval(this.tempTimer); this.tempTimer = null; }
    if (this.statusTimer) { clearInterval(this.statusTimer); this.statusTimer = null; }
  }

  private stopTimers(): void {
    this.stopStreamTimers();
    if (this.connectTimer) { clearTimeout(this.connectTimer); this.connectTimer = null; }
  }

  private emitSample(): void {
    const base: FootPressure = PRESETS[this.preset][this.side];
    const fsrKpa = FSR_CHANNEL_ORDER.map(key => {
      const b = base[key];
      // bounded random walk, then clamp into this value's own colour band
      let d = this.drift[key] + (Math.random() - 0.5) * 2 * JITTER_STEP;
      d = Math.max(-JITTER_KPA, Math.min(JITTER_KPA, d));
      this.drift[key] = d;
      const [lo, hi] = bandOf(b);
      return Math.max(lo, Math.min(hi - 0.001, b + d));
    });

    const t = Date.now();
    this.samples.emit({
      tUnixMs: t,
      side: this.side,
      fsrKpa,
      accelG: [rand(-0.2, 0.2), rand(-0.2, 0.2), rand(0.85, 1.15)],
      gyroDps: [rand(-25, 25), rand(-25, 25), rand(-25, 25)],
    });
  }

  /**
   * Replay 24 h of past temperature readings on connect, at the same 10-minute
   * resolution DeviceManager buckets to.
   *
   * A real insole caches readings while unpaired and dumps them on connect, so
   * this goes through the ordinary onTemp channel rather than reaching into the
   * manager: the history buffer has exactly one way in, and it is the same one
   * live readings use. Values interpolate the canned curve in
   * MOCK_DATA.temperatureHistory24h, which is anchored at 06:00-16:00.
   */
  private backfillTempHistory(): void {
    const seed = MOCK_DATA.temperatureHistory24h;
    const now = Date.now();
    const stepMs = 10 * 60 * 1000;
    const spanMs = 24 * 60 * 60 * 1000;
    for (let t = now - spanMs; t < now; t += stepMs) {
      const hourOfDay = new Date(t).getHours() + new Date(t).getMinutes() / 60;
      // map hour-of-day onto the seed curve, clamping outside 06:00-16:00
      const pos = Math.max(0, Math.min(seed.length - 1, (hourOfDay - 6) / 2));
      const i = Math.floor(pos);
      const j = Math.min(seed.length - 1, i + 1);
      const f = pos - i;
      const pick = (a: number, b: number) => a + (b - a) * f;
      const fore = this.side === 'left'
        ? pick(seed[i].leftForefoot, seed[j].leftForefoot)
        : pick(seed[i].rightForefoot, seed[j].rightForefoot);
      const heelBase = MOCK_DATA.temperature[this.side].heel;
      // Converge the backfilled curve onto the value the live stream will report
      // over the final CONVERGE_MS. Without this the canned curve and the live
      // constant meet at a step, and a step on a temperature trend chart reads
      // as a real thermal event rather than as two mock sources disagreeing.
      const CONVERGE_MS = 2 * 60 * 60 * 1000;
      const toEnd = now - t;
      const liveFore = MOCK_DATA.temperature[this.side].forefoot;
      const blend = toEnd >= CONVERGE_MS ? 0 : 1 - toEnd / CONVERGE_MS;
      const foreC = fore + (liveFore - fore) * blend;
      this.temps.emit({
        tUnixMs: t,
        side: this.side,
        forefootC: foreC + rand(-0.05, 0.05),
        heelC: heelBase + rand(-0.05, 0.05),
        quality: 0,   // 0 = normal, per contract (see docs/reports/011-*.md) — was 2, which masked the quality-check inversion in every consumer
      });
    }
  }

  private emitTemp(): void {
    const base = MOCK_DATA.temperature[this.side];
    this.temps.emit({
      tUnixMs: Date.now(),
      side: this.side,
      forefootC: base.forefoot + rand(-TEMP_JITTER_C, TEMP_JITTER_C),
      heelC: base.heel + rand(-TEMP_JITTER_C, TEMP_JITTER_C),
      quality: 0,   // 0 = normal, per contract (see docs/reports/011-*.md) — was 2, which masked the quality-check inversion in every consumer
    });
  }

  private emitStatus(): void {
    this.statuses.emit({
      side: this.side,
      batteryPct: MOCK_DATA.batteryLevel[this.side],
      connected: this.state === 'connected' || this.state === 'stale',
      firmware: 'v2.4.1',
      errorCode: 0,
    });
  }
}

function rand(lo: number, hi: number): number {
  return lo + Math.random() * (hi - lo);
}

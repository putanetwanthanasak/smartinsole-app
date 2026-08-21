// data/DeviceManager.ts — owns one IDataSource per foot and exposes the
// combined, throttled view the UI renders from.
//
// Three jobs the screens must not do themselves:
//   1. adapt the wire format (indexed fsrKpa[6]) to the UI shape (FootPressure)
//   2. throttle 2x50 Hz of pushes down to one coalesced 10 Hz snapshot
//   3. decide when a side has gone stale, and refuse to compute bilateral
//      figures (ΔT) from one foot

import type { FootSide, FootPressure } from '../types.js';
import { FSR_CHANNEL_ORDER } from '../constants.js';
import type { IDataSource } from './IDataSource.js';
import { MockDataSource } from './MockDataSource.js';
import type {
  ConnectionState, Unsubscribe, SensorSample, TempReading, DeviceStatus,
  SideSnapshot, CombinedSnapshot, TempHistoryPoint, TempHistory,
} from './types.js';
import { isUsable } from './types.js';

/** Coalesced emit rate. Renderers rebuild subtrees; 50 Hz of that would be janky. */
const EMIT_HZ = 10;
/** Connected but silent for this long => 'stale'. */
const STALE_AFTER_MS = 3000;
/** One temperature history point per bucket; latest reading in a bucket wins. */
const TEMP_BUCKET_MS = 10 * 60 * 1000;
const TEMP_HISTORY_SPAN_MS = 24 * 60 * 60 * 1000;

/** Wire format -> UI format. The one place this mapping is allowed to live. */
export function fsrToFootPressure(fsrKpa: number[]): FootPressure | null {
  if (!Array.isArray(fsrKpa) || fsrKpa.length !== FSR_CHANNEL_ORDER.length) return null;
  const out = {} as FootPressure;
  FSR_CHANNEL_ORDER.forEach((key, i) => { out[key] = fsrKpa[i]; });
  return out;
}

interface SideBox {
  source: IDataSource;
  /**
   * The LINK state as reported by the source. Never 'stale' - staleness is not a
   * link state, it is a statement about how old the newest sample is, and it is
   * derived at read time (see derivedState) rather than latched by a timer.
   */
  linkState: ConnectionState;
  sample: SensorSample | null;
  pressure: FootPressure | null;
  temp: TempReading | null;
  status: DeviceStatus | null;
  /** Wall-clock arrival of the newest sample. The single input to staleness. */
  lastSampleAt: number | null;
  connectedAt: number | null;
  history: TempHistoryPoint[];
  unsubs: Unsubscribe[];
}

export class DeviceManager {
  private sides: Record<FootSide, SideBox>;
  private listeners = new Set<(s: CombinedSnapshot) => void>();
  private timer: ReturnType<typeof setInterval> | null = null;
  private dirty = true;

  constructor(left: IDataSource, right: IDataSource) {
    this.sides = { left: this.box(left), right: this.box(right) };
  }

  private box(source: IDataSource): SideBox {
    const b: SideBox = {
      source, linkState: source.getState(), sample: null, pressure: null,
      temp: null, status: null, lastSampleAt: null, connectedAt: null,
      history: [], unsubs: [],
    };
    b.unsubs.push(
      source.onSample(s => {
        // Latest-wins, no queue: a throttled tick emits whatever is current when
        // it finally runs, never a backlog of stale queued samples.
        b.sample = s;
        b.pressure = fsrToFootPressure(s.fsrKpa);
        // Arrival time, NOT s.tUnixMs - a device with a skewed clock must not be
        // able to make its own data look permanently fresh or permanently stale.
        b.lastSampleAt = Date.now();
        this.dirty = true;
      }),
      source.onTemp(t => { b.temp = t; this.pushHistory(b, t); this.dirty = true; }),
      source.onStatus(d => { b.status = d; this.dirty = true; }),
      source.onStateChange(s => {
        b.linkState = s;
        if (s === 'connected') b.connectedAt = Date.now();
        if (s === 'disconnected' || s === 'error') {
          // Drop the data with the link. Keeping it would let the UI render a
          // dead foot's last values as if they were current.
          b.sample = null; b.pressure = null; b.temp = null;
          b.lastSampleAt = null; b.connectedAt = null;
        }
        this.dirty = true;
      }),
    );
    return b;
  }

  // ─── Per-side control ───────────────────────────────────────

  connect(side: FootSide): Promise<void> { return this.sides[side].source.connect(); }
  disconnect(side: FootSide): Promise<void> { return this.sides[side].source.disconnect(); }
  connectAll(): Promise<void[]> {
    return Promise.all([this.connect('left'), this.connect('right')]);
  }
  getSource(side: FootSide): IDataSource { return this.sides[side].source; }
  getStateOf(side: FootSide): ConnectionState { return this.derivedState(this.sides[side]); }

  /**
   * Staleness, decided by comparing timestamps AT READ TIME rather than by a
   * timer that flips a latched flag.
   *
   * The timer version was wrong in both directions under Chrome's background-tab
   * throttling (a 400 ms sleep measured at 1400 ms): it could report a side
   * stale while data was arriving fine, and - the dangerous direction - leave a
   * side reading 'connected' long after its stream died, because the timer that
   * would have noticed was itself throttled. A comparison evaluated on every
   * read cannot drift, however badly timers are starved.
   */
  private derivedState(b: SideBox): ConnectionState {
    if (b.linkState !== 'connected') return b.linkState;
    const since = b.lastSampleAt ?? b.connectedAt;
    if (since === null) return 'connected';
    return Date.now() - since > STALE_AFTER_MS ? 'stale' : 'connected';
  }

  // --- Temperature history ------------------------------------

  /** Bucketed per side; the latest reading inside a bucket replaces the earlier
   *  one, so the newest point tracks live while older buckets stay fixed. */
  private pushHistory(b: SideBox, t: TempReading): void {
    if (t.quality === 0) return;
    const bucket = Math.floor(t.tUnixMs / TEMP_BUCKET_MS) * TEMP_BUCKET_MS;
    const point: TempHistoryPoint = {
      tUnixMs: bucket, forefootC: t.forefootC, heelC: t.heelC,
    };
    const last = b.history[b.history.length - 1];
    if (last && last.tUnixMs === bucket) b.history[b.history.length - 1] = point;
    else if (last && bucket < last.tUnixMs) return;   // ignore out-of-order arrivals
    else b.history.push(point);

    const cutoff = Date.now() - TEMP_HISTORY_SPAN_MS;
    while (b.history.length && b.history[0].tUnixMs < cutoff) b.history.shift();
  }

  getTempHistory(): TempHistory {
    return { left: [...this.sides.left.history], right: [...this.sides.right.history] };
  }

  // ─── Subscription ───────────────────────────────────────────

  /**
   * The throttle timer is reference-counted against subscribers: it starts on
   * the first subscribe and stops on the last unsubscribe, so navigating away
   * from every screen leaves zero timers running and navigating back leaves
   * exactly one — never one per visit.
   */
  onSnapshot(cb: (s: CombinedSnapshot) => void): Unsubscribe {
    this.listeners.add(cb);
    this.ensureTimer();
    cb(this.snapshot());          // paint immediately, don't wait up to 100 ms
    return () => {
      this.listeners.delete(cb);
      if (this.listeners.size === 0) this.stopTimer();
    };
  }

  /** Diagnostics for the navigation-leak check. */
  stats(): { snapshotListeners: number; timerRunning: boolean } {
    return { snapshotListeners: this.listeners.size, timerRunning: this.timer !== null };
  }

  private ensureTimer(): void {
    if (this.timer !== null) return;
    this.timer = setInterval(() => this.tick(), Math.round(1000 / EMIT_HZ));
  }

  private stopTimer(): void {
    if (this.timer === null) return;
    clearInterval(this.timer);
    this.timer = null;
  }

  private lastStateSig = '';

  private tick(): void {
    // A side can go stale with no event to announce it, so compare the derived
    // states each tick and treat a change as dirty.
    const sig = `${this.derivedState(this.sides.left)}|${this.derivedState(this.sides.right)}`;
    if (sig !== this.lastStateSig) { this.lastStateSig = sig; this.dirty = true; }
    if (!this.dirty) return;
    this.dirty = false;
    const snap = this.snapshot();
    for (const cb of [...this.listeners]) cb(snap);
  }

  // ─── Snapshot assembly ──────────────────────────────────────

  private sideSnapshot(side: FootSide): SideSnapshot {
    const b = this.sides[side];
    return {
      side,
      state: this.derivedState(b),
      pressure: b.pressure,
      sample: b.sample,
      temp: b.temp,
      status: b.status,
      lastSampleMs: b.lastSampleAt,
    };
  }

  snapshot(): CombinedSnapshot {
    const left = this.sideSnapshot('left');
    const right = this.sideSnapshot('right');
    return { tUnixMs: Date.now(), left, right, deltaForefootC: deltaT(left, right) };
  }

  /** Release both sources' subscriptions. Not used yet; the manager is a singleton. */
  dispose(): void {
    this.stopTimer();
    this.listeners.clear();
    for (const side of ['left', 'right'] as FootSide[]) {
      this.sides[side].unsubs.forEach(u => u());
      this.sides[side].unsubs = [];
    }
  }
}

/** ΔT only when BOTH sides are usable and both actually report a forefoot value. */
function deltaT(left: SideSnapshot, right: SideSnapshot): number | null {
  if (!isUsable(left) || !isUsable(right)) return null;
  const l = left.temp?.forefootC;
  const r = right.temp?.forefootC;
  if (l === null || l === undefined || r === null || r === undefined) return null;
  if (left.temp!.quality === 0 || right.temp!.quality === 0) return null;
  return Math.abs(l - r);
}

// ─── App-wide singleton ───────────────────────────────────────
// One manager for the whole app: the sources model physical devices, so they
// must outlive any single screen. Screens subscribe and unsubscribe; they never
// construct this.

export const mockSources = {
  left: new MockDataSource('left'),
  right: new MockDataSource('right'),
};

export const deviceManager = new DeviceManager(mockSources.left, mockSources.right);

if (import.meta.env.DEV) {
  // Dev-only handle so connection states can be driven from the console without
  // shipping disconnect buttons in the UI.
  (window as unknown as Record<string, unknown>).__insole = { deviceManager, mockSources };
}

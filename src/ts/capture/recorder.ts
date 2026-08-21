// capture/recorder.ts — buffers deviceManager.onRawSample() into SampleRows
// and flushes them to IndexedDB on an interval, at the 50 Hz raw rate the
// Data Contract's Model A input fixes (§7.1, [1, 100, 24] @ 50 Hz) — NOT
// deviceManager.onSnapshot()'s throttled 10 Hz. See docs/reports/010-*.md.
//
// FLUSH_MS = 1000: chosen so at most ~1s of a session is ever at risk if the
// tab dies between flushes (survivable — IndexedDB has the rest), while
// keeping write-transaction frequency low enough that a ~100-row batch per
// flush (both feet at 50 Hz combined) stays comfortably cheap. Measured
// against the mock source's simulated 50 Hz stream (see the report for the
// numbers) rather than only asserted.
//
// onRawSample's own docstring (DeviceManager.ts) warns that a subscriber
// here must stay O(1)-cheap and must not do per-sample IndexedDB writes —
// this module honours that: the raw callback only pushes onto an array and
// increments counters, never touches IndexedDB itself. All IndexedDB I/O
// happens on the interval timer, off the sample-arrival call stack.

import { deviceManager } from '../data/DeviceManager.js';
import type { RawPressureSample, Unsubscribe } from '../data/types.js';
import { toCsvSide } from './types.js';
import type { GaitLabel, SampleRow, SessionRecord } from './types.js';
import { appendSamples, putSession } from './store.js';

const FLUSH_MS = 1000;
/** Matches Model A's window (Data Contract §7.1: 100 timesteps @ 50 Hz = 2s) — "window count" in the UI counts completed chunks of this size, not arbitrary samples. */
const WINDOW_SAMPLES = 100;

export interface InvalidInterval {
  startMs: number;
  endMs: number | null;
}

export class Recorder {
  private readonly session: SessionRecord;
  private unsub: Unsubscribe | null = null;
  private flushTimer: ReturnType<typeof setInterval> | null = null;

  private buffer: SampleRow[] = [];
  private recording = false;
  private currentLabel: GaitLabel = 'normal';
  private invalidActive = false;

  /** Invalid spans for the CURRENT take only — reset on every Start. Purely a live operator-visibility aid (Convention: "make its effect visible after the fact"); the actual record of record is the isValid column on each row. */
  invalidIntervals: InvalidInterval[] = [];

  constructor(session: SessionRecord) {
    this.session = session;
  }

  isRecording(): boolean { return this.recording; }
  getLabel(): GaitLabel { return this.currentLabel; }
  isInvalidActive(): boolean { return this.invalidActive; }

  setLabel(label: GaitLabel): void {
    if (this.recording) return;   // label is fixed for the duration of a take
    this.currentLabel = label;
  }

  start(): void {
    if (this.recording) return;
    this.recording = true;
    this.invalidActive = false;
    this.invalidIntervals = [];
    if (!this.unsub) this.unsub = deviceManager.onRawSample(s => this.handleRaw(s));
    if (!this.flushTimer) this.flushTimer = setInterval(() => { void this.flush(); }, FLUSH_MS);
  }

  /** Stops the current take. Does NOT tear down the subscription/timer — call dispose() for that (on unmount), so a Stop -> Start within the same screen visit doesn't re-subscribe. */
  stop(): void {
    if (!this.recording) return;
    this.recording = false;
    if (this.invalidActive) {
      this.invalidActive = false;
      const open = this.invalidIntervals[this.invalidIntervals.length - 1];
      if (open && open.endMs === null) open.endMs = Date.now();
    }
  }

  toggleInvalid(): void {
    if (!this.recording) return;
    this.invalidActive = !this.invalidActive;
    if (this.invalidActive) {
      this.invalidIntervals.push({ startMs: Date.now(), endMs: null });
    } else {
      const open = this.invalidIntervals[this.invalidIntervals.length - 1];
      if (open && open.endMs === null) open.endMs = Date.now();
    }
  }

  /**
   * Window-count per side for a pattern, per WINDOW_SAMPLES (see top-of-file
   * note). Falls back to zero rather than throwing if this session's
   * patternCounts is missing the key — store.recountPatterns() always seeds
   * all five now, but this stays defensive against any other path (a hand-
   * edited record, a future migration) that might produce a partial map;
   * one missing key crashing this used to take the whole recording screen's
   * render with it (see docs/reports/010-*.md).
   */
  windowCount(label: GaitLabel): { left: number; right: number } {
    const c = this.session.patternCounts[label] ?? { left: 0, right: 0 };
    return { left: Math.floor(c.left / WINDOW_SAMPLES), right: Math.floor(c.right / WINDOW_SAMPLES) };
  }

  /** Releases the subscription and timer. Call from capture.ts's unmount(). */
  dispose(): void {
    this.recording = false;
    if (this.unsub) { this.unsub(); this.unsub = null; }
    if (this.flushTimer) { clearInterval(this.flushTimer); this.flushTimer = null; }
    // Flush whatever is left, best-effort — unmount is synchronous but this
    // fires the write anyway; a page navigation away from #/capture (not a
    // full reload) does not tear down the IndexedDB connection.
    void this.flush();
  }

  private handleRaw(s: RawPressureSample): void {
    if (!this.recording) return;
    const row: SampleRow = {
      subjectId: this.session.subject.subjectId,
      sessionId: this.session.sessionId,
      tUnixMs: s.tUnixMs,
      side: toCsvSide(s.side),
      gaitLabel: this.currentLabel,
      isValid: !this.invalidActive,
      fsr_hallux: s.pressure.hallux,
      fsr_meta1: s.pressure.meta1,
      fsr_meta3: s.pressure.meta3,
      fsr_meta5: s.pressure.meta5,
      fsr_midfoot: s.pressure.midfoot,
      fsr_heel: s.pressure.heel,
      accel_x: s.accelG[0], accel_y: s.accelG[1], accel_z: s.accelG[2],
      gyro_x: s.gyroDps[0], gyro_y: s.gyroDps[1], gyro_z: s.gyroDps[2],
    };
    this.buffer.push(row);
    // No defensive fallback here (unlike windowCount) — this runs up to
    // ~100x/sec and relies on the invariant that patternCounts always has
    // all five GaitLabel keys, which both places a SessionRecord is built
    // (emptyPatternCounts() and store.recountPatterns()) now guarantee.
    const counts = this.session.patternCounts[this.currentLabel];
    if (s.side === 'left') counts.left++; else counts.right++;
  }

  private async flush(): Promise<void> {
    if (this.buffer.length === 0) return;
    const toWrite = this.buffer;
    this.buffer = [];
    await appendSamples(toWrite);
    // Mirror updated counts (and any calibration/notes capture.ts has since
    // set on the same session object) so a reload can resume from here.
    await putSession(this.session);
  }
}

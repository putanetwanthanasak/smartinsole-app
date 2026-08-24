// data/gaitPrediction.ts — the current Model A gait-pattern prediction.
//
// Deliberately NOT part of IDataSource or DeviceManager. Both of those are
// per-side (one instance per foot); Model A's input is both feet's channels
// combined (Data Contract §7.1), so a prediction is one value describing the
// gait cycle as a whole, not something either foot's data source can own.
// There is no real Model A integration in this codebase yet (see
// docs/BACKLOG.md items 8 and 9 — "a gait classifier model, explicitly out
// of scope") — this module is the seam it will eventually write into.
// AlertStore (§8.3.1's gait-pattern advisory layer) is the only reader today.

import type { GaitPrediction } from './types.js';

let current: GaitPrediction | null = null;

/** Latest Model A prediction, or null if none has ever been reported. */
export function getGaitPrediction(): GaitPrediction | null {
  return current;
}

/**
 * Mock/dev-only setter — no production caller exists yet, same status as
 * MockDataSource's setPreset(). Exposed on `window.mockGait` in dev builds
 * (see main.ts) so a gait-pattern advisory can be exercised from the
 * console without a real Model A. Pass null to clear.
 */
export function setMockGaitPrediction(pattern: GaitPrediction['pattern'] | null, confidence = 1): void {
  current = pattern === null ? null : { tUnixMs: Date.now(), pattern, confidence };
}

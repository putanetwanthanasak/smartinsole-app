// data/thresholds.ts — the runtime-loadable side of Data Contract §8.3's
// thresholds.json requirement. The shape, defaults, and mutable live state
// live in constants.ts (per CLAUDE.md convention #6); this file is purely
// IO: fetch, validate untrusted external JSON, and hand a validated config
// to constants.ts's applyThresholds() — the one function trusted to write
// every field, hard floor included (see the comment there for why that's
// safe: this is an ops/clinician-controlled file, not anything reachable
// from a patient-facing UI control).
//
// Called once at boot from main.ts, fire-and-forget (not awaited before
// startRouter()/connectAll()) — constants.ts's DEFAULT_THRESHOLDS already
// makes every threshold usable synchronously at module load, so nothing in
// the app blocks on this fetch. If it resolves later, the `let` bindings in
// constants.ts update in place and every consumer picks up the new values on
// its next read — no explicit re-render/notification needed (see
// constants.ts's comment on why that's true).

import { DEFAULT_THRESHOLDS, applyThresholds } from '../constants.js';
import type { ThresholdsConfig } from '../constants.js';

export interface LoadResult {
  ok: boolean;
  source: 'file' | 'default';
  /** Present only when ok is false — the reason the file was rejected. */
  error?: string;
}

/**
 * Fetches, validates, and applies a thresholds.json override. Never throws —
 * "fail loud with the bundled default, not fail silent with undefined
 * thresholds" (this pass's brief) means: on ANY failure (network error, 404,
 * invalid JSON syntax, wrong shape, out-of-range value), log a specific
 * console.error explaining exactly what was wrong, then explicitly re-apply
 * DEFAULT_THRESHOLDS so the app is left on a known-good, fully-defined
 * config either way — never on a partial merge and never on `undefined`.
 */
export async function loadThresholds(url = '/thresholds.json'): Promise<LoadResult> {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
    const json: unknown = await res.json();
    const cfg = validateThresholds(json);
    applyThresholds(cfg);
    return { ok: true, source: 'file' };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(
      `[thresholds] Failed to load ${url} — using bundled defaults instead. Reason: ${message}`,
    );
    applyThresholds(DEFAULT_THRESHOLDS);
    return { ok: false, source: 'default', error: message };
  }
}

/**
 * Throws a single Error listing EVERY violation found (not just the first)
 * so a malformed file's console message is immediately actionable rather
 * than requiring a fix-rerun-see-next-error loop.
 */
export function validateThresholds(data: unknown): ThresholdsConfig {
  const problems: string[] = [];
  const num = (v: unknown, path: string, opts?: { min?: number; max?: number; integer?: boolean }): number => {
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      problems.push(`${path}: expected a finite number, got ${JSON.stringify(v)}`);
      return NaN;
    }
    if (opts?.integer && !Number.isInteger(v)) problems.push(`${path}: expected an integer, got ${v}`);
    if (opts?.min !== undefined && v < opts.min) problems.push(`${path}: ${v} is below minimum ${opts.min}`);
    if (opts?.max !== undefined && v > opts.max) problems.push(`${path}: ${v} is above maximum ${opts.max}`);
    return v;
  };

  if (typeof data !== 'object' || data === null) {
    throw new Error('thresholds.json: expected a JSON object at the top level');
  }
  const d = data as Record<string, unknown>;
  const obj = (v: unknown, path: string): Record<string, unknown> => {
    if (typeof v !== 'object' || v === null) {
      problems.push(`${path}: expected an object, got ${JSON.stringify(v)}`);
      return {};
    }
    return v as Record<string, unknown>;
  };

  const pressure = obj(d.pressure, 'pressure');
  const temperature = obj(d.temperature, 'temperature');
  const asymmetry = obj(d.asymmetry, 'asymmetry');
  const model = obj(d.model, 'model');
  const motion = obj(d.motion, 'motion');

  const watchKpa = num(pressure.watchKpa, 'pressure.watchKpa', { min: 0 });
  const alertKpa = num(pressure.alertKpa, 'pressure.alertKpa', { min: 0 });
  const ptiKpaS = num(pressure.ptiKpaS, 'pressure.ptiKpaS', { min: 0 });
  const deltaC = num(temperature.deltaC, 'temperature.deltaC', { min: 0 });
  const consecutiveReadings = num(temperature.consecutiveReadings, 'temperature.consecutiveReadings', { min: 1, integer: true });
  const peakPct = num(asymmetry.peakPct, 'asymmetry.peakPct', { min: 0, max: 100 });
  const ptiPct = num(asymmetry.ptiPct, 'asymmetry.ptiPct', { min: 0, max: 100 });
  const concentrationPct = num(asymmetry.concentrationPct, 'asymmetry.concentrationPct', { min: 0, max: 100 });
  const minConfidence = num(model.minConfidence, 'model.minConfidence', { min: 0, max: 1 });
  const walkingAccelG = num(motion.walkingAccelG, 'motion.walkingAccelG', { min: 0 });
  const walkingWindowMs = num(motion.walkingWindowMs, 'motion.walkingWindowMs', { min: 1, integer: true });

  // Cross-field sanity, not just per-field range — a file that passes every
  // individual check above but sets watchKpa >= alertKpa would silently make
  // the watch tier unreachable (PRESSURE_WATCH_KPA's own branch in
  // AlertStore.evaluate() is `else if`, only reached when the alert-tier
  // check above it fails).
  if (Number.isFinite(watchKpa) && Number.isFinite(alertKpa) && watchKpa >= alertKpa) {
    problems.push(`pressure.watchKpa (${watchKpa}) must be less than pressure.alertKpa (${alertKpa})`);
  }

  if (problems.length > 0) {
    throw new Error(`thresholds.json failed validation:\n  - ${problems.join('\n  - ')}`);
  }

  return {
    version: typeof d.version === 'number' ? d.version : 1,
    pressure: { watchKpa, alertKpa, ptiKpaS },
    temperature: { deltaC, consecutiveReadings },
    asymmetry: { peakPct, ptiPct, concentrationPct },
    model: { minConfidence },
    motion: { walkingAccelG, walkingWindowMs },
  };
}

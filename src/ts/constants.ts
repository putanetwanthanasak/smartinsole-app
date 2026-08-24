// constants.ts — Thresholds, zone definitions, status meta, preset labels

import type { ZoneInfo, RiskStatus, StatusMeta, PresetName, FootPressure } from './types.js';
import type { GaitClass } from './data/types.js';

// ─── Runtime-loadable thresholds (Data Contract §8.3) ────────
//
// Every value in this section was a hardcoded TS constant until this pass
// (docs/reports/017-*.md) — §8.3 requires them to live in a runtime-loadable
// `thresholds.json` instead, specifically because they will need retuning
// after real-hardware testing, without a rebuild for each adjustment
// (docs/BACKLOG.md item 11).
//
// How this works, and why NOT ONE call site outside this file and
// data/thresholds.ts needed to change for this pass (grepped exhaustively —
// see the report): `DEFAULT_THRESHOLDS` below is the compiled-in fallback,
// always valid and present with zero network dependency, so the app is
// immediately usable even fully offline. Every threshold constant this file
// exports is declared `let`, not `const`, initialized from
// `DEFAULT_THRESHOLDS` at module load. `data/thresholds.ts` (invoked once at
// boot from main.ts, fire-and-forget) fetches `public/thresholds.json` — the
// same default values, but as an independently editable static file an
// ops/clinician can replace in a deployed build without a JS rebuild —
// validates it, and calls `applyThresholds()` below to overwrite these `let`
// bindings in place. ES modules give `let` exports LIVE bindings: every
// import of e.g. `PRESSURE_WATCH_KPA` anywhere in the app always sees the
// current value, because none of the existing consumers (heatmap.ts,
// gait.ts, pressureColor.ts, temperature.ts, home.ts, MockDataSource.ts,
// AlertStore.ts) copy a threshold into their own module-top-level variable —
// they all read the imported name at call time, inside a function invoked
// after boot. This is exactly what CLAUDE.md convention #6 ("thresholds live
// in constants.ts") already set up: one indirection point for the whole app,
// which is what makes swapping its backing store possible without touching
// a single screen.
//
// Two fields are the hard clinical floor and must never move except through
// `applyThresholds()` — see the comments at `PRESSURE_ALERT_KPA` and
// `TEMP_DELTA_THRESHOLD` below, and `setPatientSensitivity()` at the end of
// this section for the structural (not conventional) guarantee that a
// future patient-facing control can never reach them.

export interface ThresholdsConfig {
  version: number;
  pressure: { watchKpa: number; alertKpa: number; ptiKpaS: number };
  temperature: { deltaC: number; consecutiveReadings: number };
  asymmetry: { peakPct: number; ptiPct: number; concentrationPct: number };
  model: { minConfidence: number };
  /**
   * ADDITIVE — not part of Data Contract v1.4 §8.3's JSON shape. Needed for
   * the `PRESSURE_PEAK` walking-gate (docs/BACKLOG.md item 10's finding;
   * implemented this pass, docs/reports/017-*.md). Same status as the §5.1
   * `offset_adc`/`÷1000` fix from earlier passes: a local addition not yet
   * sent upstream to the contract owner. Revisit/remove this block if a
   * future contract version defines its own walking-gate shape instead.
   */
  motion: { walkingAccelG: number; walkingWindowMs: number };
}

/**
 * The compiled-in fallback. Every field matches Data Contract v1.4 §8.3's
 * JSON exactly (plus the additive `motion` block above). Used at boot before
 * the runtime file has loaded, and again any time that file is missing,
 * unreachable, or fails validation — `data/thresholds.ts` logs loudly when
 * that happens (see there); this object is what keeps the app running on
 * known-good values instead of silently ending up with `undefined`.
 *
 * Keep `public/thresholds.json` (the runtime-editable copy) in sync with
 * this by hand — there is no build step that generates one from the other.
 * Same accepted duplication as `css/heatmap.css` restating `PRESSURE_RAMP_KPA`
 * as gradient percentages (see `recomputeDerivedRamp()` below).
 */
export const DEFAULT_THRESHOLDS: Readonly<ThresholdsConfig> = Object.freeze({
  version: 1,
  pressure: Object.freeze({ watchKpa: 75, alertKpa: 200, ptiKpaS: 80 }),
  temperature: Object.freeze({ deltaC: 2.2, consecutiveReadings: 2 }),
  asymmetry: Object.freeze({ peakPct: 15, ptiPct: 20, concentrationPct: 40 }),
  model: Object.freeze({ minConfidence: 0.60 }),
  // PROVISIONAL, same status as the pressure tiers below — no real hardware
  // data exists yet to tune these against. 0.15g mean sustained deviation
  // from 1g over an 800ms window was chosen as a conservative gap between
  // typical quiet-stance sensor noise and typical gait acceleration, not
  // measured. See docs/reports/017-*.md and AlertStore.ts's isWalking().
  motion: Object.freeze({ walkingAccelG: 0.15, walkingWindowMs: 800 }),
});

// Plantar pressure is in kPa. The Data Contract fixes two tiers:
//   75 kPa  — watch  (surfaced on the heatmap, not notification-worthy)
//   200 kPa — alert  (notification-worthy, sourced from Owings et al. 2009,
//             measured with high-density research pressure mapping)
// Both are inclusive lower bounds: a zone at exactly 200 kPa is in the alert tier.
// PROVISIONAL, expect to recalibrate against real hardware. Two reasons to
// distrust 75 as a watch level: published peak plantar pressures for normal
// barefoot gait routinely exceed it, so taken literally this threshold would
// flag healthy walking; and this build has six discrete FSRs per foot rather
// than a full pressure mat, so a sensor rarely sits exactly on the true peak and
// measured values will under-read relative to the literature. Those two errors
// push in opposite directions and neither is quantified yet. The 200 kPa alert
// tier carries the identical under-reading problem, for the identical reason —
// Owings' figure also comes from a dense research mat, not six discrete points.
// Revisit both once real device data exists — do not tune this against the
// mock presets. See `docs/BACKLOG.md` item 4.
export let PRESSURE_WATCH_KPA = DEFAULT_THRESHOLDS.pressure.watchKpa;
/**
 * HARD CLINICAL FLOOR. Only `applyThresholds()` below may ever reassign this
 * — called exactly once per config load, only from `data/thresholds.ts`'s
 * loader (the trusted, ops/clinician-controlled `thresholds.json` channel,
 * NOT anything reachable from in-app UI). A future patient sensitivity
 * slider must call `setPatientSensitivity()` instead, whose parameter type
 * has no way to name this field at all — see that function's comment for
 * why this is structural, not conventional. Do not add a second writer.
 */
export let PRESSURE_ALERT_KPA = DEFAULT_THRESHOLDS.pressure.alertKpa;
/** Not consumed by any rule yet — `PRESSURE_PTI` isn't implemented (docs/BACKLOG.md item 9). Exists for shape parity with the contract's `thresholds.json`. */
export let PRESSURE_PTI_KPA_S = DEFAULT_THRESHOLDS.pressure.ptiKpaS;
// Top of the display scale — the heatmap legend and the gait bar chart both map
// values onto 0..this, so it is not merely cosmetic. Not part of the contract's
// thresholds.json (a display constant, not an alert threshold) — stays a plain
// const.
export const PRESSURE_SCALE_MAX_KPA = 250;

// °C between L/R same zone. Clinically validated threshold from Lavery et
// al. (2004) — a randomised controlled trial that validated 2.2°C against
// patient outcomes. That is external clinical validation, not a value this
// project agreed on internally, and it puts this constant in a different
// category from PRESSURE_WATCH_KPA/PRESSURE_ALERT_KPA above: the six-FSR
// absolute-magnitude under-reading caveat that applies to those two does NOT
// transfer here. ΔT is a differential between two feet measured by the same
// system, so absolute sensor error largely cancels out — the same reasoning
// that justifies using left-vs-right comparison for pressure asymmetry too.
//
// The limitation that IS ours: this system samples two points per foot
// (forefoot, heel) rather than the measurement protocol Lavery et al. used,
// so site selection — not the threshold value — is the open question here.
/**
 * HARD CLINICAL FLOOR, same status/enforcement as `PRESSURE_ALERT_KPA`
 * above — externally validated against patient outcomes (Lavery et al.
 * 2004), so a patient-side control has no business softening it. Only
 * `applyThresholds()` may reassign this.
 */
export let TEMP_DELTA_THRESHOLD = DEFAULT_THRESHOLDS.temperature.deltaC;
/**
 * Consecutive over-threshold ΔT readings required before `temp.delta`
 * fires (Data Contract §8.3: "ต่อเนื่อง ≥ 2 ครั้งวัด"). Was hardcoded as a
 * missing check entirely until this pass — see docs/BACKLOG.md item 10 and
 * `AlertStore.ts`'s `tempDeltaState`.
 */
export let TEMP_DELTA_CONSECUTIVE_READINGS = DEFAULT_THRESHOLDS.temperature.consecutiveReadings;

// PAI (Peak Asymmetry Index) watch threshold, as a percent: |L-R| / avg(L,R)
// x 100 above this is worth surfacing. Recorded in Data Contract §8.2 as the
// team's agreed figure — same evidentiary status as PRESSURE_WATCH_KPA above
// (agreed, not yet validated against measurement). See `docs/BACKLOG.md`
// item 1 for how gait.ts computes PAI itself.
export let PAI_WATCH_PCT = DEFAULT_THRESHOLDS.asymmetry.peakPct;
/** Not consumed by any rule yet — `ASYMMETRY_PEAK` isn't implemented (docs/BACKLOG.md item 9). Exists for shape parity with the contract's `thresholds.json`. */
export let PTI_ASYMMETRY_WATCH_PCT = DEFAULT_THRESHOLDS.asymmetry.ptiPct;
/** Not consumed by any rule yet — `LOAD_CONCENTRATION` isn't implemented (docs/BACKLOG.md item 9). Exists for shape parity with the contract's `thresholds.json`. */
export let LOAD_CONCENTRATION_ALERT_PCT = DEFAULT_THRESHOLDS.asymmetry.concentrationPct;

/**
 * Sustained mean deviation from 1g, over `WALKING_WINDOW_MS`, required to
 * count as "walking" for the `PRESSURE_PEAK` walking-gate. ADDITIVE, not in
 * the Data Contract yet — see `ThresholdsConfig.motion` above.
 */
export let WALKING_ACCEL_G = DEFAULT_THRESHOLDS.motion.walkingAccelG;
export let WALKING_WINDOW_MS = DEFAULT_THRESHOLDS.motion.walkingWindowMs;

// Six-stop colour ramp, expressed in kPa and derived from the two contract
// thresholds so the ramp can never drift away from the tiers it depicts.
// `watch` and `alert` are the tier boundaries themselves; `low`/`mid` subdivide
// the safe tier and `watchHigh` splits the (wide) watch tier in half.
//
// A plain mutable object (NOT `as const`, NOT frozen) so `recomputeDerivedRamp()`
// can update its properties in place after a threshold reload — object identity
// stays the same, so every existing reader (pressureColor.ts, heatmap.ts,
// MockDataSource.ts) sees the update without re-importing anything.
//
// css/heatmap.css draws the same ramp as a gradient. It does NOT restate these
// numbers: Heatmap.renderLegend() converts each stop to a percentage of
// PRESSURE_SCALE_MAX_KPA and feeds them in as --stop-* custom properties.
export const PRESSURE_RAMP_KPA = {
  low:       PRESSURE_WATCH_KPA / 3,
  mid:       (PRESSURE_WATCH_KPA * 2) / 3,
  watch:     PRESSURE_WATCH_KPA,
  watchHigh: (PRESSURE_WATCH_KPA + PRESSURE_ALERT_KPA) / 2,
  alert:     PRESSURE_ALERT_KPA,
};

// Zone fills below this value are dark enough that the numeric label on top of
// them needs to flip to white. This is a TEXT-CONTRAST boundary, not a clinical
// one — it tracks the colour ramp (the blue and green bands), so it moves if the
// ramp's colours change and has no meaning in the Data Contract.
export let PRESSURE_LABEL_INVERT_MAX_KPA = PRESSURE_RAMP_KPA.mid;

function recomputeDerivedRamp(): void {
  PRESSURE_RAMP_KPA.low       = PRESSURE_WATCH_KPA / 3;
  PRESSURE_RAMP_KPA.mid       = (PRESSURE_WATCH_KPA * 2) / 3;
  PRESSURE_RAMP_KPA.watch     = PRESSURE_WATCH_KPA;
  PRESSURE_RAMP_KPA.watchHigh = (PRESSURE_WATCH_KPA + PRESSURE_ALERT_KPA) / 2;
  PRESSURE_RAMP_KPA.alert     = PRESSURE_ALERT_KPA;
  PRESSURE_LABEL_INVERT_MAX_KPA = PRESSURE_RAMP_KPA.mid;
}

// Model A's minimum acceptable confidence, per Data Contract §7.5 / §8.3.1
// (`thresholds.json`'s `model.minConfidence`). Used only by the §8.3.1
// gait-pattern advisory layer today (AlertStore) — nothing in this codebase
// acts on Model A's argmax class directly (see docs/BACKLOG.md items 8/9).
export let MIN_CONFIDENCE = DEFAULT_THRESHOLDS.model.minConfidence;

/**
 * The ONE function allowed to write the hard-floor fields
 * (`PRESSURE_ALERT_KPA`, `TEMP_DELTA_THRESHOLD`) — called only by
 * `data/thresholds.ts`'s loader, after it has fetched and validated a
 * `thresholds.json`. Not for UI code. See `setPatientSensitivity()` below
 * for the function UI code should call instead.
 */
export function applyThresholds(cfg: ThresholdsConfig): void {
  PRESSURE_WATCH_KPA = cfg.pressure.watchKpa;
  PRESSURE_ALERT_KPA = cfg.pressure.alertKpa;
  PRESSURE_PTI_KPA_S = cfg.pressure.ptiKpaS;
  TEMP_DELTA_THRESHOLD = cfg.temperature.deltaC;
  TEMP_DELTA_CONSECUTIVE_READINGS = cfg.temperature.consecutiveReadings;
  PAI_WATCH_PCT = cfg.asymmetry.peakPct;
  PTI_ASYMMETRY_WATCH_PCT = cfg.asymmetry.ptiPct;
  LOAD_CONCENTRATION_ALERT_PCT = cfg.asymmetry.concentrationPct;
  MIN_CONFIDENCE = cfg.model.minConfidence;
  WALKING_ACCEL_G = cfg.motion.walkingAccelG;
  WALKING_WINDOW_MS = cfg.motion.walkingWindowMs;
  recomputeDerivedRamp();
}

/**
 * The ONLY threshold mutator meant to ever be reachable from a UI control
 * (the not-yet-built patient sensitivity slider, docs/BACKLOG.md item 5).
 * This is where "the slider must never touch the hard floor" is enforced
 * STRUCTURALLY, not by convention: this function's parameter is a bare
 * percent — there is no field in its signature that could name
 * `PRESSURE_ALERT_KPA` or `TEMP_DELTA_THRESHOLD`, so no caller, however
 * malicious or buggy, can reach them through this entry point. The
 * implementation below only ever assigns `PRESSURE_WATCH_KPA`.
 *
 * `pct`: 0 = least sensitive (watch tier at its max bound), 100 = most
 * sensitive (watch tier at its min bound). The bounds themselves
 * (`WATCH_KPA_MIN`/`MAX` below) are a placeholder pending real clinician
 * input — same "provisional, needs a real decision" status as every other
 * unvalidated number in this file, flagged so it isn't mistaken for a
 * clinically-set figure. Never built into a slider UI this pass (out of
 * scope, see docs/reports/017-*.md) — this exists so that pass has
 * something correct to wire up to, per this pass's brief.
 *
 * Item 5's older note also mentions scaling "the ΔT alert margin" — not
 * implemented here: the contract's `thresholds.json` shape has no separate
 * soft ΔT tier to scale (only the hard-floor `deltaC`), so there is nothing
 * for this function to adjust on the temperature side yet. If the contract
 * ever grows one, extend this function the same narrow-parameter way, never
 * by giving it access to `TEMP_DELTA_THRESHOLD`.
 */
const WATCH_KPA_MIN = 50;
const WATCH_KPA_MAX = 100;
export function setPatientSensitivity(pct: number): void {
  const p = Math.max(0, Math.min(100, pct));
  PRESSURE_WATCH_KPA = WATCH_KPA_MAX - (p / 100) * (WATCH_KPA_MAX - WATCH_KPA_MIN);
  recomputeDerivedRamp();
}

// ─── Gait-pattern advisory text (Data Contract §8.3.1) ───────
// NOT an alert rule — AlertStore only appends this sentence to an alert that
// already fired from an existing pressure rule (PRESSURE_WATCH/PRESSURE_PEAK
// today; PRESSURE_PTI/LOAD_CONCENTRATION once those exist, see
// docs/BACKLOG.md item 9), when Model A's most recent prediction at that
// zone meets MIN_CONFIDENCE. It never fires an alert on its own and never
// changes statusLevel/severity — see docs/DATA-CONTRACT.md §8.3.1.
//
// `zones: 'any'` means the sentence is appended regardless of which zone
// triggered (matches the contract's treatment of `antalgic`, whose evidence
// doesn't support a specific site). `rotated_foot` is ALSO treated as
// `zones: 'any'` here, with a direction-neutral sentence that departs from
// the contract's table: the contract's in-toeing/out-toeing wording needs a
// direction Model A's output alone doesn't carry (that's only captured as
// research-capture session metadata, PatternNotes.rotatedFootNote — not
// available to live AlertStore). Confirmed with the user rather than
// guessing a direction from pressure asymmetry, which would violate this
// app's no-fabricated-bilateral-readings rule the same way inferring an
// unmeasured value would. Revisit if Model A ever adds direction as a
// separate output.
export const GAIT_ADVISORY: Record<GaitClass, { zones: (keyof FootPressure)[] | 'any'; th: string } | null> = {
  normal: null,
  heel_walking: {
    zones: ['heel'],
    th: 'ตรวจพบรูปแบบเดินลงส้น ซึ่งอาจเพิ่มแรงกดบริเวณส้นเท้า',
  },
  toe_walking: {
    zones: ['hallux', 'meta1'],
    th: 'ตรวจพบรูปแบบเดินเขย่งปลายเท้า ซึ่งอาจเพิ่มแรงกดบริเวณปลายเท้า',
  },
  rotated_foot: {
    zones: 'any',
    th: 'ตรวจพบรูปแบบเดินบิดเท้า ทิศทางอาจมีผลต่อจุดรับน้ำหนัก — ยังไม่มีข้อมูลยืนยันตำแหน่งแน่ชัด',
  },
  antalgic: {
    zones: 'any',
    th: 'ตรวจพบรูปแบบเดินไม่สมมาตร ควรตรวจสอบแรงกดทั้งสองข้างเทียบกัน',
  },
};

// ─── FSR channel order ──────────────────────────────────────
// The BLE payload carries pressure as an indexed fsrKpa[6]; the UI stores a
// name-keyed FootPressure object. This is the one authoritative mapping between
// the two, and the order is fixed by the Data Contract. Nothing consumes it yet —
// it exists so that when the BLE adapter lands there is no second opinion about
// which array slot is which zone. Confirmed against Data Contract v1.1 §3.1 —
// index 0..5 = hallux, 1st MTH, 3rd MTH, 5th MTH, midfoot/lateral arch, heel.
// See docs/BLE-INTERFACE.md for the full packet-offset table this maps into.
export const FSR_CHANNEL_ORDER = ['hallux', 'meta1', 'meta3', 'meta5', 'midfoot', 'heel'] as const;

// ─── Zone definitions for a LEFT foot (plantar / sole view) ──
// ViewBox: 0 0 100 270. Big toe is on the medial side (right side
// of the SVG); the right foot mirrors via transform=scaleX(-1).
export const ZONES: ZoneInfo[] = [
  // Key is the contract's anatomical name; the label stays patient-facing.
  { id: 'hallux',  labelTH: 'นิ้วหัวแม่เท้า', labelEN: 'Big toe',         cx: 76, cy: 26,  rx: 13.5, ry: 11   },
  { id: 'meta1',   labelTH: 'เนินเท้าที่ 1',  labelEN: '1st metatarsal',  cx: 75, cy: 78,  rx: 13,   ry: 11   },
  { id: 'meta3',   labelTH: 'เนินเท้าที่ 3',  labelEN: '3rd metatarsal',  cx: 50, cy: 86,  rx: 13,   ry: 11   },
  { id: 'meta5',   labelTH: 'เนินเท้าที่ 5',  labelEN: '5th metatarsal',  cx: 24, cy: 92,  rx: 12,   ry: 10.5 },
  { id: 'midfoot', labelTH: 'อุ้งเท้า',        labelEN: 'Midfoot',         cx: 32, cy: 152, rx: 13,   ry: 18   },
  { id: 'heel',    labelTH: 'ส้นเท้า',         labelEN: 'Heel',            cx: 47, cy: 222, rx: 18,   ry: 16   },
];

// ─── Foot silhouette path (left foot, plantar view) ─────────
export const FOOT_BODY_PATH = `
  M 47 257
  C 73 257 76 232 73 210
  C 71 192 78 168 79 148
  C 81 128 88 110 84 88
  C 80 65 70 52 60 49
  C 50 47 40 47 30 50
  C 18 54 12 70 10 92
  C 8 112 16 132 18 152
  C 19 172 25 192 22 212
  C 20 234 22 257 47 257 Z
`;

export interface ToeShape { cx: number; cy: number; rx: number; ry: number; }
export const TOES: ToeShape[] = [
  { cx: 76, cy: 26, rx: 13,  ry: 11.5 },
  { cx: 56, cy: 18, rx:  9,  ry:  9.5 },
  { cx: 40, cy: 16, rx:  8,  ry:  9   },
  { cx: 25, cy: 18, rx:  7.5,ry:  8.5 },
  { cx: 12, cy: 24, rx:  7,  ry:  8   },
];

// ─── 6-state AI classifier metadata ─────────────────────────
export const STATUS_META: Record<RiskStatus, StatusMeta> = {
  0: { th: 'ไม่ได้สวมใส่',           en: 'Not worn',          tone: 'neutral', color: '#8A8F95', soft: '#F1ECE0' },
  1: { th: 'เดินปกติ',                en: 'Normal walking',    tone: 'safe',    color: '#22C55E', soft: '#DCFCE7' },
  2: { th: 'ความไม่สมมาตรเล็กน้อย',    en: 'Minor asymmetry',   tone: 'warn',    color: '#F59E0B', soft: '#FEF3C7' },
  3: { th: 'แรงกดสูงผิดปกติ',          en: 'Elevated pressure', tone: 'warn',    color: '#F59E0B', soft: '#FEF3C7' },
  4: { th: 'อุณหภูมิผิดปกติ',           en: 'Temperature alert', tone: 'danger',  color: '#EF4444', soft: '#FEE2E2' },
  5: { th: 'เตือนภัยความเสี่ยงสูง',     en: 'High-risk warning', tone: 'danger',  color: '#EF4444', soft: '#FEE2E2' },
};

// ─── Preset display labels ──────────────────────────────────
export interface PresetLabel { id: PresetName; th: string; en: string; }
export const PRESET_LABELS: PresetLabel[] = [
  { id: 'normal',    th: 'เดินปกติ',         en: 'Normal'      },
  { id: 'diabetic',  th: 'ผู้ป่วยเบาหวาน',    en: 'Diabetic'    },
  { id: 'heavyHeel', th: 'ลงส้นหนัก',         en: 'Heel strike' },
  { id: 'forefoot',  th: 'ลงหน้าเท้าหนัก',   en: 'Forefoot'    },
];

// ─── Alert recommendations (TH + EN) ────────────────────────
export interface AlertRecommendation { th: string; en: string; }
export const ALERT_RECOMMENDATIONS: Record<'pressure' | 'temperature' | 'gait', AlertRecommendation> = {
  pressure:    { th: 'ลองเปลี่ยนรองเท้าให้พื้นนุ่มขึ้น', en: 'Try changing to softer shoes'      },
  temperature: { th: 'ควรพบแพทย์ภายใน 24–48 ชั่วโมง',    en: 'See your doctor within 24–48 hrs' },
  gait:        { th: 'ลดระยะเวลาเดินและพักเท้าบ่อย ๆ',  en: 'Reduce walking and rest more often' },
};

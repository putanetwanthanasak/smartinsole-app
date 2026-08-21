// constants.ts — Thresholds, zone definitions, status meta, preset labels

import type { ZoneInfo, RiskStatus, StatusMeta, PresetName } from './types.js';

// ─── Clinical thresholds ────────────────────────────────────
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
// mock presets.
//
// Both values also appear in Data Contract v1.1 §8.3 (`docs/DATA-CONTRACT.md`)
// as the team's agreed figures. That is not the same claim as "validated
// against measurement" — the contract records what was agreed, not what has
// been checked against real device data, and its own §8.3 note states this
// exact under-reading gap in the contract's own words. Being in the contract
// changes where these numbers are recorded, not their evidentiary status;
// keep treating them as provisional. See `docs/BACKLOG.md` item 4.
//
// Separate, architectural point: the contract requires ALL threshold values
// to live in a runtime `thresholds.json`, not be hardcoded in source (§8.3 —
// they will definitely need tuning after real-hardware testing, without a
// rebuild). This file still hardcodes them as TS constants; not fixed here,
// see `docs/BACKLOG.md` item 11.
export const PRESSURE_WATCH_KPA     = 75;
export const PRESSURE_ALERT_KPA     = 200;
// Top of the display scale — the heatmap legend and the gait bar chart both map
// values onto 0..this, so it is not merely cosmetic.
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
//
// One additional gap vs. the contract's own condition (Data Contract v1.1
// §8.3): the contract requires this to fire only after ≥2 consecutive
// over-threshold readings ("ต่อเนื่อง ≥ 2 ครั้งวัด"); `AlertStore.evaluate()`
// currently fires on a single reading. Not changed here — see
// `docs/BACKLOG.md` item 10.
export const TEMP_DELTA_THRESHOLD   = 2.2;

// PAI (Peak Asymmetry Index) watch threshold, as a percent: |L-R| / avg(L,R)
// x 100 above this is worth surfacing. Recorded in Data Contract v1.1 §8.2 as
// the team's agreed figure — same evidentiary status as PRESSURE_WATCH_KPA
// above (agreed, not yet validated against measurement), see
// `docs/BACKLOG.md` item 4 for that distinction and item 11 for why this
// still lives here as a TS constant instead of in a runtime thresholds.json.
// See `docs/BACKLOG.md` item 1 for how gait.ts computes PAI itself.
export const PAI_WATCH_PCT = 15;

// Six-stop colour ramp, expressed in kPa and derived from the two contract
// thresholds so the ramp can never drift away from the tiers it depicts.
// `watch` and `alert` are the tier boundaries themselves; `low`/`mid` subdivide
// the safe tier and `watchHigh` splits the (wide) watch tier in half.
//
// css/heatmap.css draws the same ramp as a gradient. It does NOT restate these
// numbers: Heatmap.renderLegend() converts each stop to a percentage of
// PRESSURE_SCALE_MAX_KPA and feeds them in as --stop-* custom properties.
export const PRESSURE_RAMP_KPA = {
  low:       PRESSURE_WATCH_KPA / 3,                          //  25
  mid:       (PRESSURE_WATCH_KPA * 2) / 3,                    //  50
  watch:     PRESSURE_WATCH_KPA,                              //  75
  watchHigh: (PRESSURE_WATCH_KPA + PRESSURE_ALERT_KPA) / 2,   // 137.5
  alert:     PRESSURE_ALERT_KPA,                              // 200
} as const;

// Zone fills below this value are dark enough that the numeric label on top of
// them needs to flip to white. This is a TEXT-CONTRAST boundary, not a clinical
// one — it tracks the colour ramp (the blue and green bands), so it moves if the
// ramp's colours change and has no meaning in the Data Contract.
export const PRESSURE_LABEL_INVERT_MAX_KPA = PRESSURE_RAMP_KPA.mid;

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

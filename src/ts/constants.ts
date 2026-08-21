// constants.ts — Thresholds, zone definitions, status meta, preset labels

import type { ZoneInfo, RiskStatus, StatusMeta, PresetName } from './types.js';

// ─── Clinical thresholds ────────────────────────────────────
// Plantar pressure is in kPa. The Data Contract fixes two tiers:
//   75 kPa  — watch  (surfaced on the heatmap, not notification-worthy)
//   200 kPa — alert  (notification-worthy)
// Both are inclusive lower bounds: a zone at exactly 200 kPa is in the alert tier.
// PROVISIONAL, expect to recalibrate against real hardware. Two reasons to
// distrust 75 as a watch level: published peak plantar pressures for normal
// barefoot gait routinely exceed it, so taken literally this threshold would
// flag healthy walking; and this build has six discrete FSRs per foot rather
// than a full pressure mat, so a sensor rarely sits exactly on the true peak and
// measured values will under-read relative to the literature. Those two errors
// push in opposite directions and neither is quantified yet. Revisit once real
// device data exists — do not tune this against the mock presets.
export const PRESSURE_WATCH_KPA     = 75;
export const PRESSURE_ALERT_KPA     = 200;
// Top of the display scale — the heatmap legend and the gait bar chart both map
// values onto 0..this, so it is not merely cosmetic.
export const PRESSURE_SCALE_MAX_KPA = 250;

export const TEMP_DELTA_THRESHOLD   = 2.2;            // °C between L/R same zone

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
// which array slot is which zone.
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

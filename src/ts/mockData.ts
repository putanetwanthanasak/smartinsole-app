// mockData.ts — All simulated data + 4 presets (typed)

import type { AppData, PressureData, PresetName } from './types.js';

/**
 * Anchor a seed alert to a wall-clock time relative to today, so the strings the
 * Alerts screen derives ('14:32', 'เมื่อวาน 18:05', '2 วันก่อน 09:10') stay
 * exactly what the old hardcoded `time` fields said, whatever day it is run.
 */
function at(daysAgo: number, hh: number, mm: number): number {
  const d = new Date();
  d.setHours(hh, mm, 0, 0);
  d.setDate(d.getDate() - daysAgo);
  return d.getTime();
}

// Peak plantar pressure per zone, in kPa, on the 0–PRESSURE_SCALE_MAX_KPA display
// scale. Tiers: < 75 safe · 75–199 watch · >= 200 alert.
//
// These were converted from the old unitless 0–100 index. The base conversion is
// ×2.5 (0–100 → 0–250), which leaves every preset's shape and every bar height
// unchanged; three deliberate departures from it:
//
//   • `normal` uses ×1.4, not ×2.5. At ×2.5 every zone would land in the watch
//     tier, which contradicts the scenario — "normal walking" must read as
//     nothing-flagged, so it stays below 75 everywhere (max 70).
//   • `diabetic` left meta3 and `forefoot` right meta1/meta3 were nudged up over
//     200. At a plain ×2.5 they land at 195, just under the alert line, which
//     would silently drop them out of the high-risk count they were in before.
//
// The zones in the top tier are therefore exactly the ones that were in the top
// tier under the old threshold: 0 / 2 / 2 / 4 for normal / diabetic / heavyHeel /
// forefoot. Keep it that way if you edit these — the risk summary, the pulse
// rings and Home's status badge are all driven off that count.
export const PRESETS: Record<PresetName, PressureData> = {
  normal: {
    left:  { hallux:  49, meta1:  63, meta3:  56, meta5:  42, midfoot: 28, heel:  70 },
    right: { hallux:  46, meta1:  60, meta3:  53, meta5:  39, midfoot: 25, heel:  67 },
  },
  diabetic: {
    left:  { hallux: 100, meta1: 220, meta3: 205, meta5: 138, midfoot: 62, heel: 162 },
    right: { hallux:  88, meta1: 138, meta3: 120, meta5:  88, midfoot: 50, heel: 125 },
  },
  heavyHeel: {
    left:  { hallux:  50, meta1:  88, meta3:  75, meta5:  62, midfoot: 75, heel: 230 },
    right: { hallux:  45, meta1:  80, meta3:  70, meta5:  55, midfoot: 70, heel: 220 },
  },
  forefoot: {
    left:  { hallux: 175, meta1: 212, meta3: 205, meta5: 150, midfoot: 38, heel:  62 },
    right: { hallux: 162, meta1: 205, meta3: 202, meta5: 138, midfoot: 30, heel:  55 },
  },
};

export const MOCK_DATA: AppData = {
  connectionStatus: { left: true, right: true },
  batteryLevel: { left: 78, right: 82 },
  currentStatus: 3,

  // Default snapshot used on initial load (matches the diabetic preset)
  pressure: PRESETS.diabetic,

  presets: PRESETS,

  temperature: {
    left:  { forefoot: 31.8, heel: 30.5 },
    right: { forefoot: 29.4, heel: 30.2 },
  },

  todaySummary: {
    steps: 4230,
    walkingMinutes: 38,
    gaitSymmetryScore: 72,
  },

  gaitHistory7Days: [85, 78, 80, 76, 74, 72, 72],

  temperatureHistory24h: [
    { hour: '06:00', leftForefoot: 30.1, rightForefoot: 29.8 },
    { hour: '08:00', leftForefoot: 30.5, rightForefoot: 29.5 },
    { hour: '10:00', leftForefoot: 31.0, rightForefoot: 29.3 },
    { hour: '12:00', leftForefoot: 31.5, rightForefoot: 29.2 },
    { hour: '14:00', leftForefoot: 31.8, rightForefoot: 29.4 },
    { hour: '16:00', leftForefoot: 31.6, rightForefoot: 29.5 },
  ],

  // Seed log. The three that used to be appended inside alerts.ts as
  // EXTRA_ALERTS now live here too — they were always seed data, and keeping two
  // sources of mock alerts meant the Alerts screen and the tab badge disagreed
  // about how many alerts existed.
  recentAlerts: [
    { id: 1, tUnixMs: at(0, 14, 32), type: 'pressure',    severity: 'warning', message: 'แรงกดสูงบริเวณเนินปลายเท้าซ้าย',         acknowledged: false },
    { id: 2, tUnixMs: at(0, 12, 15), type: 'temperature', severity: 'danger',  message: 'ผลต่างอุณหภูมิเท้าหน้า 2.4°C เกินค่ามาตรฐาน', acknowledged: true  },
    { id: 3, tUnixMs: at(0,  9, 40), type: 'gait',        severity: 'caution', message: 'ตรวจพบการเดินไม่สมมาตรเล็กน้อย',         acknowledged: true  },
    { id: 4, tUnixMs: at(1, 18,  5), type: 'pressure',    severity: 'danger',  message: 'แรงกดเกินเกณฑ์ที่ส้นเท้าขวา 92',          acknowledged: true  },
    { id: 5, tUnixMs: at(1, 14, 20), type: 'gait',        severity: 'warning', message: 'การเดินไม่สมมาตร · ซ้ายช้ากว่าขวา',      acknowledged: true  },
    { id: 6, tUnixMs: at(2,  9, 10), type: 'temperature', severity: 'caution', message: 'อุณหภูมิเท้าหน้าซ้ายเพิ่ม 0.6°C',        acknowledged: true  },
  ],
};

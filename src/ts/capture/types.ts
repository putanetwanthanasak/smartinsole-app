// capture/types.ts — types for research capture mode (docs/reports/010-*.md).
//
// This is the ONLY place GaitLabel and the CSV row shape are defined. The CSV
// column list (CSV_COLUMNS) is dictated by an external Python training
// pipeline that already parses these exact names — do not rename, reorder,
// or add/remove columns here without checking with that pipeline's owner
// first (see the report for the full instruction this implements).

import type { FootSide } from '../types.js';

// ─── Gait patterns (Data Contract v1.2 §7.2 / §6 GaitClass) ────
// Index order matters (matches the contract's Model A output index), even
// though the CSV stores the STRING label, not the index — an index
// off-by-one would silently mislabel a whole dataset, which is exactly what
// storing the string instead of the index defends against.

export type GaitLabel = 'normal' | 'antalgic' | 'toe_walking' | 'heel_walking' | 'rotated_foot';

export interface GaitLabelMeta {
  id: GaitLabel;
  index: 0 | 1 | 2 | 3 | 4;
  th: string;
  en: string;
}

export const GAIT_LABELS: GaitLabelMeta[] = [
  { id: 'normal',       index: 0, th: 'เดินปกติ',           en: 'Normal' },
  { id: 'antalgic',     index: 1, th: 'เดินกะเผลก',          en: 'Antalgic' },
  { id: 'toe_walking',  index: 2, th: 'เดินเขย่งปลายเท้า',    en: 'Toe walking' },
  { id: 'heel_walking', index: 3, th: 'เดินลงส้น',           en: 'Heel walking' },
  { id: 'rotated_foot', index: 4, th: 'เดินบิดเท้า',          en: 'Rotated foot' },
];

// ─── Subject (per Data Contract ethics requirement: random code only) ──

export type Sex = 'male' | 'female' | 'other';

export interface SubjectInfo {
  subjectId: string;           // e.g. "SI-001" — random code, NEVER a name/ID
  age: number | null;
  sex: Sex | null;
  weightKg: number | null;
  heightCm: number | null;
  footLengthLeftCm: number | null;
  footLengthRightCm: number | null;
  dominantSide: FootSide | null;
  roomTempC: number | null;
  humidityPct: number | null;
}

export function emptySubject(): SubjectInfo {
  return {
    subjectId: '', age: null, sex: null, weightKg: null, heightCm: null,
    footLengthLeftCm: null, footLengthRightCm: null, dominantSide: null,
    roomTempC: null, humidityPct: null,
  };
}

// ─── Session calibration (30s standing-still baseline) ──────────

export interface SideCalibration {
  /** Mean resting pressure per zone over the 30s window, in kPa. Null if that side never reported a usable sample during calibration. */
  restingKpa: Record<'hallux' | 'meta1' | 'meta3' | 'meta5' | 'midfoot' | 'heel', number> | null;
  forefootC: number | null;
  heelC: number | null;
}

export interface SessionCalibration {
  capturedAtUnixMs: number;
  left: SideCalibration;
  right: SideCalibration;
  /** |left.forefootC - right.forefootC|, null unless both sides reported a forefoot temp. Should be near zero; not blocking if it isn't — see CALIBRATION_DELTA_WARN_C. */
  startingDeltaTC: number | null;
}

// ─── Per-pattern operator notes (protocol requirements that aren't per-sample) ──

export type RotationNote = 'in-toeing' | 'out-toeing';

export interface PatternNotes {
  /** Which side was instructed to "limp" for antalgic — alternates between subjects per protocol, recorded once per session. */
  antalgicAffectedSide: FootSide | null;
  /** in-toeing vs out-toeing for rotated_foot — both share one class label, this is a note only. */
  rotatedFootNote: RotationNote | null;
}

export function emptyPatternNotes(): PatternNotes {
  return { antalgicAffectedSide: null, rotatedFootNote: null };
}

// ─── Session record (IndexedDB `sessions` store) ─────────────────

export interface SessionRecord {
  sessionId: string;
  subject: SubjectInfo;
  calibration: SessionCalibration | null;
  notes: PatternNotes;
  startedAtUnixMs: number;
  /** Null while the session is still open (used to detect an interrupted session on reload). */
  endedAtUnixMs: number | null;
  /** Set after a successful export; gates the delete-after-export action. */
  exportedAtUnixMs: number | null;
  /** Running per-pattern sample counts, mirrored here on every flush so a reload can restore the completion display without rescanning every sample row. Keyed by GaitLabel, one count per side. */
  patternCounts: Record<GaitLabel, { left: number; right: number }>;
}

export function emptyPatternCounts(): Record<GaitLabel, { left: number; right: number }> {
  const out = {} as Record<GaitLabel, { left: number; right: number }>;
  for (const g of GAIT_LABELS) out[g.id] = { left: 0, right: 0 };
  return out;
}

// ─── Sample row (IndexedDB `samples` store AND the CSV row shape) ──
//
// Field names double as the CSV header row. side is 'L'/'R' (not FootSide's
// 'left'/'right') and gaitLabel is the class STRING, not the index — both
// per the fixed schema in docs/reports/010-*.md.

export type CsvSide = 'L' | 'R';

export interface SampleRow {
  subjectId: string;
  sessionId: string;
  tUnixMs: number;
  side: CsvSide;
  gaitLabel: GaitLabel;
  isValid: boolean;
  fsr_hallux: number;
  fsr_meta1: number;
  fsr_meta3: number;
  fsr_meta5: number;
  fsr_midfoot: number;
  fsr_heel: number;
  accel_x: number;
  accel_y: number;
  accel_z: number;
  gyro_x: number;
  gyro_y: number;
  gyro_z: number;
}

/** Fixed column order — the CSV writer uses this list explicitly rather than trusting object key order. DO NOT reorder/rename/add/remove without checking with the training pipeline owner. */
export const CSV_COLUMNS: (keyof SampleRow)[] = [
  'subjectId', 'sessionId', 'tUnixMs', 'side', 'gaitLabel', 'isValid',
  'fsr_hallux', 'fsr_meta1', 'fsr_meta3', 'fsr_meta5', 'fsr_midfoot', 'fsr_heel',
  'accel_x', 'accel_y', 'accel_z', 'gyro_x', 'gyro_y', 'gyro_z',
];

export function toCsvSide(s: FootSide): CsvSide { return s === 'left' ? 'L' : 'R'; }

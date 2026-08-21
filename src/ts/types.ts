// types.ts — All shared interfaces, types, and enums

// Pressure data for a single foot (6 zones), in kPa.
// Key names are the Data Contract's anatomical names. The contract also fixes the
// channel ORDER for the indexed BLE payload — see FSR_CHANNEL_ORDER in constants.ts.
export interface FootPressure {
  hallux: number;
  meta1: number;
  meta3: number;
  meta5: number;
  midfoot: number;
  heel: number;
}

// Both feet pressure
export interface PressureData {
  left: FootPressure;
  right: FootPressure;
}

// Foot temperature (forefoot + heel sensors per foot)
export interface FootTemperature {
  forefoot: number;
  heel: number;
}

// Zone metadata — drives the SVG rendering of each pressure zone
export interface ZoneInfo {
  id: keyof FootPressure;
  labelTH: string;
  labelEN: string;
  // SVG coordinates (within the 100x270 viewBox of one foot)
  cx: number;
  cy: number;
  rx: number;
  ry: number;
}

// Severity levels (used across pressure, temp, gait)
export type SeverityLevel = 'safe' | 'caution' | 'warning' | 'danger';

// Alert entry
//
// `tUnixMs` replaces the old `time: string` (values like 'เมื่อวาน 18:05').
// Storing the display string meant the day grouping had to be recovered by
// substring-matching Thai words out of it, which no real timestamped alert would
// ever satisfy. The string is now derived for display; the instant is the datum.
export interface AlertEntry {
  id: number;
  tUnixMs: number;
  type: 'pressure' | 'temperature' | 'gait';
  severity: SeverityLevel;
  message: string;
  acknowledged: boolean;
}

// AI classifier risk status.
//
// 1–5 are the Data Contract's risk levels. 0 is deliberately NOT a contract level:
// it is a UI state meaning "not worn / no data", which the contract has no way to
// express. Do not "fix" this to 1–5 to match the contract — the app needs somewhere
// to sit when no data is arriving, and that need grows once the two insoles are
// independent BLE peripherals and one side can be absent while the other reports.
export type RiskStatus = 0 | 1 | 2 | 3 | 4 | 5;

// Preset scenario names
export type PresetName = 'normal' | 'diabetic' | 'heavyHeel' | 'forefoot';

// Seed data only — the shape of the canned 24h curve MockDataSource backfills
// from. The RUNTIME history shape is TempHistoryPoint in data/types.ts, which is
// per-side and carries both channels; this one cannot represent a missing foot
// and is not used for rendering.
export interface TempSeedPoint {
  hour: string;
  leftForefoot: number;
  rightForefoot: number;
}

// Daily summary
export interface DailySummary {
  steps: number;
  walkingMinutes: number;
  gaitSymmetryScore: number;
}

// Side identifier
export type FootSide = 'left' | 'right';

// Tooltip data when a zone is tapped
export interface ZoneTooltipData {
  side: FootSide;
  zone: ZoneInfo;
  value: number;
}

// Status metadata for one of the 6 risk states
export interface StatusMeta {
  th: string;
  en: string;
  tone: 'neutral' | 'safe' | 'warn' | 'danger';
  color: string;
  soft: string;
}

// Complete app state
export interface AppData {
  connectionStatus: { left: boolean; right: boolean };
  batteryLevel: { left: number; right: number };
  currentStatus: RiskStatus;
  pressure: PressureData;
  presets: Record<PresetName, PressureData>;
  temperature: { left: FootTemperature; right: FootTemperature };
  todaySummary: DailySummary;
  gaitHistory7Days: number[];
  temperatureHistory24h: TempSeedPoint[];
  recentAlerts: AlertEntry[];
}

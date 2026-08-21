// gait.ts — Gait Analysis screen.
//
// Wired to the data seam for exactly one metric: PAI (Peak Asymmetry Index),
// a rolling-window figure computed from the live pressure stream. Everything
// else on this screen (classifier verdict, CoP trajectory, 7-day symmetry
// trend) has no real data source yet and renders an explicit unavailable
// state instead of the placeholder numbers this screen used to show — see
// docs/BACKLOG.md item 1 for the full decision and requirements this file
// implements.
//
// HARD CONSTRAINT (docs/BACKLOG.md item 1): the words "stride" / "ก้าว" must
// not appear anywhere in the PAI section below — heading, axis label,
// legend, tooltip, or any other label. PAI is a fixed-duration rolling
// window over recent samples, not stride-segmented gait data; stride
// segmentation needs IMU processing this app does not implement. Grepped
// clean before this file was committed — see docs/reports/003-gait-pai.md.

import { PRESSURE_SCALE_MAX_KPA, PAI_WATCH_PCT } from './constants.js';
import { initNavigation, renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import { deviceManager } from './data/DeviceManager.js';
import { isUsable } from './data/types.js';
import type { CombinedSnapshot, RawPressureSample, Unsubscribe } from './data/types.js';
import type { FootPressure } from './types.js';

// ─── Rolling-window definition ──────────────────────────────
// PAI is computed per WINDOW, not per stride, because stride segmentation
// needs IMU processing this app does not implement yet (see
// docs/BACKLOG.md item 1). A window is currently a fixed wall-clock
// duration — this is the one declaration site that encodes what "one
// window" means. Once stride segmentation lands, this is where that swap
// happens (wall-clock duration -> stride-boundary event); the PAI formula
// itself (computePai below) does not change either way.
const WINDOW_MS = 2000;
/** Bar columns shown on the chart, oldest to most recent; the last one is always the in-progress window. */
const WINDOW_COUNT = 8;

// ─── PAI math ────────────────────────────────────────────────

/** |L-R| / ((L+R)/2) x 100. Null when both sides read zero (undefined ratio), not 0. */
function computePai(peakL: number, peakR: number): number | null {
  const avg = (peakL + peakR) / 2;
  if (avg === 0) return null;
  return (Math.abs(peakL - peakR) / avg) * 100;
}

function peakOf(pressure: FootPressure): number {
  return Math.max(...Object.values(pressure));
}

// ─── Shared "unavailable" card, reused by every static section AND by the
// PAI section when data isn't there — one visual pattern for "nothing to
// show here," matching the nodata treatment already used on Home/Temperature
// (same "NO DATA"/muted-icon/em-dash vocabulary, see home.ts's ΔT tile and
// temperature.ts's dt-hero). The ICON is not shared, deliberately: `bluetooth`
// means "no data from the device" and is only accurate for PAI, whose
// unavailability really is a connectivity question. The other three sections
// use `construction` — absent-by-design (no classifier/CoP/trend source
// exists at all, regardless of connection state) — because `bluetooth` on
// those cards would tell anyone who reads the icon before the caption
// (most people) that connecting both insoles would fix it, which is false.
// ─────────────────────────────────────────────────────────────

function unavailableCardHTML(opts: {
  th: string; en: string; pill: string; bodyTH: string; bodyEN: string; icon: string;
}): string {
  return `
    <div class="head">
      <div>
        <div class="th">${opts.th}</div>
        <div class="en">${opts.en}</div>
      </div>
      <span class="pill">${opts.pill}</span>
    </div>
    <div class="section-empty">
      <div class="ic"><i data-lucide="${opts.icon}"></i></div>
      <div class="big">—</div>
      <div class="label-th">${opts.bodyTH}</div>
      <div class="label-en">${opts.bodyEN}</div>
    </div>
  `;
}

function renderStaticUnavailable(hostId: string, opts: Parameters<typeof unavailableCardHTML>[0]): void {
  const host = document.getElementById(hostId);
  if (!host) return;
  host.className = 'gait-card nodata';
  host.innerHTML = unavailableCardHTML(opts);
  refreshIcons();
}

// ─── Header ──────────────────────────────────────────────────

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  host.innerHTML = `
    <div class="title-block">
      <span class="eyebrow">analysis · วิเคราะห์การเดิน</span>
      <div class="title">การเดิน</div>
    </div>
    <a href="#/settings" class="gear-btn" aria-label="ตั้งค่า">
      <i data-lucide="settings"></i>
    </a>
  `;
}

// ─── Classification card — no classifier exists (out of scope, see
// docs/BACKLOG.md item 1) — static unavailable state, rendered once. ───

function renderClassification(): void {
  renderStaticUnavailable('classification', {
    th: 'การจำแนกรูปแบบการเดิน',
    en: 'Gait classification',
    pill: 'NOT AVAILABLE',
    bodyTH: 'ยังไม่มีระบบจำแนกรูปแบบการเดิน',
    bodyEN: 'No classifier built yet',
    icon: 'construction',
  });
}

// ─── PAI (peak asymmetry index) — the one real metric on this screen ──
//
// Rolling-window accumulation happens off the RAW per-sample stream
// (deviceManager.onRawSample, up to 50 Hz per side), not off the throttled
// 10 Hz onSnapshot. This split matters, not just for tidiness: a 2 s window
// at 50 Hz is 100 samples, and onSnapshot only ever delivers 20 of them
// (10 Hz x 2 s) — a "peak" taken from that would be the max of a set with
// 80% of the data thrown away, which under-reads exactly the kind of signal
// (plantar pressure rising and falling fast at heel strike) most likely to
// have its true peak fall in the discarded 80%. onRawSample exists
// specifically so this doesn't happen. onSnapshot is still used, but only to
// drive the RENDER (10 Hz is plenty for a human-readable chart) and to
// gate/reset accumulation when a foot's usability changes — measurement
// rate and render rate are different concerns, handled by two different
// subscriptions here.
//
// Per docs/BACKLOG.md item 1 / CLAUDE.md's safety rule: accumulation only
// happens while both feet are usable (checked via the `bothUsableNow` flag
// below, refreshed every onSnapshot tick — good enough at 10 Hz resolution
// for a 2 s window). The instant that flag flips false, all window state is
// discarded (not paused, not shown stale) and the section falls back to the
// same nodata pattern as every other unavailable section on this screen —
// a one-footed asymmetry figure is not a degraded reading, it's a
// meaningless one.

interface WindowAccum { peakL: number; peakR: number; hasSample: boolean; }
function freshAccum(): WindowAccum { return { peakL: 0, peakR: 0, hasSample: false }; }

let windowStart = 0;
let live: WindowAccum = freshAccum();
let history: { peakL: number; peakR: number }[] = [];
/** Refreshed once per onSnapshot tick (10 Hz); onRawSample reads this rather than re-deriving usability itself, since it fires far more often than that needs re-checking. */
let bothUsableNow = false;

// Build-once DOM refs for the live chart (Convention #3 in CLAUDE.md: the
// snapshot stream is 10 Hz, so this subtree is built once and mutated in
// place, never innerHTML-rebuilt on a tick — an innerHTML rebuild at that
// rate would restart the bars' CSS height transition every 100 ms).
let symmetryLiveBuilt = false;
let pillEl: HTMLElement | null = null;
let paiNumEl: HTMLElement | null = null;
let subThEl: HTMLElement | null = null;
let barEls: { l: HTMLElement; r: HTMLElement; label: HTMLElement }[] = [];

function buildSymmetryLiveDom(host: HTMLElement): void {
  host.className = 'gait-card';
  host.innerHTML = `
    <div class="head">
      <div>
        <div class="th">ดัชนีความไม่สมมาตรของแรงกด</div>
        <div class="en">Peak Asymmetry Index (PAI) · ${WINDOW_MS / 1000}s rolling window</div>
      </div>
      <span class="pill">—</span>
    </div>
    <div class="pai-row">
      <div class="pai-big"><span class="pai-num">—</span><span class="unit">%</span></div>
      <div class="pai-sub">
        <div class="label-th"></div>
        <div class="label-en">watch threshold ${PAI_WATCH_PCT}%</div>
      </div>
    </div>
    <div class="symmetry-grid"></div>
    <div class="legend-row">
      <div class="key"><span class="swatch l"></span>เท้าซ้าย · L</div>
      <div class="key"><span class="swatch r"></span>เท้าขวา · R</div>
    </div>
  `;
  pillEl = host.querySelector('.head .pill');
  paiNumEl = host.querySelector('.pai-num');
  subThEl = host.querySelector('.pai-sub .label-th');

  const barsHost = host.querySelector('.symmetry-grid')!;
  barEls = [];
  for (let i = 0; i < WINDOW_COUNT; i++) {
    const step = document.createElement('div');
    step.className = 'step';
    const bars = document.createElement('div');
    bars.className = 'bars';
    const barL = document.createElement('div'); barL.className = 'bar l';
    const barR = document.createElement('div'); barR.className = 'bar r';
    bars.append(barL, barR);
    const label = document.createElement('div');
    label.className = 'step-label';
    step.append(bars, label);
    barsHost.appendChild(step);
    barEls.push({ l: barL, r: barR, label });
  }
  symmetryLiveBuilt = true;
}

function renderSymmetryUnavailable(): void {
  renderStaticUnavailable('symmetry', {
    th: 'ดัชนีความไม่สมมาตรของแรงกด',
    en: 'Peak Asymmetry Index (PAI)',
    pill: 'NO DATA',
    bodyTH: 'ต้องมีข้อมูลทั้งสองข้าง',
    bodyEN: 'needs both feet',
    icon: 'bluetooth',
  });
  symmetryLiveBuilt = false;
  pillEl = paiNumEl = subThEl = null;
  barEls = [];
}

function updateSymmetryLive(): void {
  if (!symmetryLiveBuilt) return;

  // Carry the last completed window's peaks forward for the instant right
  // after a window rolls over and the new one has no sample yet, so the
  // headline doesn't flash to "no data" every WINDOW_MS.
  const last = history[history.length - 1];
  const peakL = live.hasSample ? live.peakL : (last?.peakL ?? 0);
  const peakR = live.hasSample ? live.peakR : (last?.peakR ?? 0);
  const pai = computePai(peakL, peakR);
  const watch = pai !== null && pai > PAI_WATCH_PCT;

  if (pillEl) {
    const txt = pai === null ? '—' : (watch ? 'WATCH' : 'OK');
    if (pillEl.textContent !== txt) pillEl.textContent = txt;
    const cls = 'pill' + (watch ? ' watch' : '');
    if (pillEl.className !== cls) pillEl.className = cls;
  }
  if (paiNumEl) {
    const txt = pai === null ? '—' : pai.toFixed(1);
    if (paiNumEl.textContent !== txt) paiNumEl.textContent = txt;
  }
  if (subThEl) {
    const txt = pai === null ? '' :
      watch ? `เกินเกณฑ์เฝ้าระวัง ${PAI_WATCH_PCT}%` : `ต่ำกว่าเกณฑ์เฝ้าระวัง ${PAI_WATCH_PCT}%`;
    if (subThEl.textContent !== txt) subThEl.textContent = txt;
  }

  // WINDOW_COUNT columns: completed windows, left-padded with empty
  // placeholders until there's enough history, then the live window last.
  const padded = [...history];
  while (padded.length < WINDOW_COUNT - 1) padded.unshift({ peakL: 0, peakR: 0 });
  const cols = [...padded.slice(-(WINDOW_COUNT - 1)), { peakL, peakR }];

  const max = PRESSURE_SCALE_MAX_KPA;
  cols.forEach((c, i) => {
    const el = barEls[i];
    if (!el) return;
    const hL = `${Math.min(100, (c.peakL / max) * 100)}%`;
    const hR = `${Math.min(100, (c.peakR / max) * 100)}%`;
    if (el.l.style.height !== hL) el.l.style.height = hL;
    if (el.r.style.height !== hR) el.r.style.height = hR;
    const secondsAgo = (cols.length - 1 - i) * (WINDOW_MS / 1000);
    const labelTxt = secondsAgo === 0 ? 'now' : `-${secondsAgo}s`;
    if (el.label.textContent !== labelTxt) el.label.textContent = labelTxt;
  });
}

// ─── CoP trajectory — no CoP computation exists yet — static unavailable
// state, rendered once. The old decorative SVG trace is deleted outright,
// not replaced with a different fake path. ─────────────────────

function renderCoP(): void {
  renderStaticUnavailable('cop', {
    th: 'ทางเดินจุดศูนย์ถ่วงแรงกด',
    en: 'Center of Pressure trajectory',
    pill: 'NOT AVAILABLE',
    bodyTH: 'ยังไม่มีการคำนวณจุดศูนย์ถ่วงแรงกด',
    bodyEN: 'Not computed yet',
    icon: 'construction',
  });
}

// ─── 7-day trend — no symmetry-score history source exists yet — static
// unavailable state, rendered once. ─────────────────────────────

function renderTrend(): void {
  renderStaticUnavailable('trend', {
    th: 'แนวโน้ม 7 วัน',
    en: '7-day trend',
    pill: 'NOT AVAILABLE',
    bodyTH: 'ยังไม่มีข้อมูลแนวโน้มความสมมาตร',
    bodyEN: 'No trend data yet',
    icon: 'construction',
  });
}

// ─── Lifecycle ───────────────────────────────────────────────

let unsubs: Unsubscribe[] = [];

/**
 * Runs on every raw sample (up to 50 Hz per side) — accumulation only, no
 * DOM work. See the PAI section comment above for why this is the raw
 * subscription and not onSnapshot.
 */
function handleRawSample(s: RawPressureSample): void {
  if (!bothUsableNow) return;   // gated by the flag applySnapshot maintains

  const peak = peakOf(s.pressure);
  if (s.side === 'left') live.peakL = Math.max(live.peakL, peak);
  else live.peakR = Math.max(live.peakR, peak);
  live.hasSample = true;

  if (windowStart === 0) windowStart = s.tUnixMs;
  if (s.tUnixMs - windowStart >= WINDOW_MS) {
    history.push({ peakL: live.peakL, peakR: live.peakR });
    if (history.length > WINDOW_COUNT - 1) history.shift();
    live = freshAccum();
    windowStart = s.tUnixMs;
  }
}

/** Runs at 10 Hz (onSnapshot) — usability gating/reset and the actual render. */
function applySnapshot(snap: CombinedSnapshot): void {
  const left = snap.left;
  const right = snap.right;
  const wasUsable = bothUsableNow;
  bothUsableNow = isUsable(left) && isUsable(right) && !!left.pressure && !!right.pressure;

  if (!bothUsableNow) {
    // Discard any in-progress/completed window state rather than let it sit
    // stale and get shown once a foot reconnects — a fresh window on
    // reconnect is correct; resuming a window that was interrupted mid-way
    // is not.
    if (wasUsable || history.length > 0 || live.hasSample || symmetryLiveBuilt) {
      history = [];
      live = freshAccum();
      windowStart = 0;
    }
    renderSymmetryUnavailable();
    return;
  }

  if (!symmetryLiveBuilt) {
    const host = document.getElementById('symmetry');
    if (host) buildSymmetryLiveDom(host);
  }
  updateSymmetryLive();
}

export function mount(): void {
  renderStatusBar();
  renderHeader();
  renderClassification();
  renderCoP();
  renderTrend();

  // Reset window state on every mount so a re-visit starts a fresh window
  // rather than resuming one left over from before this screen was last
  // unmounted.
  windowStart = 0;
  live = freshAccum();
  history = [];
  bothUsableNow = false;
  symmetryLiveBuilt = false;
  renderSymmetryUnavailable();

  // Two subscriptions, two different rates and jobs (see the PAI section
  // comment): raw for accumulation, snapshot for gating + render. Both are
  // unsubscribed in unmount() per CLAUDE.md Convention #2.
  unsubs.push(deviceManager.onRawSample(handleRawSample));
  unsubs.push(deviceManager.onSnapshot(applySnapshot));
  initNavigation();
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  pillEl = paiNumEl = subThEl = null;
  barEls = [];
  symmetryLiveBuilt = false;
  // Everything else this screen renders lives inside #view and is discarded
  // when the router clears it.
}

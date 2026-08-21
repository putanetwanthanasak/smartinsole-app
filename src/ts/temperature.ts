// temperature.ts — Temperature monitoring screen, wired to the data seam.
//
// Re-render strategy: every live section writes its markup through
// writeIfChanged, so at 10 Hz nothing touches the DOM unless the markup actually
// differs. Temperature readings arrive at 1 Hz and are displayed to one decimal,
// so in practice these sections rebuild about once a second and are idle in
// between. None of them contains an event listener or a CSS animation, which is
// why string replacement is adequate here and the heatmap needed node-level
// mutation instead.

import { TEMP_DELTA_THRESHOLD } from './constants.js';
import { tempColor } from './pressureColor.js';
import { initNavigation, renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import { deviceManager } from './data/DeviceManager.js';
import { alertStore, formatAlertTime } from './data/AlertStore.js';
import { isUsable } from './data/types.js';
import type {
  CombinedSnapshot, SideSnapshot, TempHistoryPoint, Unsubscribe,
} from './data/types.js';
import type { AlertEntry, FootSide } from './types.js';

let lastHTML: Record<string, string> = {};

function writeIfChanged(host: HTMLElement, key: string, html: string): boolean {
  if (lastHTML[key] === html) return false;
  lastHTML[key] = html;
  host.innerHTML = html;
  return true;
}

// ─── Header (static) ─────────────────────────────────────────

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  host.innerHTML = `
    <div class="title-block">
      <span class="eyebrow">temperature · อุณหภูมิเท้า</span>
      <div class="title">อุณหภูมิ</div>
    </div>
    <a href="#/settings" class="gear-btn" aria-label="ตั้งค่า">
      <i data-lucide="settings"></i>
    </a>
  `;
}

// ─── ΔT hero ─────────────────────────────────────────────────

function fmt(s: SideSnapshot | null): string {
  if (!isUsable(s) || s.temp?.forefootC == null) return '—';
  return `${s.temp.forefootC.toFixed(1)}°C`;
}

function renderDTHero(snap: CombinedSnapshot): void {
  const host = document.getElementById('dt-hero');
  if (!host) return;
  const dT = snap.deltaForefootC;

  // Exactly the rule Home uses, from the same field, so the two screens cannot
  // disagree: null unless BOTH sides are usable and both report a forefoot value.
  if (dT === null) {
    host.className = 'dt-hero nodata';
    writeIfChanged(host, 'hero', `
      <div class="head">
        <div>
          <div class="th">ผลต่างอุณหภูมิเท้าหน้า</div>
          <div class="en">Forefoot ΔT · needs both feet</div>
        </div>
        <span class="pill">NO DATA</span>
      </div>
      <div class="dt-meter-wrap">
        <div class="dt-meter is-empty"></div>
      </div>
      <div class="dt-row">
        <div>
          <div class="big">—</div>
          <div class="label-th">ยังไม่สามารถคำนวณผลต่างได้</div>
          <div class="label-en">Both insoles required</div>
        </div>
        <div class="pair">
          <div class="v"><span class="l">L</span> · ${fmt(snap.left)}</div>
          <div class="v" style="margin-top:6px"><span class="r">R</span> · ${fmt(snap.right)}</div>
        </div>
      </div>
    `);
    return;
  }

  const pct = Math.min(100, (dT / 4) * 100);
  const thresholdPct = (TEMP_DELTA_THRESHOLD / 4) * 100;
  const over = dT > TEMP_DELTA_THRESHOLD;
  host.className = 'dt-hero';
  writeIfChanged(host, 'hero', `
    <div class="head">
      <div>
        <div class="th">ผลต่างอุณหภูมิเท้าหน้า</div>
        <div class="en">Forefoot ΔT · clinical alert at ${TEMP_DELTA_THRESHOLD}°C</div>
      </div>
      <span class="pill">${over ? 'ALERT' : 'OK'}</span>
    </div>
    <div class="dt-meter-wrap">
      <div class="dt-meter">
        <div class="threshold-label" style="left:${thresholdPct}%">${TEMP_DELTA_THRESHOLD}°C</div>
        <div class="threshold" style="left:${thresholdPct}%"></div>
        <div class="needle" style="left:${pct}%"></div>
      </div>
    </div>
    <div class="dt-row">
      <div>
        <div class="big">${dT.toFixed(1)}°<span style="font-size:24px">C</span></div>
        <div class="label-th">${over ? `เกินเกณฑ์ ${(dT - TEMP_DELTA_THRESHOLD).toFixed(1)}°C` : 'อยู่ในเกณฑ์ปกติ'}</div>
        <div class="label-en">${over ? 'Above clinical threshold' : 'Within normal range'}</div>
      </div>
      <div class="pair">
        <div class="v"><span class="l">L</span> · ${fmt(snap.left)}</div>
        <div class="v" style="margin-top:6px"><span class="r">R</span> · ${fmt(snap.right)}</div>
      </div>
    </div>
  `);
}

// ─── Bilateral foot map ──────────────────────────────────────

const FOOT_BODY = `M 50 18
  C 70 22 80 38 82 64
  C 84 90 78 130 76 158
  C 74 184 68 214 60 232
  C 54 248 38 252 30 240
  C 22 228 18 198 20 168
  C 22 138 24 100 28 70
  C 32 40 38 22 50 18 Z`;
const TOES = [
  { cx: 47, cy: 14, rx: 6.5, ry: 7 },
  { cx: 60, cy: 24, rx: 5,   ry: 5.5 },
  { cx: 70, cy: 36, rx: 4.5, ry: 5 },
  { cx: 78, cy: 48, rx: 4,   ry: 4.5 },
  { cx: 84, cy: 60, rx: 3.6, ry: 4 },
];
/** Same neutral grey the heatmap uses for an absent foot. */
const UNAVAILABLE_FILL = '#CFC9BC';

function renderTempFeet(snap: CombinedSnapshot): void {
  const host = document.getElementById('temp-feet');
  if (!host) return;

  const dots = (s: SideSnapshot | null) => {
    const ok = isUsable(s);
    const fore = ok ? s!.temp?.forefootC ?? null : null;
    const heel = ok ? s!.temp?.heelC ?? null : null;
    const cell = (cx: number, cy: number, rx: number, ry: number, v: number | null) => `
      <ellipse class="temp-dot" cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${v === null ? UNAVAILABLE_FILL : tempColor(v)}" />
      <text class="temp-val" x="${cx}" y="${cy + 3}" text-anchor="middle">${v === null ? '–' : `${v.toFixed(1)}°`}</text>`;
    return cell(50, 80, 22, 14, fore) + cell(40, 218, 20, 13, heel);
  };

  const foot = (side: FootSide, th: string, en: string) => {
    const s = side === 'left' ? snap.left : snap.right;
    const unavailable = !isUsable(s);
    return `
      <div class="cell${unavailable ? ' unavailable' : ''}">
        <svg viewBox="0 0 100 270">
          <g ${side === 'right' ? 'transform="translate(100,0) scale(-1,1)"' : ''}>
            <path class="foot-shape" d="${FOOT_BODY.trim()}" />
            ${TOES.map(t => `<ellipse class="toe-shape" cx="${t.cx}" cy="${t.cy}" rx="${t.rx}" ry="${t.ry}" />`).join('')}
          </g>
          <g>${dots(s)}</g>
        </svg>
        ${unavailable ? '<div class="na-note"><span class="th">ไม่มีข้อมูล</span><span class="en">No data</span></div>' : ''}
        <div class="side-label">${th} <span class="en">· ${en}</span></div>
      </div>`;
  };

  writeIfChanged(host, 'feet', `
    <div class="head">
      <div>
        <div class="th">แผนที่อุณหภูมิ</div>
        <div class="en">Bilateral skin temperature</div>
      </div>
    </div>
    <div class="temp-feet">
      ${foot('left', 'ซ้าย', 'L')}
      ${foot('right', 'ขวา', 'R')}
    </div>
    <div class="temp-legend">
      <div class="bar"></div>
      <div class="scale"><span>เย็น · 28°</span><span>ร้อน · 33°</span></div>
    </div>
  `);
}

// ─── 24 h trend ──────────────────────────────────────────────

const SPAN_MS = 24 * 60 * 60 * 1000;
const BUCKET_MS = 10 * 60 * 1000;

/**
 * Build path segments, breaking wherever data is absent.
 *
 * A missing bucket or a null channel produces a GAP: the line stops and restarts
 * on the far side. Drawing straight through would invent readings for a period
 * when the insole was off the foot, which on a trend chart is indistinguishable
 * from a real measurement.
 */
function segments(points: TempHistoryPoint[], t0: number, w: number, h: number,
                  min: number, max: number): string[] {
  const x = (t: number) => ((t - t0) / SPAN_MS) * w;
  const y = (v: number) => h - ((v - min) / (max - min)) * h;
  const out: string[] = [];
  let cur: string[] = [];
  let prevT: number | null = null;
  for (const p of points) {
    const v = p.forefootC;
    const gap = prevT !== null && p.tUnixMs - prevT > BUCKET_MS * 1.5;
    if (v === null || gap) {
      if (cur.length > 1) out.push(cur.join(' '));
      cur = [];
      if (v === null) { prevT = p.tUnixMs; continue; }
    }
    cur.push(`${cur.length === 0 ? 'M' : 'L'} ${x(p.tUnixMs).toFixed(1)} ${y(v).toFixed(1)}`);
    prevT = p.tUnixMs;
  }
  if (cur.length > 1) out.push(cur.join(' '));
  return out;
}

function renderTrend(): void {
  const host = document.getElementById('temp-trend');
  if (!host) return;
  const hist = deviceManager.getTempHistory();
  const w = 320, h = 130, min = 28, max = 33;
  const now = Date.now();
  const t0 = now - SPAN_MS;

  const grid = [28, 30, 32].map(v => {
    const y = h - ((v - min) / (max - min)) * h;
    return `<line x1="0" y1="${y}" x2="${w}" y2="${y}" />
      <text class="chart-axis" x="-4" y="${y + 3}" text-anchor="end">${v}°</text>`;
  }).join('');

  const paths = (pts: TempHistoryPoint[], cls: string) =>
    segments(pts, t0, w, h, min, max).map(d => `<path class="${cls}" d="${d}" />`).join('');

  // hour ticks every 4 h
  const ticks: string[] = [];
  const firstTick = Math.ceil(t0 / (4 * 3600000)) * 4 * 3600000;
  for (let t = firstTick; t <= now; t += 4 * 3600000) {
    const d = new Date(t);
    const label = `${String(d.getHours()).padStart(2, '0')}:00`;
    ticks.push(`<text class="chart-axis" x="${(((t - t0) / SPAN_MS) * w).toFixed(1)}" y="${h + 14}" text-anchor="middle">${label}</text>`);
  }

  const empty = hist.left.length === 0 && hist.right.length === 0;

  writeIfChanged(host, 'trend', `
    <div class="head">
      <div>
        <div class="th">แนวโน้ม 24 ชั่วโมง</div>
        <div class="en">24-hour temperature trend · forefoot</div>
      </div>
    </div>
    <div class="chart-wrap">
      ${empty ? `<div class="chart-empty">ยังไม่มีประวัติ<span>No history yet</span></div>` : `
      <svg viewBox="-20 -8 ${w + 24} ${h + 24}" preserveAspectRatio="none">
        <g class="chart-grid">${grid}</g>
        ${paths(hist.left, 'line-l')}
        ${paths(hist.right, 'line-r')}
        ${ticks.join('')}
      </svg>`}
    </div>
    <div class="legend-line">
      <div class="key"><span class="line" style="background:var(--brand-primary)"></span>เท้าซ้าย · L forefoot</div>
      <div class="key"><span class="line" style="background:var(--brand-accent)"></span>เท้าขวา · R forefoot</div>
    </div>
  `);
}

// ─── Temperature alert history ───────────────────────────────

function renderAlertHistory(alerts: AlertEntry[]): void {
  const host = document.getElementById('alert-history');
  if (!host) return;
  // Real temperature alerts only. The two synthetic entries that used to be
  // appended here "to make the screen feel realistic" are gone — they were
  // indistinguishable from real ones on screen, which is the whole problem.
  const temps = alerts.filter(a => a.type === 'temperature').slice(0, 6);

  writeIfChanged(host, 'alerts', `
    <div class="head">
      <div>
        <div class="th">ประวัติการแจ้งเตือน</div>
        <div class="en">Temperature alerts · recent</div>
      </div>
    </div>
    ${temps.length === 0 ? `<div class="alert-empty">ยังไม่มีการแจ้งเตือนอุณหภูมิ<span>No temperature alerts yet</span></div>` : ''}
    ${temps.map(a => `
      <div class="alert-row">
        <div class="dot ${a.severity === 'danger' ? 'danger' : 'warn'}"></div>
        <div class="body">
          <div class="msg">${a.message}</div>
          <div class="time">${formatAlertTime(a.tUnixMs)}</div>
        </div>
        ${a.acknowledged ? '<i data-lucide="check" class="ic-xs" style="color:var(--text-tertiary)"></i>' : '<span class="pill">NEW</span>'}
      </div>
    `).join('')}
  `) && refreshIcons();
}

// ─── Lifecycle ───────────────────────────────────────────────

let unsubs: Unsubscribe[] = [];

export function mount(): void {
  lastHTML = {};
  renderStatusBar();
  renderHeader();

  unsubs.push(deviceManager.onSnapshot(snap => {
    renderDTHero(snap);
    renderTempFeet(snap);
    renderTrend();
  }));
  unsubs.push(alertStore.subscribe(renderAlertHistory));

  initNavigation({ alertCount: alertStore.unacknowledgedCount() });
  refreshIcons();
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  lastHTML = {};
}

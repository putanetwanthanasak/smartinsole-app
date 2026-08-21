// home.ts — Home/dashboard. The first screen wired to the data seam.
//
// Everything on this screen now derives from DeviceManager's throttled snapshot
// rather than from MOCK_DATA, except the "today" tiles (steps / minutes /
// symmetry), which are not sensor data and have no source yet.
//
// Re-render discipline: the snapshot arrives at 10 Hz, so each block writes its
// innerHTML only when the markup it would produce actually changed. Without
// that, every tick would rebuild the connection strip and status badge, throw
// away and re-create their icons, and restart the badge's pulse animation.

import { MOCK_DATA } from './mockData.js';
import {
  STATUS_META, TEMP_DELTA_THRESHOLD, PRESET_LABELS,
  PRESSURE_WATCH_KPA, PRESSURE_ALERT_KPA,
} from './constants.js';
import { Heatmap } from './heatmap.js';
import { initNavigation, renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import type { RiskStatus, FootSide, PresetName } from './types.js';
import { deviceManager, mockSources } from './data/DeviceManager.js';
import { alertStore } from './data/AlertStore.js';
import { isUsable } from './data/types.js';
import type {
  CombinedSnapshot, SideSnapshot, ConnectionState, Unsubscribe,
} from './data/types.js';

// ─── Derived status ──────────────────────────────────────────

/**
 * Same ladder as before, now driven by values rather than by which preset is
 * selected: normal walking peaks below the watch tier, and anything reaching the
 * alert tier escalates to 3. Status 0 is the "no usable data" state — it was
 * unreachable while the UI read a static snapshot, and is reachable now.
 */
function statusFromSnapshot(snap: CombinedSnapshot): RiskStatus {
  const usable = [snap.left, snap.right].filter(isUsable);
  const all: number[] = [];
  for (const s of usable) if (s.pressure) all.push(...Object.values(s.pressure));
  if (all.length === 0) return 0;
  const mx = Math.max(...all);
  if (mx >= PRESSURE_ALERT_KPA) return 3;
  if (mx >= PRESSURE_WATCH_KPA) return 2;
  return 1;
}

// ─── Write-if-changed ────────────────────────────────────────

let lastHTML: Record<string, string> = {};

function writeIfChanged(host: HTMLElement, key: string, html: string): boolean {
  if (lastHTML[key] === html) return false;
  lastHTML[key] = html;
  host.innerHTML = html;
  return true;
}

// ─── Connection strip ────────────────────────────────────────

const STATE_TH: Record<ConnectionState, string> = {
  connected: 'เชื่อมต่อแล้ว',
  connecting: 'กำลังเชื่อมต่อ',
  stale: 'สัญญาณขาดช่วง',
  error: 'ผิดพลาด',
  disconnected: 'ไม่ได้เชื่อมต่อ',
};
const STATE_EN: Record<ConnectionState, string> = {
  connected: 'connected',
  connecting: 'connecting',
  stale: 'signal stale',
  error: 'error',
  disconnected: 'offline',
};
/** Compact per-side token; the full wording lives in the strip's main label. */
const STATE_SHORT: Record<ConnectionState, string> = {
  connected: '',
  connecting: 'กำลังต่อ',
  stale: 'ค้าง',
  error: 'ผิดพลาด',
  disconnected: 'ไม่ต่อ',
};

function sideTone(state: ConnectionState): string {
  if (state === 'connected') return 'ok';
  if (state === 'error') return 'err';
  if (state === 'stale') return 'warn';
  return 'off';
}

function renderConnectionStrip(snap: CombinedSnapshot): void {
  const host = document.getElementById('connection-strip');
  if (!host) return;

  const states: Record<FootSide, ConnectionState> = {
    left: snap.left?.state ?? 'disconnected',
    right: snap.right?.state ?? 'disconnected',
  };
  const connectedCount = (['left', 'right'] as FootSide[])
    .filter(s => states[s] === 'connected').length;

  // Overall wording: only claim "connected" when BOTH sides are.
  let th: string;
  let en: string;
  if (connectedCount === 2) { th = STATE_TH.connected; en = 'both insoles'; }
  else if (connectedCount === 1) { th = 'เชื่อมต่อบางส่วน'; en = 'one insole only'; }
  else if (states.left === 'connecting' || states.right === 'connecting') { th = STATE_TH.connecting; en = STATE_EN.connecting; }
  else if (states.left === 'error' || states.right === 'error') { th = STATE_TH.error; en = STATE_EN.error; }
  else { th = STATE_TH.disconnected; en = STATE_EN.disconnected; }

  const icon = connectedCount > 0 ? 'bluetooth-connected' : 'bluetooth';

  const cell = (side: FootSide, letter: string) => {
    const st = states[side];
    const snapSide = side === 'left' ? snap.left : snap.right;
    const battery = snapSide?.status?.batteryPct;
    // Battery only for a connected side: on a stale or dropped link the number
    // is not current, and a stale battery reading is a lie.
    const value = st === 'connected' && battery !== undefined
      ? `${battery}%`
      : STATE_SHORT[st];
    const cls = st === 'connected' ? 'val num' : 'val state';
    return `<div class="battery tone-${sideTone(st)}" title="${STATE_TH[st]} · ${STATE_EN[st]}">
        <span class="side">${letter}</span><span class="${cls}">${value}</span>
      </div>`;
  };

  const html = `
    <div class="icon-wrap tone-${connectedCount > 0 ? 'ok' : 'off'}"><i data-lucide="${icon}"></i></div>
    <div class="label">
      <strong>${th}</strong>
      <span class="sub">${en}</span>
    </div>
    <div class="batteries">
      ${cell('left', 'L')}
      ${cell('right', 'R')}
    </div>
  `;
  if (writeIfChanged(host, 'strip', html)) refreshIcons();
}

// ─── Status badge + alert banner ─────────────────────────────

function renderStatusBadge(status: RiskStatus): void {
  const host = document.getElementById('status-badge');
  if (!host) return;
  const meta = STATUS_META[status];
  const tone = meta.tone;                       // 'neutral' is now reachable
  const iconName =
    tone === 'neutral' ? 'bluetooth' :
    tone === 'safe' ? 'shield' :
    tone === 'danger' ? 'alert-triangle' : 'activity';
  const ringClass = tone === 'safe' || tone === 'neutral' ? '' : 'live-dot';
  const html = `
    <div class="badge-icon">
      <div class="ring ${ringClass}"></div>
      <div class="core"><i data-lucide="${iconName}"></i></div>
    </div>
    <div class="meta">
      <div class="eyebrow tone-${tone}">STATUS · ${status}/5</div>
      <div class="th">${meta.th}</div>
      <div class="en">${meta.en}</div>
    </div>
  `;
  const cls = `status-badge tone-${tone}`;
  if (host.className !== cls) host.className = cls;
  if (writeIfChanged(host, 'badge', html)) refreshIcons();
}

function renderAlertBanner(status: RiskStatus): void {
  const host = document.getElementById('alert-banner');
  if (!host) return;
  if (status < 3) {
    if (host.style.display !== 'none') host.style.display = 'none';
    writeIfChanged(host, 'banner', '');
    return;
  }
  host.style.display = '';
  const tone = status >= 4 ? 'danger' : 'warn';
  const adviceTH = status >= 4 ? 'พักเท้าและติดต่อแพทย์'      : 'พักเท้าสักครู่';
  const adviceEN = status >= 4 ? 'Rest and call your doctor' : 'Rest your feet for a moment';
  const cls = `alert-banner tone-${tone}`;
  if (host.className !== cls) host.className = cls;
  const html = `
    <div class="ic"><i data-lucide="alert-triangle"></i></div>
    <div class="copy">
      <div class="th">${adviceTH}</div>
      <div class="en">${adviceEN}</div>
    </div>
    <i data-lucide="chevron-right"></i>
  `;
  if (writeIfChanged(host, 'banner', html)) refreshIcons();
}

// ─── ΔT tile ─────────────────────────────────────────────────

function renderTempCompact(snap: CombinedSnapshot): void {
  const host = document.getElementById('temp-compact');
  if (!host) return;

  const dT = snap.deltaForefootC;
  let cls: string;
  let html: string;

  if (dT === null) {
    // Safety property, not polish: a ΔT computed from one foot, or from a stale
    // reading, is a fabricated clinical number. Show nothing rather than that.
    cls = 'temp-compact card nodata';
    html = `
      <div class="row">
        <div class="ic"><i data-lucide="thermometer"></i></div>
        <div style="flex:1">
          <div class="label-th">ผลต่างอุณหภูมิ</div>
          <div class="label-en">ΔT forefoot · ต้องมีข้อมูลทั้งสองข้าง · needs both feet</div>
        </div>
        <div style="text-align:right">
          <div class="delta">—</div>
          <div class="delta-sub">L ${fmtTemp(snap.left)} · R ${fmtTemp(snap.right)}</div>
        </div>
      </div>
    `;
  } else {
    const alert = dT > TEMP_DELTA_THRESHOLD;
    cls = `temp-compact card ${alert ? 'alert' : 'safe'}`;
    html = `
      <div class="row">
        <div class="ic"><i data-lucide="thermometer"></i></div>
        <div style="flex:1">
          <div class="label-th">ผลต่างอุณหภูมิ</div>
          <div class="label-en">ΔT forefoot · threshold ${TEMP_DELTA_THRESHOLD}°C</div>
        </div>
        <div style="text-align:right">
          <div class="delta">${dT.toFixed(1)}°</div>
          <div class="delta-sub">L ${fmtTemp(snap.left)} · R ${fmtTemp(snap.right)}</div>
        </div>
      </div>
    `;
  }

  if (host.className !== cls) host.className = cls;
  if (writeIfChanged(host, 'temp', html)) refreshIcons();
  host.onclick = () => { window.location.hash = '#/temp'; };
}

function fmtTemp(s: SideSnapshot | null): string {
  if (!isUsable(s) || s.temp?.forefootC == null) return '—';
  return s.temp.forefootC.toFixed(1);
}

// ─── Static blocks ───────────────────────────────────────────

function renderTodaySummary(): void {
  const host = document.getElementById('today-summary');
  if (!host) return;
  const t = MOCK_DATA.todaySummary;
  host.innerHTML = `
    <div class="section-label">
      <div>
        <div class="l-th">สรุปวันนี้</div>
        <div class="l-en">Today's activity</div>
      </div>
      <span style="font-size:11px;color:var(--text-tertiary);font-family:var(--font-en);display:flex;align-items:center;gap:4px">
        <i data-lucide="calendar" class="ic-xs"></i> 11 พ.ค.
      </span>
    </div>
    <div class="summary-grid">
      <div class="card tile brand">
        <div class="ic ic-sm"><i data-lucide="footprints"></i></div>
        <div class="val">${t.steps.toLocaleString()}<span class="unit">ก้าว</span></div>
        <div class="label">steps</div>
      </div>
      <div class="card tile muted">
        <div class="ic ic-sm"><i data-lucide="clock"></i></div>
        <div class="val">${t.walkingMinutes}<span class="unit">นาที</span></div>
        <div class="label">walking</div>
      </div>
      <div class="card tile warn">
        <div class="ic ic-sm"><i data-lucide="activity"></i></div>
        <div class="val">${t.gaitSymmetryScore}<span class="unit">/100</span></div>
        <div class="label">symmetry</div>
      </div>
    </div>
  `;
}

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  host.innerHTML = `
    <div class="title-block">
      <span class="eyebrow">today · ดูแลเท้าวันนี้</span>
      <div class="title">สวัสดี คุณสมชาย</div>
    </div>
    <a href="#/settings" class="gear-btn" aria-label="ตั้งค่า">
      <i data-lucide="settings"></i>
    </a>
  `;
}

// ─── Mock-source controls ────────────────────────────────────
// These buttons used to live inside Heatmap and mutate its private preset.
// They are a control for the MOCK sources, so they now talk to those directly,
// and Heatmap knows nothing about them beyond where to put the element.

function buildPresetControls(): HTMLElement {
  const sec = document.createElement('div');
  sec.className = 'preset-section';

  const label = document.createElement('div');
  label.className = 'preset-label';
  label.innerHTML = `<i data-lucide="refresh-ccw" class="ic-xs"></i><span>จำลองสถานการณ์ · simulate</span>`;
  sec.appendChild(label);

  const grid = document.createElement('div');
  grid.className = 'preset-grid';
  let active: PresetName = mockSources.left.getPreset();

  for (const p of PRESET_LABELS) {
    const btn = document.createElement('button');
    btn.className = 'preset-btn' + (p.id === active ? ' active' : '');
    btn.innerHTML = `<div class="th">${p.th}</div><div class="en">${p.en}</div>`;
    btn.addEventListener('click', () => {
      if (active === p.id) return;
      active = p.id;
      mockSources.left.setPreset(p.id);
      mockSources.right.setPreset(p.id);
      grid.querySelectorAll('.preset-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
    grid.appendChild(btn);
  }
  sec.appendChild(grid);
  return sec;
}

// ─── Lifecycle ───────────────────────────────────────────────

let heatmap: Heatmap | null = null;
let unsubs: Unsubscribe[] = [];

function applySnapshot(snap: CombinedSnapshot): void {
  heatmap?.setPressure({
    left: isUsable(snap.left) ? snap.left.pressure : null,
    right: isUsable(snap.right) ? snap.right.pressure : null,
  });
  const status = statusFromSnapshot(snap);
  renderAlertBanner(status);
  renderStatusBadge(status);
  renderConnectionStrip(snap);
  renderTempCompact(snap);
}

export function mount(): void {
  lastHTML = {};
  renderStatusBar();
  renderHeader();

  const heatmapHost = document.getElementById('heatmap-host')!;
  heatmap = new Heatmap({
    container: heatmapHost,
    pressure: { left: null, right: null },
    controls: buildPresetControls(),
  });

  // One subscription; its unsubscribe is the only thing keeping this screen's
  // closures alive, and unmount() drops it.
  unsubs.push(deviceManager.onSnapshot(applySnapshot));

  renderTodaySummary();
  initNavigation({ alertCount: alertStore.unacknowledgedCount() });
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  heatmap?.destroy();
  heatmap = null;
  lastHTML = {};
  // Everything else this screen renders lives inside #view and is discarded
  // when the router clears it.
}

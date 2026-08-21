// gait.ts — Gait Analysis screen

import { MOCK_DATA } from './mockData.js';
import { initNavigation, renderStatusBar } from './navigation.js';
import { PRESSURE_SCALE_MAX_KPA } from './constants.js';

interface StridePair { l: number; r: number; }

// Peak pressure per stride, in kPa. Converted from the old 0-100 index at x2.5,
// the same factor that maps the old max of 100 onto PRESSURE_SCALE_MAX_KPA - so
// every bar keeps the height it had, and the "PEAK kPa" pill on this card is now
// telling the truth instead of labelling index values as kPa.
const STRIDES: StridePair[] = [
  { l: 195, r: 180 },
  { l: 205, r: 175 },
  { l: 200, r: 185 },
  { l: 212, r: 170 },
  { l: 198, r: 188 },
  { l: 210, r: 178 },
  { l: 202, r: 182 },
  { l: 208, r: 172 },
];

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

function renderClassification(): void {
  const host = document.getElementById('classification');
  if (!host) return;
  host.className = 'gait-classify tone-warn';
  host.innerHTML = `
    <div class="ic"><i data-lucide="footprints"></i></div>
    <div style="flex:1">
      <div class="text-th">ความไม่สมมาตรเล็กน้อย</div>
      <div class="text-en">Minor asymmetry · status 2/5</div>
    </div>
    <div>
      <div class="conf">87%</div>
      <div class="conf-sub">confidence</div>
    </div>
  `;
}

function renderSymmetry(): void {
  const host = document.getElementById('symmetry');
  if (!host) return;
  const max = PRESSURE_SCALE_MAX_KPA;
  const bars = STRIDES.map((s, i) => `
    <div class="step">
      <div class="bars" style="height: 100%">
        <div class="bar l" style="height: ${(s.l / max) * 100}%"></div>
        <div class="bar r" style="height: ${(s.r / max) * 100}%"></div>
      </div>
      <div class="step-label">#${i + 1}</div>
    </div>
  `).join('');

  host.innerHTML = `
    <div class="head">
      <div>
        <div class="th">สมมาตรซ้าย-ขวา</div>
        <div class="en">Left vs right · last 8 strides</div>
      </div>
      <span class="pill">PEAK kPa</span>
    </div>
    <div class="symmetry-grid">${bars}</div>
    <div class="legend-row">
      <div class="key"><span class="swatch l"></span>เท้าซ้าย · L</div>
      <div class="key"><span class="swatch r"></span>เท้าขวา · R</div>
    </div>
  `;
}

function renderCoP(): void {
  const host = document.getElementById('cop');
  if (!host) return;
  // Path traces heel → arch → meta → toe inside a foot outline
  host.innerHTML = `
    <div class="head">
      <div>
        <div class="th">ทางเดินจุดศูนย์ถ่วงแรงกด</div>
        <div class="en">Center of Pressure trajectory</div>
      </div>
      <span class="pill">1 GAIT CYCLE</span>
    </div>
    <div class="cop-wrap">
      <svg viewBox="0 0 100 220" aria-label="Center of pressure trace">
        <path d="M 50 22 C 70 30 78 60 76 100 C 74 140 68 175 60 195 C 55 205 45 210 38 200 C 30 188 28 160 30 130 C 32 100 34 60 50 22 Z"
              fill="#FAF6EC" stroke="rgba(0,0,0,0.18)" stroke-width="1.4" />
        <!-- CoP polyline: heel → arch → meta → toe -->
        <path class="cop-trace"
              d="M 50 185 C 52 165 50 145 48 125 C 46 105 50 80 52 60 C 53 48 52 38 50 30" />
        <circle class="cop-dot start" cx="50" cy="185" r="4.5" />
        <circle class="cop-dot end" cx="50" cy="30" r="4.5" />
        <text class="cop-label" x="56" y="188">heel</text>
        <text class="cop-label" x="56" y="33">toe</text>
      </svg>
    </div>
  `;
}

function renderTrend(): void {
  const host = document.getElementById('trend');
  if (!host) return;
  const data = MOCK_DATA.gaitHistory7Days;
  const min = Math.min(...data) - 4;
  const max = Math.max(...data) + 4;
  const w = 220, h = 60;
  const stepX = w / (data.length - 1);
  const pts = data.map((v, i) => {
    const x = i * stepX;
    const y = h - ((v - min) / (max - min)) * h;
    return [x, y] as const;
  });
  const linePath = pts.map((p, i) => (i === 0 ? `M ${p[0]} ${p[1]}` : `L ${p[0]} ${p[1]}`)).join(' ');
  const areaPath = `${linePath} L ${pts[pts.length - 1][0]} ${h} L 0 ${h} Z`;
  const dots = pts.map((p, i) => `<circle class="spark-dot ${i === pts.length - 1 ? 'last' : ''}" cx="${p[0]}" cy="${p[1]}" r="${i === pts.length - 1 ? 4 : 2.4}" />`).join('');
  const days = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
  const today = data[data.length - 1];
  const delta = today - data[0];

  host.innerHTML = `
    <div class="head">
      <div>
        <div class="th">แนวโน้ม 7 วัน</div>
        <div class="en">Symmetry score · 7 days</div>
      </div>
      <span class="pill">${data[data.length - 1]}/100</span>
    </div>
    <div class="trend-row">
      <div>
        <div class="score">${today}<span class="delta">${delta >= 0 ? '+' : ''}${delta}</span></div>
        <div class="score-sub">vs 7d ago</div>
      </div>
      <div class="sparkline">
        <svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
          <path class="spark-area" d="${areaPath}" />
          <path class="spark-line" d="${linePath}" />
          ${dots}
        </svg>
        <div class="day-row">${days.map(d => `<span>${d}</span>`).join('')}</div>
      </div>
    </div>
  `;
}

// ─── Lifecycle ───────────────────────────────────────────────

export function mount(): void {
  renderStatusBar();
  renderHeader();
  renderClassification();
  renderSymmetry();
  renderCoP();
  renderTrend();
  initNavigation();
}

export function unmount(): void {
  // Nothing to release: this screen is pure markup with no listeners and no
  // objects held outside #view, which the router clears on navigation.
}

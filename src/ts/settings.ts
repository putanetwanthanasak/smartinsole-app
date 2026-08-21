// settings.ts — Device pairing, profile, alert sensitivity, language, export

import { renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import { deviceManager } from './data/DeviceManager.js';
import type { CombinedSnapshot, ConnectionState, Unsubscribe } from './data/types.js';
import type { FootSide } from './types.js';

interface SettingsState {
  sensitivity: number;     // 0..100
  notifications: boolean;
  vibration: boolean;
  doctorAlerts: boolean;
  language: 'th' | 'en';
}

const state: SettingsState = {
  sensitivity: 65,
  notifications: true,
  vibration: true,
  doctorAlerts: false,
  language: 'th',
};

function batteryClass(pct: number): 'high' | 'med' | 'low' {
  if (pct >= 60) return 'high';
  if (pct >= 25) return 'med';
  return 'low';
}

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  host.innerHTML = `
    <a href="#/home" class="gear-btn" aria-label="กลับ" style="background:var(--bg-secondary)">
      <i data-lucide="chevron-left"></i>
    </a>
    <div class="title-block" style="flex:1;text-align:center">
      <div class="title" style="font-size:17px">ตั้งค่า</div>
      <span class="eyebrow">settings</span>
    </div>
    <div style="width:42px"></div>
  `;
  // Center the title block by overriding the default header layout
  host.style.justifyContent = 'space-between';
}

function renderProfile(): void {
  const host = document.getElementById('profile');
  if (!host) return;
  host.className = 'profile-card';
  host.innerHTML = `
    <div class="avatar">สม</div>
    <div class="who" style="flex:1">
      <div class="name">สมชาย รักษ์เท้า</div>
      <div class="meta-th">เบาหวานชนิดที่ 2 · อายุ 62 ปี</div>
      <div class="meta">Type 2 diabetes · age 62 · Dr. Wichai</div>
    </div>
    <i data-lucide="chevron-right" style="opacity:0.6"></i>
  `;
}

const STATE_EN: Record<ConnectionState, string> = {
  connected: 'connected',
  connecting: 'connecting',
  stale: 'signal stale',
  error: 'error',
  disconnected: 'offline',
};

/**
 * Device rows, live from the snapshot. Battery and firmware are only shown for a
 * side that is actually connected: both come from DeviceStatus, and a figure
 * left on screen from a link that has since dropped is stale data presented as
 * current. Firmware was previously the hardcoded literal 'v2.4.1'.
 */
function renderDevices(snap: CombinedSnapshot): void {
  const host = document.getElementById('devices');
  if (!host) return;

  const row = (side: FootSide) => {
    const s = side === 'left' ? snap.left : snap.right;
    const state: ConnectionState = s?.state ?? 'disconnected';
    const live = state === 'connected';
    const battery = live ? s?.status?.batteryPct ?? null : null;
    const firmware = live ? s?.status?.firmware ?? null : null;
    const sideTH = side === 'left' ? 'แผ่นรองเท้าซ้าย' : 'แผ่นรองเท้าขวา';
    const icon = live ? 'bluetooth-connected' : 'bluetooth';
    const meta = [STATE_EN[state], firmware].filter(Boolean).join(' · ');
    return `
      <div class="settings-row device-row state-${state}">
        <div class="ic brand"><i data-lucide="${icon}"></i></div>
        <div class="label">
          <div class="th">${sideTH}</div>
          <div class="en">
            <span class="conn-dot"></span>${meta}
          </div>
          <div class="battery-bar"><div class="battery-fill ${battery === null ? 'none' : batteryClass(battery)}" style="width:${battery ?? 0}%"></div></div>
        </div>
        <div>
          <div class="value">${battery === null ? '—' : `${battery}%`}</div>
          <div class="value-sub">battery</div>
        </div>
      </div>
    `;
  };

  const html = `
    <div class="block-head">
      <div class="th">อุปกรณ์</div>
      <div class="en">CONNECTED DEVICES</div>
    </div>
    ${row('left')}
    ${row('right')}
  `;
  if (lastDevicesHTML !== html) {
    lastDevicesHTML = html;
    host.innerHTML = html;
    refreshIcons();
  }
}

let lastDevicesHTML = '';

function renderPreferences(): void {
  const host = document.getElementById('preferences');
  if (!host) return;
  host.innerHTML = `
    <div class="block-head">
      <div class="th">การแจ้งเตือน</div>
      <div class="en">ALERT PREFERENCES</div>
    </div>

    <div class="slider-row">
      <div class="top">
        <div>
          <div class="th">ความไวการแจ้งเตือน</div>
          <div class="en">Alert sensitivity</div>
        </div>
        <span class="val" id="sens-val">${state.sensitivity}%</span>
      </div>
      <input class="slider" id="sens-slider" type="range" min="0" max="100" value="${state.sensitivity}" />
      <div class="scale">
        <span>น้อย · low</span>
        <span>มาก · high</span>
      </div>
    </div>

    <div class="settings-row">
      <div class="ic brand"><i data-lucide="bell"></i></div>
      <div class="label">
        <div class="th">การแจ้งเตือนพุช</div>
        <div class="en">Push notifications</div>
      </div>
      <button class="toggle ${state.notifications ? 'on' : ''}" data-key="notifications" type="button" aria-label="toggle"></button>
    </div>

    <div class="settings-row">
      <div class="ic brand"><i data-lucide="vibrate"></i></div>
      <div class="label">
        <div class="th">การสั่นเตือน</div>
        <div class="en">Vibration alerts</div>
      </div>
      <button class="toggle ${state.vibration ? 'on' : ''}" data-key="vibration" type="button" aria-label="toggle"></button>
    </div>

    <div class="settings-row">
      <div class="ic warn"><i data-lucide="stethoscope"></i></div>
      <div class="label">
        <div class="th">แจ้งแพทย์อัตโนมัติ</div>
        <div class="en">Auto-notify doctor on critical alerts</div>
      </div>
      <button class="toggle ${state.doctorAlerts ? 'on' : ''}" data-key="doctorAlerts" type="button" aria-label="toggle"></button>
    </div>
  `;

  const slider = host.querySelector<HTMLInputElement>('#sens-slider');
  const sensVal = host.querySelector<HTMLElement>('#sens-val');
  slider?.addEventListener('input', () => {
    state.sensitivity = parseInt(slider.value, 10);
    if (sensVal) sensVal.textContent = `${state.sensitivity}%`;
    slider.style.background = `linear-gradient(to right, var(--brand-primary) 0 ${state.sensitivity}%, var(--bg-secondary) ${state.sensitivity}% 100%)`;
  });
  if (slider) {
    slider.style.background = `linear-gradient(to right, var(--brand-primary) 0 ${state.sensitivity}%, var(--bg-secondary) ${state.sensitivity}% 100%)`;
  }

  host.querySelectorAll<HTMLButtonElement>('.toggle').forEach(t => {
    t.addEventListener('click', () => {
      const key = t.dataset.key as keyof SettingsState;
      if (key === 'notifications' || key === 'vibration' || key === 'doctorAlerts') {
        state[key] = !state[key];
        t.classList.toggle('on', state[key]);
      }
    });
  });
}

function renderLanguage(): void {
  const host = document.getElementById('language');
  if (!host) return;
  host.innerHTML = `
    <div class="block-head">
      <div class="th">อื่น ๆ</div>
      <div class="en">PREFERENCES</div>
    </div>
    <div class="settings-row">
      <div class="ic brand"><i data-lucide="languages"></i></div>
      <div class="label">
        <div class="th">ภาษา</div>
        <div class="en">Language</div>
      </div>
      <div class="lang-seg" id="lang-seg">
        <div class="seg ${state.language === 'th' ? 'active' : ''}" data-lang="th">ไทย</div>
        <div class="seg ${state.language === 'en' ? 'active' : ''}" data-lang="en">EN</div>
      </div>
    </div>
    <div class="settings-row">
      <div class="ic brand"><i data-lucide="user-round"></i></div>
      <div class="label">
        <div class="th">โปรไฟล์ผู้ป่วย</div>
        <div class="en">Patient profile · medical info</div>
      </div>
      <i data-lucide="chevron-right" class="chev"></i>
    </div>
    <div class="settings-row">
      <div class="ic brand"><i data-lucide="user-plus"></i></div>
      <div class="label">
        <div class="th">ผู้ดูแล</div>
        <div class="en">Caregiver access · 1 person</div>
      </div>
      <i data-lucide="chevron-right" class="chev"></i>
    </div>
  `;
  host.querySelectorAll<HTMLElement>('.seg').forEach(s => {
    s.addEventListener('click', () => {
      state.language = s.dataset.lang as 'th' | 'en';
      host.querySelectorAll('.seg').forEach(x => x.classList.toggle('active', (x as HTMLElement).dataset.lang === state.language));
    });
  });
}

function renderExport(): void {
  const host = document.getElementById('export');
  if (!host) return;
  host.innerHTML = `
    <button class="export-btn" type="button">
      <div class="ic-wrap"><i data-lucide="file-down"></i></div>
      <div class="label">
        <div class="th">ส่งออกรายงาน PDF สำหรับแพทย์</div>
        <div class="en">Export PDF report for your next visit</div>
      </div>
      <i data-lucide="arrow-right"></i>
    </button>
    <div class="app-version">Smart Insole Companion · v1.0.0</div>
  `;
}

// ─── Lifecycle ───────────────────────────────────────────────

let unsubs: Unsubscribe[] = [];

export function mount(): void {
  // `state` is deliberately NOT reset here — see unmount().
  lastDevicesHTML = '';
  renderStatusBar();
  renderHeader();
  renderProfile();
  unsubs.push(deviceManager.onSnapshot(renderDevices));
  renderPreferences();
  renderLanguage();
  renderExport();
  // No initNavigation() call: Settings is not a tab, so the router's cleared
  // tab bar stays empty, matching pages.reference/settings.html.
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  lastDevicesHTML = '';

  // renderHeader() sets an inline justify-content on #app-header, which now
  // lives in the shell and outlives this screen. Left in place it would centre
  // every other screen's header, so undo it here.
  const host = document.getElementById('app-header');
  if (host) host.style.justifyContent = '';

  // The slider, toggles and language segments are inside #view and are dropped
  // when the router clears it. `state` intentionally persists across
  // navigation: these are user preferences, not per-visit view state.
}

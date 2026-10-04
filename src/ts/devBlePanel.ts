// devBlePanel.ts — dev-only connect UI for real Web Bluetooth hardware.
//
// NOT one of the five screens (home/gait/temp/alerts/settings) — deliberately
// out of that rendering path, per this pass's brief. Mounted directly by
// main.ts, appended to <body> outside #view and outside .device-frame, so it
// survives every route change and is never confused with product UI.
//
// It exists ONLY because Web Bluetooth's requestDevice() requires a real
// user gesture (a click), which main.ts's normal boot-time
// deviceManager.connectAll() can never provide, and — per this pass's
// brief — two insoles means two SEPARATE gestures regardless. See
// data/DeviceManager.ts's `usingWebBle` for how this gets mounted instead of
// the usual auto-connect.
//
// Collapsed by default to a small "BLE L● R●" toggle in the top-left corner,
// so the app UI stays fully visible on a real phone; the toggle expands the
// full panel downward from the top of the viewport. Open/closed state is
// remembered in localStorage.

import type { FootSide } from './types.js';
import type { ConnectionState } from './data/types.js';
import type { DeviceManager } from './data/DeviceManager.js';
import type { WebBleDataSource } from './data/WebBleDataSource.js';

const SIDES: FootSide[] = ['left', 'right'];
const OPEN_STORAGE_KEY = 'bleDevPanelOpen';

// Collapsed-toggle status dots. Green means exactly 'connected' — stale and
// connecting get their own colour rather than borrowing it.
const STATE_DOT_COLOR: Record<ConnectionState, string> = {
  connected: '#3DDC84',
  connecting: '#FFC857',
  stale: '#FFC857',
  error: '#FF6B6B',
  disconnected: '#777',
};

const PANEL_CSS = `
#ble-dev-panel {
  position: fixed; top: 0; left: 0; right: 0; z-index: 99999;
  display: flex; flex-direction: column; gap: 8px;
  padding: max(8px, env(safe-area-inset-top)) max(8px, env(safe-area-inset-right)) 8px max(8px, env(safe-area-inset-left));
  font: 14px/1.4 monospace; color: #7CFC7C;
  pointer-events: none;
}
#ble-dev-panel.is-open {
  pointer-events: auto;
  background: #111; border-bottom: 2px solid #7CFC7C;
  max-height: 100vh; max-height: 100dvh; overflow-y: auto;
}
#ble-dev-panel .bdp-bar { display: flex; align-items: center; gap: 8px; }
#ble-dev-panel .bdp-title { flex: 1; min-width: 0; font-size: 12px; font-weight: bold; }
#ble-dev-panel button {
  pointer-events: auto;
  min-width: 44px; min-height: 44px; padding: 0 12px;
  font: bold 14px/1 monospace; color: #7CFC7C;
  background: #1E1E1E; border: 1px solid #7CFC7C; border-radius: 8px;
}
#ble-dev-panel button:active { background: #2E4A2E; }
#ble-dev-panel .bdp-toggle {
  display: flex; align-items: center; gap: 6px; flex: none;
  background: rgba(17, 17, 17, 0.88);
}
#ble-dev-panel .bdp-dot { color: #777; }
#ble-dev-panel .bdp-close { flex: none; padding: 0; font-size: 22px; }
#ble-dev-panel:not(.is-open) .bdp-title,
#ble-dev-panel:not(.is-open) .bdp-close,
#ble-dev-panel:not(.is-open) .bdp-row { display: none; }
#ble-dev-panel .bdp-row { display: flex; flex-direction: column; gap: 6px; padding-top: 8px; border-top: 1px solid #333; }
#ble-dev-panel .bdp-actions { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
#ble-dev-panel .bdp-actions button { padding: 0 4px; }
#ble-dev-panel [data-role="diag"] { font-size: 12px; opacity: 0.7; overflow-wrap: anywhere; }
#ble-dev-panel [data-role="detail"] { color: #FF6B6B; overflow-wrap: anywhere; }
`;

export function mountDevBlePanel(deviceManager: DeviceManager, bleSources: Record<FootSide, WebBleDataSource>): void {
  const style = document.createElement('style');
  style.textContent = PANEL_CSS;
  document.head.appendChild(style);

  const panel = document.createElement('div');
  panel.id = 'ble-dev-panel';
  panel.innerHTML = `
    <div class="bdp-bar">
      <button class="bdp-toggle" data-action="toggle" aria-label="Toggle BLE dev panel">
        BLE
        <span>L<span class="bdp-dot" data-dot="left">●</span></span>
        <span>R<span class="bdp-dot" data-dot="right">●</span></span>
      </button>
      <div class="bdp-title">BLE DEV PANEL (?ds=ble) — not part of the app UI</div>
      <button class="bdp-close" data-action="close" aria-label="Close BLE dev panel">×</button>
    </div>
  `;

  const rows: Record<FootSide, HTMLElement> = { left: buildRow('left'), right: buildRow('right') };
  SIDES.forEach(side => panel.appendChild(rows[side]));

  const toggle = panel.querySelector<HTMLButtonElement>('[data-action="toggle"]')!;
  const setOpen = (open: boolean): void => {
    panel.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', String(open));
    writeStoredOpen(open);
  };
  setOpen(readStoredOpen());
  toggle.addEventListener('click', () => setOpen(!panel.classList.contains('is-open')));
  panel.querySelector<HTMLButtonElement>('[data-action="close"]')!.addEventListener('click', () => setOpen(false));

  document.body.appendChild(panel);

  for (const side of SIDES) {
    const row = rows[side];
    row.querySelector<HTMLButtonElement>('[data-action="connect"]')!.addEventListener('click', () => {
      deviceManager.connect(side).catch(err => {
        console.error(`[ble-dev-panel] connect(${side}) failed:`, err);
        setDetail(row, `connect() failed: ${err instanceof Error ? err.message : String(err)}`);
      });
    });
    row.querySelector<HTMLButtonElement>('[data-action="disconnect"]')!.addEventListener('click', () => {
      void deviceManager.disconnect(side);
    });
    row.querySelector<HTMLButtonElement>('[data-action="forget"]')!.addEventListener('click', () => {
      bleSources[side].forgetDevice();
      setDetail(row, 'device forgotten — next Connect will show the picker again');
    });
  }

  // Dev tool, not a live app screen — polling is fine (no build-once/mutate
  // rigor needed here, this is diagnostic scaffolding, not product UI).
  setInterval(() => {
    for (const side of SIDES) {
      const row = rows[side];
      const state = deviceManager.getStateOf(side);
      row.querySelector('[data-role="state"]')!.textContent = state;
      panel.querySelector<HTMLElement>(`[data-dot="${side}"]`)!.style.color = STATE_DOT_COLOR[state];
      const diag = bleSources[side].getDiagnostics();
      row.querySelector('[data-role="diag"]')!.textContent =
        `pkts=${diag.totalPackets} dropped=${diag.droppedPackets} truncated=${diag.truncatedPackets} `
        + `unparseable=${diag.unparseablePackets} seq=${diag.lastSeq ?? '—'} `
        + `offset=${diag.timeOffsetMs ?? '—'}ms cal=${diag.calibration?.deviceId ?? '—'}`;
    }
  }, 500);
}

function buildRow(side: FootSide): HTMLElement {
  const row = document.createElement('div');
  row.className = 'bdp-row';
  row.innerHTML = `
    <div><strong>${side}</strong> state=<span data-role="state">disconnected</span></div>
    <div class="bdp-actions">
      <button data-action="connect">Connect</button>
      <button data-action="disconnect">Disconnect</button>
      <button data-action="forget">Forget</button>
    </div>
    <div data-role="diag"></div>
    <div data-role="detail"></div>
  `;
  return row;
}

function setDetail(row: HTMLElement, text: string): void {
  row.querySelector('[data-role="detail"]')!.textContent = text;
}

// localStorage can throw (private mode, storage disabled) — the panel must
// still work, it just won't remember its state.
function readStoredOpen(): boolean {
  try {
    return localStorage.getItem(OPEN_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

function writeStoredOpen(open: boolean): void {
  try {
    localStorage.setItem(OPEN_STORAGE_KEY, open ? '1' : '0');
  } catch {
    // ignore — see readStoredOpen
  }
}

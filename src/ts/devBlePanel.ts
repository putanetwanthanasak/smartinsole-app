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

import type { FootSide } from './types.js';
import type { DeviceManager } from './data/DeviceManager.js';
import type { WebBleDataSource } from './data/WebBleDataSource.js';

const SIDES: FootSide[] = ['left', 'right'];

export function mountDevBlePanel(deviceManager: DeviceManager, bleSources: Record<FootSide, WebBleDataSource>): void {
  const panel = document.createElement('div');
  panel.id = 'ble-dev-panel';
  panel.setAttribute('style', [
    'position:fixed', 'left:0', 'right:0', 'bottom:0', 'z-index:99999',
    'background:#111', 'color:#7CFC7C', 'font:11px/1.4 monospace',
    'padding:8px 10px', 'display:flex', 'flex-direction:column', 'gap:6px',
    'border-top:2px solid #7CFC7C',
  ].join(';'));

  const title = document.createElement('div');
  title.textContent = 'BLE DEV PANEL (?ds=ble) — not part of the app UI';
  title.style.fontWeight = 'bold';
  panel.appendChild(title);

  const rows: Record<FootSide, HTMLElement> = { left: buildRow('left'), right: buildRow('right') };
  SIDES.forEach(side => panel.appendChild(rows[side]));

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
  row.innerHTML = `
    <strong>${side}</strong>
    <button data-action="connect">Connect</button>
    <button data-action="disconnect">Disconnect</button>
    <button data-action="forget">Forget device</button>
    state=<span data-role="state">disconnected</span>
    <div data-role="diag" style="opacity:0.7"></div>
    <div data-role="detail" style="color:#FF6B6B"></div>
  `;
  return row;
}

function setDetail(row: HTMLElement, text: string): void {
  row.querySelector('[data-role="detail"]')!.textContent = text;
}

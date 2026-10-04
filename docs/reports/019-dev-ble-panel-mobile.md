# 019 — Dev BLE panel usable on a phone

Dev-only UI fix. The `?ds=ble` panel (`src/ts/devBlePanel.ts`) was a bar
fixed to the bottom of the viewport with 11px text and unstyled buttons; on a
real Android phone its Connect buttons were obscured and it covered the app.

## What changed

- **`src/ts/devBlePanel.ts`** — the only source file touched.
  - Collapsed by default to a floating **`BLE L● R●`** toggle, top-left,
    92x44px. Tapping it shows/hides the panel.
  - Per-side status dot on the toggle, updated by the existing 500 ms poll
    from `deviceManager.getStateOf(side)`: green = `connected`, amber =
    `connecting` or `stale`, red = `error`, grey = `disconnected`. Green means
    exactly `connected` — a stale stream does not show green.
  - Expanded panel drops down from the **top** of the viewport, with a **×**
    close button (44x44px) in its header row.
  - Connect / Disconnect / Forget are styled buttons in a 3-column grid, each
    44px tall, 14px bold text. "Forget device" is now labelled "Forget" so
    three fit across a phone.
  - Padding uses `max(8px, env(safe-area-inset-*))` on top/left/right.
  - Open/closed state persists in `localStorage` (`bleDevPanelOpen`), read
    and written inside try/catch.
  - Styles moved from an inline `style` attribute to one injected `<style>`
    element, all scoped under `#ble-dev-panel`.
- **`docs/BLE-TEST-CHECKLIST.md`** — setup step 3 described the old bottom
  bar; updated to the toggle + top panel, and "Forget device" → "Forget".

Not touched: `WebBleDataSource`, `DeviceManager`, `main.ts`, every screen,
`index.html`, all CSS files. Gating is unchanged — `main.ts` still only calls
`mountDevBlePanel` when `usingWebBle && bleSources`.

## Verification

- `npm run build` — clean.
- Layout checked in Chrome in a 412x880 viewport (the app loaded in a
  412px-wide iframe, since the Chrome window would not resize below its
  minimum width):
  - On load: collapsed, toggle at (8,8) 92x44; taps elsewhere reach the app
    (the collapsed container is `pointer-events: none` apart from the toggle).
  - Expanded: panel 326px tall from the top, no horizontal overflow; all six
    action buttons 122x44 at 14px, × 44x44.
  - Open state survives reload; × closes; closed state survives reload.
  - Without `?ds=ble`, `#ble-dev-panel` is absent from the DOM.

## Not verified

- **Not run on a real Android phone**, and no BLE device was connected in
  this pass, so the dot colours for non-disconnected states were not observed
  live.
- **Safe-area insets**: `index.html`'s viewport meta has no
  `viewport-fit=cover`, so `env(safe-area-inset-*)` resolves to 0 and the 8px
  floor applies. In a normal Chrome tab that is correct (the browser already
  keeps the page out of the status bar). If the Capacitor build goes
  edge-to-edge, `viewport-fit=cover` will be needed for the insets to take
  effect — left alone here since `index.html` is not dev-only.

## Things noticed, not changed

- Collapsed, the toggle sits over the faux iOS status bar's clock at the top
  left; it does not overlap the header title or the settings gear.
- At 412px the `.device-frame` (402px + 2x16px body padding) is wider than
  the viewport, so the app itself scrolls sideways slightly on a phone. That
  is product CSS, outside this pass.

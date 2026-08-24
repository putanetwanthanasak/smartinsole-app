// main.ts — the single entry module index.html loads.
//
// Vendored web fonts, then the router. Both were CDN-loaded before; they are
// bundled now so the app makes no external requests and works offline inside a
// Capacitor shell.
//
// These replace the Google Fonts @import that used to sit at css/global.css:5.
// The weights below match that URL exactly — Noto Sans Thai 400/500/600/700,
// Inter 400/500/600/700, JetBrains Mono 500/600 — and the @fontsource packages
// declare the same family names ('Noto Sans Thai', 'Inter', 'JetBrains Mono'),
// so the --font-th / --font-en / --font-mono tokens resolve unchanged.
import '@fontsource/noto-sans-thai/400.css';
import '@fontsource/noto-sans-thai/500.css';
import '@fontsource/noto-sans-thai/600.css';
import '@fontsource/noto-sans-thai/700.css';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/inter/700.css';
import '@fontsource/jetbrains-mono/500.css';
import '@fontsource/jetbrains-mono/600.css';

import { startRouter } from './router.js';
import { deviceManager, usingWebBle, bleSources } from './data/DeviceManager.js';
import { mountDevBlePanel } from './devBlePanel.js';
import { setMockGaitPrediction } from './data/gaitPrediction.js';
import { alertStore } from './data/AlertStore.js';
import { loadThresholds } from './data/thresholds.js';
import { setPatientSensitivity } from './constants.js';

document.addEventListener('DOMContentLoaded', () => {
  startRouter();

  // Fire-and-forget: constants.ts's DEFAULT_THRESHOLDS already makes every
  // threshold usable synchronously (see constants.ts), so nothing here
  // blocks boot on this fetch. loadThresholds() never throws — it logs and
  // falls back to defaults itself on any failure (see data/thresholds.ts).
  void loadThresholds();

  // Dev-only console hooks. Same status as DeviceManager.ts's `window.__insole`
  // (which this deliberately doesn't touch — see this pass's brief):
  //   window.mockGait.set('heel_walking', 0.75) / .clear()
  //     — drives the Data Contract §8.3.1 gait-pattern advisory layer
  //       (AlertStore). No real Model A integration exists yet, so this is
  //       the only way to exercise it before that lands.
  //   window.__alertStore
  //     — the AlertStore singleton, so a rule's 30-min repeat-suppression
  //       can be cleared for retesting: __alertStore.lastFiredAt.clear()
  //       (TS `private` is compile-time only; the field is a plain Map at
  //       runtime, reachable from an untyped console).
  //   window.__thresholds.load(url) / .setPatientSensitivity(pct)
  //     — re-run the thresholds.json loader against an arbitrary URL (for
  //       testing the malformed/missing-file path), or exercise the
  //       not-yet-UI'd patient sensitivity mutator directly.
  if (import.meta.env.DEV) {
    (window as unknown as { mockGait: unknown }).mockGait = {
      set: setMockGaitPrediction,
      clear: () => setMockGaitPrediction(null),
    };
    (window as unknown as { __alertStore: unknown }).__alertStore = alertStore;
    (window as unknown as { __thresholds: unknown }).__thresholds = {
      load: loadThresholds,
      setPatientSensitivity,
    };
  }

  if (usingWebBle && bleSources) {
    // Web Bluetooth's requestDevice() requires a real user gesture per
    // device — a boot-time call can never provide that, and two insoles
    // means two separate gestures regardless (see devBlePanel.ts). The
    // usual auto-connect below is skipped entirely in this mode.
    mountDevBlePanel(deviceManager, bleSources);
    return;
  }

  // Connect ONCE at app start, not from any screen's mount().
  // Screens used to call connectAll() themselves, which meant simply changing
  // tabs silently re-established a link the user had deliberately dropped — and
  // made the disconnected state impossible to observe on any screen but the one
  // it was triggered from. Pairing is an app-level concern, not a per-screen one.
  void deviceManager.connectAll();
});

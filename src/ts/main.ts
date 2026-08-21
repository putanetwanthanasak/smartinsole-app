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
import { deviceManager } from './data/DeviceManager.js';

document.addEventListener('DOMContentLoaded', () => {
  startRouter();

  // Connect ONCE at app start, not from any screen's mount().
  // Screens used to call connectAll() themselves, which meant simply changing
  // tabs silently re-established a link the user had deliberately dropped — and
  // made the disconnected state impossible to observe on any screen but the one
  // it was triggered from. Pairing is an app-level concern, not a per-screen one.
  void deviceManager.connectAll();
});

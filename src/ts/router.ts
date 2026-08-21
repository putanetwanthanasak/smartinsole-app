// router.ts — hash router for the single-page shell.
//
// Routes:  #/home  #/gait  #/temp  #/alerts  #/settings
//
// On every route change the router unmounts the outgoing screen, clears #view,
// injects the incoming screen's section scaffolding (lifted verbatim from the
// matching pages.reference/*.html), calls that screen's mount(), then re-runs lucide once.
// An empty or unrecognised hash resolves to #/home.

import * as home from './home.js';
import * as gait from './gait.js';
import * as temperature from './temperature.js';
import * as alerts from './alerts.js';
import * as settings from './settings.js';
import * as capture from './capture.js';
import { refreshIcons } from './icons.js';

export type RouteId = 'home' | 'gait' | 'temp' | 'alerts' | 'settings' | 'capture';

/** Every screen module exposes exactly this pair. */
export interface Screen {
  mount(): void;
  unmount(): void;
}

interface Route {
  id: RouteId;
  /** Mirrors the <title> of the page this screen replaces. */
  title: string;
  /** Page wrapper class that used to sit on <main> / the page's wrapper <div>. */
  viewClass: string;
  /** Section scaffolding, lifted from pages.reference/<name>.html. */
  template: string;
  screen: Screen;
}

const DEFAULT_ROUTE: RouteId = 'home';

// ─── Screen scaffolding ───────────────────────────────────────
// These are the <section> hosts each screen's renderers write into. They are
// copied from pages.reference/*.html minus the <header id="app-header">, which is now
// persistent shell furniture in index.html.

const HOME_TEMPLATE = `
      <section id="alert-banner"></section>
      <section id="connection-strip" class="connection-strip"></section>
      <section id="status-badge"></section>

      <section id="heatmap-host" class="heatmap-host"></section>

      <section class="tail-stack">
        <button id="temp-compact" type="button"></button>
        <section id="today-summary"></section>
      </section>
`;

const GAIT_TEMPLATE = `
        <section id="classification"></section>
        <section id="symmetry" class="gait-card"></section>
        <section id="cop" class="gait-card"></section>
        <section id="trend" class="gait-card"></section>
`;

const TEMP_TEMPLATE = `
        <section id="dt-hero"></section>
        <section id="temp-feet" class="temp-card"></section>
        <section id="temp-trend" class="trend-card"></section>
        <section id="alert-history" class="alert-mini"></section>
`;

const ALERTS_TEMPLATE = `
        <section id="emergency"></section>
        <section id="filter-row"></section>
        <section id="timeline" class="timeline"></section>
`;

const SETTINGS_TEMPLATE = `
        <section id="profile"></section>
        <section id="devices" class="settings-block"></section>
        <section id="preferences" class="settings-block"></section>
        <section id="language" class="settings-block"></section>
        <section id="export"></section>
`;

// capture.ts owns everything inside this single host — an operator flow with
// several steps (subject entry / calibration / recording / export), not a
// fixed set of named sections like the patient screens above. Not a tab —
// reached only by navigating to #/capture directly, never linked from the
// patient-facing UI (docs/reports/010-*.md).
const CAPTURE_TEMPLATE = `
        <div id="capture-body" class="capture-body"></div>
`;

const ROUTES: Record<RouteId, Route> = {
  home:     { id: 'home',     title: 'Smart Insole — หน้าหลัก',      viewClass: 'home-page',     template: HOME_TEMPLATE,     screen: home },
  gait:     { id: 'gait',     title: 'Smart Insole — การเดิน',        viewClass: 'gait-page',     template: GAIT_TEMPLATE,     screen: gait },
  temp:     { id: 'temp',     title: 'Smart Insole — อุณหภูมิ',        viewClass: 'temp-page',     template: TEMP_TEMPLATE,     screen: temperature },
  alerts:   { id: 'alerts',   title: 'Smart Insole — การแจ้งเตือน',   viewClass: 'alerts-page',   template: ALERTS_TEMPLATE,   screen: alerts },
  settings: { id: 'settings', title: 'Smart Insole — ตั้งค่า',         viewClass: 'settings-page', template: SETTINGS_TEMPLATE, screen: settings },
  capture:  { id: 'capture',  title: 'Smart Insole — Research Capture', viewClass: 'capture-page', template: CAPTURE_TEMPLATE, screen: capture },
};

// ─── Route resolution ─────────────────────────────────────────

/** '#/temp' → 'temp'. Empty or unknown hashes fall back to the default route. */
export function resolveRoute(hash: string = window.location.hash): RouteId {
  const raw = hash.replace(/^#\/?/, '').toLowerCase();
  return Object.prototype.hasOwnProperty.call(ROUTES, raw)
    ? (raw as RouteId)
    : DEFAULT_ROUTE;
}

/** Canonical hash for a route, e.g. 'temp' → '#/temp'. */
export function hrefFor(id: RouteId): string {
  return `#/${id}`;
}

// ─── Navigation ───────────────────────────────────────────────

let current: Route | null = null;

function navigate(id: RouteId): void {
  const route = ROUTES[id];

  // Normalise the address bar before mounting: the tab bar derives its active
  // state from the hash, so '' and '#/HOME' must become '#/home' first.
  // replaceState does not fire hashchange, so this cannot re-enter navigate().
  const canonical = hrefFor(id);
  if (window.location.hash !== canonical) {
    window.history.replaceState(null, '', canonical);
  }

  const view = document.getElementById('view');
  if (!view) return;

  if (current) current.screen.unmount();

  view.innerHTML = '';
  view.className = route.viewClass;
  document.title = route.title;

  // Blank the tab bar so a screen that does not call initNavigation (Settings)
  // shows the same empty bar it showed as its own page.
  const bar = document.querySelector<HTMLElement>('nav.tab-bar');
  if (bar) bar.innerHTML = '';

  view.innerHTML = route.template;

  // A full page load always started at the top; reproduce that.
  const scroller = document.querySelector<HTMLElement>('.app-scroll');
  if (scroller) scroller.scrollTop = 0;

  route.screen.mount();
  current = route;

  // One icon pass for everything the scaffolding + mount() just injected.
  refreshIcons();
}

/** Wire up hashchange and render the current route. */
export function startRouter(): void {
  window.addEventListener('hashchange', () => navigate(resolveRoute()));
  navigate(resolveRoute());
}

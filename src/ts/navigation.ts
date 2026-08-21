// navigation.ts — Bottom tab bar active state + in-app navigation
//
// Each screen calls `initNavigation()` from its mount(). The active tab is
// derived from the current hash route rather than being passed in, so the bar
// can never disagree with what the router actually mounted.

import { refreshIcons } from './icons.js';

export type TabId = 'home' | 'gait' | 'temp' | 'alerts';

interface TabSpec {
  id: TabId;
  href: string;
  th: string;
  en: string;
  icon: string;        // lucide icon name
  badgeAttr?: string;  // optional dataset key for showing a count
}

const TABS: TabSpec[] = [
  { id: 'home',   href: '#/home',   th: 'หน้าหลัก',   en: 'Home',   icon: 'home'      },
  { id: 'gait',   href: '#/gait',   th: 'การเดิน',    en: 'Gait',   icon: 'activity'  },
  { id: 'temp',   href: '#/temp',   th: 'อุณหภูมิ',    en: 'Temp',   icon: 'thermometer' },
  { id: 'alerts', href: '#/alerts', th: 'แจ้งเตือน',  en: 'Alerts', icon: 'bell',     badgeAttr: 'alertCount' },
];

/**
 * The tab matching the current hash, or null when the route is not a tab
 * (Settings, which is reached via the header gear button).
 */
export function currentTabId(): TabId | null {
  const hash = window.location.hash.toLowerCase();
  const tab = TABS.find(t => t.href === hash);
  return tab ? tab.id : null;
}

/**
 * Build the bottom tab bar inside an existing `<nav class="tab-bar">`
 * element, marking the current route's tab as active.
 */
export function initNavigation(opts?: { alertCount?: number }): void {
  const bar = document.querySelector<HTMLElement>('nav.tab-bar');
  if (!bar) return;

  const active = currentTabId();

  bar.innerHTML = '';
  for (const tab of TABS) {
    const btn = document.createElement('a');
    btn.className = 'tab' + (tab.id === active ? ' active' : '');
    btn.href = tab.href;

    const icWrap = document.createElement('span');
    icWrap.className = 'ic-wrap';

    const ic = document.createElement('i');
    ic.setAttribute('data-lucide', tab.icon);
    icWrap.appendChild(ic);

    if (tab.id === 'alerts' && opts?.alertCount && opts.alertCount > 0) {
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = String(opts.alertCount);
      icWrap.appendChild(badge);
    }

    const label = document.createElement('span');
    label.className = 'tab-label';
    label.textContent = tab.th;

    btn.appendChild(icWrap);
    btn.appendChild(label);
    bar.appendChild(btn);
  }

  // Re-render lucide icons after we've injected new <i data-lucide> nodes
  refreshIcons();
}

/**
 * Render the iOS-style status bar (time + signal/wifi/battery placeholder).
 * Pure presentational; safe to call on every page.
 */
export function renderStatusBar(time: string = '9:41'): void {
  const sb = document.querySelector<HTMLElement>('.status-bar');
  if (!sb) return;
  sb.innerHTML = `
    <span class="time">${time}</span>
    <span class="icons">
      <svg width="18" height="11" viewBox="0 0 18 11" fill="currentColor">
        <rect x="0"  y="7" width="3" height="4" rx="0.7"/>
        <rect x="5"  y="5" width="3" height="6" rx="0.7"/>
        <rect x="10" y="2" width="3" height="9" rx="0.7"/>
        <rect x="15" y="0" width="3" height="11" rx="0.7"/>
      </svg>
      <svg width="25" height="12" viewBox="0 0 25 12" fill="none" stroke="currentColor" stroke-width="1">
        <rect x="0.5" y="0.5" width="22" height="11" rx="3" />
        <rect x="2"   y="2"   width="19" height="8"  rx="1.5" fill="currentColor"/>
      </svg>
    </span>
  `;
}

// alerts.ts — Alerts timeline + filter + emergency contact.
//
// Alerts now come from the AlertStore, which generates them from real threshold
// crossings on the device stream. Day grouping is derived from each entry's
// timestamp instead of substring-matching Thai words out of a display string.
//
// Re-render strategy: the timeline is rebuilt through writeIfChanged and only
// when its markup differs, which for an alert log means when an alert is raised
// or acknowledged — not at 10 Hz. Clicks are handled by one delegated listener
// on the timeline host, so rebuilding the list cannot strand handlers.

import { ALERT_RECOMMENDATIONS } from './constants.js';
import { initNavigation, renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import { alertStore, bucketOf, formatAlertTime } from './data/AlertStore.js';
import type { DayBucket } from './data/AlertStore.js';
import type { Unsubscribe } from './data/types.js';
import type { AlertEntry, SeverityLevel } from './types.js';

type AlertType = AlertEntry['type'];

interface ExpandedAlert extends AlertEntry {
  day: DayBucket;
  iconName: string;
  tone: 'danger' | 'warn' | 'safe';
}

function expand(a: AlertEntry): ExpandedAlert {
  const iconMap: Record<AlertType, string> = {
    pressure: 'gauge',
    temperature: 'thermometer',
    gait: 'footprints',
  };
  const toneMap: Record<SeverityLevel, 'danger' | 'warn' | 'safe'> = {
    safe:    'safe',
    danger:  'danger',
    warning: 'warn',
    caution: 'warn',
  };
  return { ...a, day: bucketOf(a.tUnixMs), iconName: iconMap[a.type], tone: toneMap[a.severity] };
}

let lastHTML: Record<string, string> = {};

function writeIfChanged(host: HTMLElement, key: string, html: string): boolean {
  if (lastHTML[key] === html) return false;
  lastHTML[key] = html;
  host.innerHTML = html;
  return true;
}

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  host.innerHTML = `
    <div class="title-block">
      <span class="eyebrow">alerts · การแจ้งเตือน</span>
      <div class="title">การแจ้งเตือน</div>
    </div>
    <a href="#/settings" class="gear-btn" aria-label="ตั้งค่า">
      <i data-lucide="settings"></i>
    </a>
  `;
}

let activeFilter: 'all' | AlertType = 'all';
let current: AlertEntry[] = [];

function renderFilter(): void {
  const host = document.getElementById('filter-row');
  if (!host) return;
  const filters: { id: 'all' | AlertType; th: string; en: string }[] = [
    { id: 'all',         th: 'ทั้งหมด',  en: 'All' },
    { id: 'pressure',    th: 'แรงกด',   en: 'Pressure' },
    { id: 'temperature', th: 'อุณหภูมิ', en: 'Temp' },
    { id: 'gait',        th: 'การเดิน', en: 'Gait' },
  ];
  host.className = 'filter-row';
  writeIfChanged(host, 'filter', filters.map(f => `
    <button class="chip ${f.id === activeFilter ? 'active' : ''}" data-filter="${f.id}" type="button">
      <span class="th">${f.th}</span>
      <span class="en">${f.en}</span>
    </button>
  `).join(''));
}

function renderTimeline(): void {
  const host = document.getElementById('timeline');
  if (!host) return;
  const all = current.map(expand);
  const filtered = activeFilter === 'all' ? all : all.filter(a => a.type === activeFilter);

  const groups: Record<DayBucket, ExpandedAlert[]> = { today: [], yesterday: [], older: [] };
  for (const a of filtered) groups[a.day].push(a);
  for (const k of Object.keys(groups) as DayBucket[]) {
    groups[k].sort((x, y) => y.tUnixMs - x.tUnixMs);
  }

  const groupLabels: Record<DayBucket, { th: string; en: string }> = {
    today:     { th: 'วันนี้',     en: 'TODAY' },
    yesterday: { th: 'เมื่อวาน',    en: 'YESTERDAY' },
    older:     { th: 'ก่อนหน้านี้', en: 'EARLIER' },
  };

  let html = '';
  for (const day of ['today', 'yesterday', 'older'] as const) {
    if (groups[day].length === 0) continue;
    html += `<div class="timeline-day">${groupLabels[day].th} · ${groupLabels[day].en}</div>`;
    for (const a of groups[day]) {
      const recco = ALERT_RECOMMENDATIONS[a.type];
      html += `
        <div class="alert-card tone-${a.tone}">
          <div class="ic"><i data-lucide="${a.iconName}"></i></div>
          <div class="body">
            <div class="title-row">
              <div class="title-th">${a.message}</div>
              <div class="time">${formatAlertTime(a.tUnixMs)}</div>
            </div>
            <div class="recco">
              <i data-lucide="lightbulb" class="arrow ic-xs"></i>
              <span><strong>${recco.th}</strong> · ${recco.en}</span>
            </div>
          </div>
          <div class="ack-state">
            ${a.acknowledged
              ? `<span class="ack-pill done"><i data-lucide="check" class="ic-xs"></i>รับทราบ</span>`
              : `<button class="ack-pill new" type="button" data-ack="${a.id}">NEW</button>`}
          </div>
        </div>
      `;
    }
  }
  if (!html) {
    html = `<div style="padding:32px 8px;text-align:center;color:var(--text-tertiary);font-size:13px">ไม่มีการแจ้งเตือนในหมวดนี้<br><span style="font-family:var(--font-en);font-size:11px;opacity:0.8">No alerts in this category</span></div>`;
  }
  if (writeIfChanged(host, 'timeline', html)) refreshIcons();
}

function renderEmergency(): void {
  const host = document.getElementById('emergency');
  if (!host) return;
  host.className = 'emergency';
  host.innerHTML = `
    <div class="pulse"><i data-lucide="phone"></i></div>
    <div class="label">
      <div class="title-th">ติดต่อแพทย์ฉุกเฉิน</div>
      <div class="title-en">Emergency · call your doctor</div>
      <div class="num">นพ. วิชัย · 02-XXX-XXXX</div>
    </div>
    <button class="call-btn" type="button" aria-label="โทร">
      <i data-lucide="phone-call"></i>
    </button>
  `;
}

// ─── Lifecycle ───────────────────────────────────────────────

let unsubs: Unsubscribe[] = [];

/** One delegated listener each for the filter row and the timeline, attached at
 *  mount. Both hosts survive re-renders, so no handler is ever stranded. */
function wireDelegates(): void {
  const filterHost = document.getElementById('filter-row');
  filterHost?.addEventListener('click', e => {
    const btn = (e.target as HTMLElement).closest<HTMLElement>('.chip');
    if (!btn) return;
    activeFilter = btn.dataset.filter as 'all' | AlertType;
    renderFilter();
    renderTimeline();
  });

  const timelineHost = document.getElementById('timeline');
  timelineHost?.addEventListener('click', e => {
    const btn = (e.target as HTMLElement).closest<HTMLElement>('[data-ack]');
    if (!btn) return;
    alertStore.acknowledge(Number(btn.dataset.ack));   // store re-emits, list re-renders
  });
}

export function mount(): void {
  lastHTML = {};
  activeFilter = 'all';
  renderStatusBar();
  renderHeader();
  renderEmergency();
  wireDelegates();

  unsubs.push(alertStore.subscribe(list => {
    current = list;
    renderFilter();
    renderTimeline();
    initNavigation({ alertCount: alertStore.unacknowledgedCount() });
  }));
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  lastHTML = {};
  // The delegated listeners are on #filter-row and #timeline, both inside #view,
  // and are discarded when the router clears it.
}

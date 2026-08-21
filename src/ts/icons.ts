// icons.ts — Lucide icons, vendored from npm.
//
// Replaces the `<script src="unpkg.com/lucide">` CDN global that used to be read
// as `(window as any).lucide.createIcons()`. Every call site now imports
// `refreshIcons()` from here instead.
//
// Only the icons this app actually uses are bundled. Passing lucide's full
// `icons` barrel (2030 icons) would pull the entire set into the bundle, since a
// barrel object defeats tree-shaking. The set below is exhaustive as of this
// commit and includes the names assigned dynamically at
// home.ts (shield / alert-triangle / activity), heatmap.ts (shield /
// alert-triangle), alerts.ts (gauge / thermometer / footprints), and
// gait.ts (bluetooth / construction, chosen per-section — see the comment
// at unavailableCardHTML in gait.ts for why they're not interchangeable),
// which a search for `data-lucide="..."` alone does not reveal.
//
// If you add a new `data-lucide` name, add it here too — `warnMissingIcons()`
// below will flag it in dev if you forget.

import {
  createIcons,
  Activity,
  AlertTriangle,
  ArrowRight,
  Bell,
  Bluetooth,
  BluetoothConnected,
  Calendar,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Construction,
  FileDown,
  Footprints,
  Gauge,
  Home,
  Languages,
  Lightbulb,
  Phone,
  PhoneCall,
  RefreshCcw,
  Settings,
  Shield,
  Stethoscope,
  Thermometer,
  UserPlus,
  UserRound,
  Vibrate,
  X,
} from 'lucide';

const USED_ICONS = {
  Activity,
  AlertTriangle,
  ArrowRight,
  Bell,
  Bluetooth,
  BluetoothConnected,
  Calendar,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Construction,
  FileDown,
  Footprints,
  Gauge,
  Home,
  Languages,
  Lightbulb,
  Phone,
  PhoneCall,
  RefreshCcw,
  Settings,
  Shield,
  Stethoscope,
  Thermometer,
  UserPlus,
  UserRound,
  Vibrate,
  X,
};

/**
 * Replace every `<i data-lucide="...">` in the document with its SVG.
 *
 * Same whole-document scan the CDN global performed, so the call sites keep
 * their existing semantics: safe to call repeatedly, and only elements that
 * still carry the attribute are processed.
 */
export function refreshIcons(): void {
  createIcons({ icons: USED_ICONS });
  if (import.meta.env.DEV) warnMissingIcons();
}

/**
 * Dev-only guard: report placeholders createIcons could not resolve.
 *
 * Note the `:not(svg)` — lucide keeps the `data-lucide` attribute on the <svg>
 * it generates, so a bare `[data-lucide]` query matches every *successfully*
 * rendered icon. Only a placeholder that is still its original element (the
 * renderers emit `<i data-lucide="...">`) indicates a name missing from
 * USED_ICONS.
 */
function warnMissingIcons(): void {
  const missed = new Set(
    [...document.querySelectorAll('[data-lucide]:not(svg)')]
      .map(el => el.getAttribute('data-lucide') ?? '')
      .filter(Boolean),
  );
  if (missed.size > 0) {
    console.warn(
      `[icons] not bundled, add to USED_ICONS in src/ts/icons.ts: ${[...missed].join(', ')}`,
    );
  }
}

// heatmap.ts — SVG foot rendering, zones, tooltips, risk summary.
//
// Public API:
//   const hm = new Heatmap({ container, pressure, controls });
//   hm.setPressure({ left, right });   // either side may be null = unavailable
//   hm.destroy();
//
// The component is a pure view over pressure data: it does not know where the
// numbers come from and no longer imports PRESETS. Scenario switching is a
// mock-source concern, injected as an opaque `controls` element.
//
// Built ONCE, then updated in place. This matters: the data layer emits at
// 10 Hz, and the previous implementation rebuilt its whole subtree on every
// change. At 10 Hz that would restart the danger pulse animations every 100 ms
// (so they would never visibly run), drop the zone-detail slide-up mid-flight,
// and churn the DOM ten times a second for a two-digit text change.

import type {
  FootSide, ZoneInfo, ZoneTooltipData, FootPressure,
} from './types.js';
import {
  ZONES, FOOT_BODY_PATH, TOES,
  PRESSURE_WATCH_KPA, PRESSURE_ALERT_KPA, PRESSURE_SCALE_MAX_KPA,
  PRESSURE_RAMP_KPA, PRESSURE_LABEL_INVERT_MAX_KPA,
} from './constants.js';
import {
  pressureColor, pressureSeverity, pressureAdvice,
} from './pressureColor.js';
import { refreshIcons } from './icons.js';

const SVGNS = 'http://www.w3.org/2000/svg';

/** Neutral grey for an unavailable zone. Deliberately outside the pressure ramp
 *  and the status palette so it cannot be misread as a low reading. */
const UNAVAILABLE_FILL = '#CFC9BC';

/** Either side may be null, meaning "no usable data for this foot". */
export interface HeatmapPressure {
  left: FootPressure | null;
  right: FootPressure | null;
}

interface HeatmapOpts {
  container: HTMLElement;
  pressure: HeatmapPressure;
  /** Optional slot rendered between the zone detail and the risk summary. */
  controls?: HTMLElement;
}

interface ZoneRef {
  zone: ZoneInfo;
  group: SVGGElement;
  fill: SVGElement;
  text: SVGElement;
}

interface SideRef {
  cell: HTMLElement;
  zones: Map<string, ZoneRef>;
}

export class Heatmap {
  private container: HTMLElement;
  private controls: HTMLElement | null;
  private pressure: HeatmapPressure;
  private selected: ZoneTooltipData | null = null;

  private sides!: Record<FootSide, SideRef>;
  private riskEl!: HTMLElement;
  private detailEl: HTMLElement | null = null;

  /** Structural signature of the risk summary, so it is only rebuilt when the
   *  SET of high-risk zones changes — not when their values merely drift. */
  private riskSig = '';
  private chipRefs = new Map<string, HTMLElement>();

  constructor(opts: HeatmapOpts) {
    this.container = opts.container;
    this.controls = opts.controls ?? null;
    this.pressure = opts.pressure;
    this.build();
    this.setPressure(this.pressure);
  }

  // ─── Public ───────────────────────────────────────────────

  setPressure(p: HeatmapPressure): void {
    this.pressure = p;

    for (const side of ['left', 'right'] as FootSide[]) {
      const values = p[side];
      const ref = this.sides[side];
      ref.cell.classList.toggle('unavailable', values === null);

      for (const z of ZONES) {
        const zr = ref.zones.get(z.id)!;
        if (values === null) {
          zr.fill.setAttribute('fill', UNAVAILABLE_FILL);
          zr.text.textContent = '–';
          zr.group.classList.remove('danger', 'invert-text');
          zr.text.setAttribute('y', String(z.cy + 4));
        } else {
          const v = values[z.id];
          const isDanger = v >= PRESSURE_ALERT_KPA;
          const rounded = String(Math.round(v));
          zr.fill.setAttribute('fill', pressureColor(v));
          zr.text.textContent = rounded;
          zr.group.classList.toggle('danger', isDanger);
          zr.group.classList.toggle('invert-text', v < PRESSURE_LABEL_INVERT_MAX_KPA);
          // Font-size was already tuned once for 3-digit kPa values (see the
          // CSS comment on .zone-group.danger .zone-value — "220" measured
          // 28.3px against a 27px zone at 14px, fixed at 12px). That tuning
          // assumes the value never exceeds 3 digits, which held until a raw
          // ADC value briefly reached the heatmap during BLE debugging
          // (0-4095, up to 4 digits) and produced two adjacent zones'
          // overlapping text rendering as one garbled string. Rather than
          // re-tune a THIRD fixed size for "4 digits" and leave the same trap
          // for a 5th, this scales by digit count generally — see the
          // .wide-value / .x-wide-value rules in heatmap.css.
          zr.group.classList.toggle('wide-value', rounded.replace('-', '').length === 4);
          zr.group.classList.toggle('x-wide-value', rounded.replace('-', '').length >= 5);
          zr.text.setAttribute('y', String(z.cy + (isDanger ? 5 : 4)));
        }
      }
    }
    this.syncSelection();

    // A tapped zone whose foot just went away must not keep showing old numbers.
    if (this.selected && p[this.selected.side] === null) {
      this.closeDetail();
    } else if (this.selected) {
      const v = p[this.selected.side]![this.selected.zone.id];
      if (v !== this.selected.value) {
        this.selected = { ...this.selected, value: v };
        this.renderDetail();
      }
    }

    this.updateRiskSummary();
  }

  destroy(): void {
    this.selected = null;
    this.detailEl = null;
    this.chipRefs.clear();
    this.container.innerHTML = '';
    this.container.classList.remove('heatmap-stack');
  }

  // ─── Build (once) ─────────────────────────────────────────

  private build(): void {
    this.container.innerHTML = '';
    this.container.classList.add('heatmap-stack');

    const card = el('div', 'heatmap-card');
    card.appendChild(this.buildHead());

    const grid = el('div', 'feet-grid');
    this.sides = {
      left: this.buildFootCell('left', 'ซ้าย', 'L'),
      right: this.buildFootCell('right', 'ขวา', 'R'),
    };
    grid.append(this.sides.left.cell, this.sides.right.cell);
    card.appendChild(grid);
    card.appendChild(this.buildLegend());
    this.container.appendChild(card);

    if (this.controls) this.container.appendChild(this.controls);

    this.riskEl = el('div', 'risk-summary tone-safe');
    this.container.appendChild(this.riskEl);

    refreshIcons();
  }

  private buildHead(): HTMLElement {
    const head = el('div', 'card-head');
    const titleBlock = el('div');
    titleBlock.innerHTML = `
      <div class="th-title">แผนที่แรงกด</div>
      <div class="en-title">Foot pressure heatmap · live</div>
    `;
    const live = el('div', 'pill live');
    live.innerHTML = `<span class="dot live-dot"></span>LIVE`;
    head.append(titleBlock, live);
    return head;
  }

  private buildFootCell(side: FootSide, thLabel: string, enLabel: string): SideRef {
    const cell = el('div', 'foot-cell');
    const wrap = el('div', 'svg-wrap');
    const zones = new Map<string, ZoneRef>();
    wrap.appendChild(this.buildFootSVG(side, zones));

    // Overlay, shown by CSS only while this foot is unavailable.
    const note = el('div', 'na-note');
    note.innerHTML = `<span class="th">ไม่มีข้อมูล</span><span class="en">No data</span>`;
    wrap.appendChild(note);

    const label = el('div', 'foot-label');
    label.innerHTML = `${thLabel}<span class="side-en">· ${enLabel}</span>`;
    cell.append(wrap, label);
    return { cell, zones };
  }

  private buildFootSVG(side: FootSide, zones: Map<string, ZoneRef>): SVGSVGElement {
    const svg = svgEl('svg') as SVGSVGElement;
    svg.setAttribute('viewBox', '0 0 100 270');
    svg.setAttribute('width', '100%');
    svg.setAttribute('height', '100%');
    svg.classList.add('foot-svg');
    svg.setAttribute('aria-label', side === 'left' ? 'เท้าซ้าย' : 'เท้าขวา');

    const defs = svgEl('defs');
    const grad = svgEl('radialGradient');
    grad.id = `shade-${side}`;
    grad.setAttribute('cx', '50%'); grad.setAttribute('cy', '55%'); grad.setAttribute('r', '60%');
    const s1 = svgEl('stop'); s1.setAttribute('offset', '0%');   s1.setAttribute('stop-color', '#FFFFFF');
    const s2 = svgEl('stop'); s2.setAttribute('offset', '100%'); s2.setAttribute('stop-color', '#F1ECE0');
    grad.append(s1, s2);
    defs.appendChild(grad);
    svg.appendChild(defs);

    const g = svgEl('g');
    if (side === 'right') g.setAttribute('transform', 'translate(100,0) scale(-1,1)');

    const shadow = svgEl('ellipse');
    shadow.setAttribute('cx', '48'); shadow.setAttribute('cy', '262');
    shadow.setAttribute('rx', '38'); shadow.setAttribute('ry', '4');
    shadow.classList.add('foot-shadow');
    g.appendChild(shadow);

    const body = svgEl('path');
    body.setAttribute('d', FOOT_BODY_PATH.trim());
    body.classList.add('foot-body');
    body.setAttribute('fill', `url(#shade-${side})`);
    g.appendChild(body);

    for (const t of TOES) {
      const e = svgEl('ellipse');
      e.setAttribute('cx', String(t.cx)); e.setAttribute('cy', String(t.cy));
      e.setAttribute('rx', String(t.rx)); e.setAttribute('ry', String(t.ry));
      e.classList.add('toe-shape');
      e.setAttribute('fill', `url(#shade-${side})`);
      g.appendChild(e);
    }

    const crease = svgEl('path');
    crease.setAttribute('d', 'M 78 110 C 80 140 80 170 76 195');
    crease.classList.add('arch-crease');
    g.appendChild(crease);

    for (const z of ZONES) {
      const ref = this.buildZone(side, z);
      zones.set(z.id, ref);
      g.appendChild(ref.group);
    }

    svg.appendChild(g);
    return svg;
  }

  /**
   * Zone nodes are created once, including both pulse rings. The rings are
   * hidden by CSS unless the group carries `.danger`, so changing tier is a
   * class toggle rather than DOM surgery — which is what lets the pulse
   * animation run continuously instead of restarting on every update.
   */
  private buildZone(side: FootSide, zone: ZoneInfo): ZoneRef {
    const group = svgEl('g') as SVGGElement;
    group.classList.add('zone-group');

    for (const cls of ['pulse-ring', 'pulse-ring-2']) {
      const r = svgEl('ellipse');
      r.setAttribute('cx', String(zone.cx)); r.setAttribute('cy', String(zone.cy));
      r.setAttribute('rx', String(zone.rx)); r.setAttribute('ry', String(zone.ry));
      r.classList.add(cls);
      group.appendChild(r);
    }

    const fill = svgEl('ellipse');
    fill.setAttribute('cx', String(zone.cx)); fill.setAttribute('cy', String(zone.cy));
    fill.setAttribute('rx', String(zone.rx)); fill.setAttribute('ry', String(zone.ry));
    fill.classList.add('zone-fill');
    group.appendChild(fill);

    const labelG = svgEl('g');
    if (side === 'right') labelG.setAttribute('transform', `translate(${zone.cx * 2},0) scale(-1,1)`);
    const text = svgEl('text');
    text.setAttribute('x', String(zone.cx));
    text.setAttribute('y', String(zone.cy + 4));
    text.setAttribute('text-anchor', 'middle');
    text.classList.add('zone-value');
    labelG.appendChild(text);
    group.appendChild(labelG);

    group.addEventListener('click', (e) => {
      e.stopPropagation();
      const values = this.pressure[side];
      if (values === null) return;            // nothing to show for a dead foot
      this.selected = { side, zone, value: values[zone.id] };
      this.syncSelection();     // don't wait up to 100 ms for the next snapshot
      this.renderDetail();
    });

    return { zone, group, fill, text };
  }

  private buildLegend(): HTMLElement {
    const legend = el('div', 'legend');

    // Single source of truth for the ramp: every gradient stop and both tier
    // markers are positioned from the kPa constants, converted here to a
    // percentage of the display scale and handed to CSS as custom properties.
    const pct = (kpa: number) => `${(kpa / PRESSURE_SCALE_MAX_KPA) * 100}%`;
    legend.style.setProperty('--stop-low',        pct(PRESSURE_RAMP_KPA.low));
    legend.style.setProperty('--stop-mid',        pct(PRESSURE_RAMP_KPA.mid));
    legend.style.setProperty('--stop-watch',      pct(PRESSURE_RAMP_KPA.watch));
    legend.style.setProperty('--stop-watch-high', pct(PRESSURE_RAMP_KPA.watchHigh));
    legend.style.setProperty('--stop-alert',      pct(PRESSURE_RAMP_KPA.alert));

    legend.innerHTML = `
      <div class="bar">
        <div class="marker-label watch">${PRESSURE_WATCH_KPA} · เฝ้าระวัง</div>
        <div class="marker watch"></div>
        <div class="marker-label alert">${PRESSURE_ALERT_KPA} · อันตราย</div>
        <div class="marker alert"></div>
      </div>
      <div class="scale">
        <span>ต่ำ · 0 kPa</span>
        <span>สูง · ${PRESSURE_SCALE_MAX_KPA} kPa</span>
      </div>
    `;
    return legend;
  }

  // ─── Zone detail ──────────────────────────────────────────

  private renderDetail(): void {
    const data = this.selected;
    if (!data) return;
    const sev = pressureSeverity(data.value);
    const sideTH = data.side === 'left' ? 'เท้าซ้าย' : 'เท้าขวา';
    const sideEN = data.side === 'left' ? 'Left foot' : 'Right foot';

    if (!this.detailEl) {
      this.detailEl = el('div', 'zone-detail slide-up');
      this.container.insertBefore(this.detailEl, this.controls ?? this.riskEl);
    }
    this.detailEl.innerHTML = `
      <div class="head">
        <div class="titles">
          <div class="side">${sideTH} · ${sideEN}</div>
          <div class="th">${data.zone.labelTH}</div>
          <div class="en">${data.zone.labelEN}</div>
        </div>
        <button class="close-btn ic-sm" aria-label="ปิด">
          <i data-lucide="x"></i>
        </button>
      </div>
      <div class="severity tone-${sev.tone}">
        <div class="value num">${Math.round(data.value)}</div>
        <div>
          <div class="label">${sev.th} · ${sev.en}</div>
          <div class="sub-en">แรงกด · kPa</div>
        </div>
      </div>
      <div class="advice">${pressureAdvice(data.value)}</div>
    `;
    this.detailEl.querySelector('.close-btn')?.addEventListener('click', () => this.closeDetail());
    refreshIcons();
  }

  private closeDetail(): void {
    this.selected = null;
    this.detailEl?.remove();
    this.detailEl = null;
    this.syncSelection();
  }

  /** Mirror `selected` onto the zone groups (drives the .selected outline). */
  private syncSelection(): void {
    for (const side of ['left', 'right'] as FootSide[]) {
      for (const z of ZONES) {
        const on = !!this.selected
          && this.selected.side === side
          && this.selected.zone.id === z.id;
        this.sides[side].zones.get(z.id)!.group.classList.toggle('selected', on);
      }
    }
  }

  // ─── Risk summary ─────────────────────────────────────────

  private updateRiskSummary(): void {
    const available = (['left', 'right'] as FootSide[]).filter(s => this.pressure[s] !== null);

    const dangerZones: ZoneTooltipData[] = [];
    for (const side of available) {
      const values = this.pressure[side]!;
      for (const z of ZONES) {
        const v = values[z.id];
        if (v >= PRESSURE_ALERT_KPA) dangerZones.push({ side, zone: z, value: v });
      }
    }
    dangerZones.sort((a, b) => b.value - a.value);

    const count = dangerZones.length;
    const noData = available.length === 0;
    const partial = available.length === 1;

    const tone: 'none' | 'safe' | 'warn' | 'danger' =
      noData ? 'none' : count === 0 ? 'safe' : count <= 2 ? 'warn' : 'danger';

    let advice: string;
    if (noData) {
      advice = 'ยังไม่ได้รับข้อมูลจากอุปกรณ์ — ไม่สามารถประเมินแรงกดได้';
    } else if (count === 0) {
      advice = 'การกระจายแรงกดอยู่ในเกณฑ์ปลอดภัย เดินต่อได้ตามปกติ';
    } else if (dangerZones.every(z => z.zone.id === 'heel')) {
      advice = 'ลงส้นเท้าแรงเกินไป — ลองวางเท้าให้เต็มฝ่าและตรวจรองเท้าว่ารองรับส้นพอ';
    } else if (dangerZones.some(z => ['hallux', 'meta1', 'meta3', 'meta5'].includes(z.zone.id))) {
      advice = 'พบแรงกดสูงบริเวณเนินปลายเท้า — เสี่ยงต่อแผลกดทับ ควรพักเท้าและพิจารณาเปลี่ยนรองเท้า';
    } else {
      advice = 'พบแรงกดสูงผิดปกติ — ลดระยะการเดินและปรึกษาแพทย์หากอาการยังคงอยู่';
    }
    if (partial) advice += ' (ประเมินจากเท้าข้างเดียว · assessed from one foot only)';

    // Only the SET of high-risk zones drives a rebuild; drifting values do not.
    const sig = [tone, noData ? 'nodata' : '', partial ? 'partial' : '',
      ...dangerZones.map(d => `${d.side}:${d.zone.id}`)].join('|');

    if (sig !== this.riskSig) {
      this.riskSig = sig;
      this.riskEl.className = `risk-summary tone-${tone}`;
      const iconName = noData ? 'bluetooth' : count === 0 ? 'shield' : 'alert-triangle';
      const titleTH = noData ? 'ไม่มีข้อมูล' : count === 0 ? 'ไม่พบโซนเสี่ยง' : `${count} โซนความเสี่ยงสูง`;
      const titleEN = noData ? 'No data' : count === 0 ? 'No high-risk zones' : `${count} high-risk zones`;

      const listHTML = count > 0
        ? `<div class="danger-zone-list">` + dangerZones.map(d => `
            <div class="danger-zone-row" data-key="${d.side}:${d.zone.id}">
              <div class="chip">${Math.round(d.value)}</div>
              <div style="flex:1;min-width:0">
                <div class="name">${d.zone.labelTH} · ${d.side === 'left' ? 'ซ้าย' : 'ขวา'}</div>
                <div class="name-en">${d.zone.labelEN} · ${d.side}</div>
              </div>
            </div>`).join('') + `</div>`
        : '';

      this.riskEl.innerHTML = `
        <div class="summary-head">
          <div class="ic"><i data-lucide="${iconName}"></i></div>
          <div style="flex:1">
            <div class="text-th">${titleTH}</div>
            <div class="text-en">${titleEN}</div>
          </div>
        </div>
        ${listHTML}
        <div class="advice-block">${advice}</div>
      `;
      this.chipRefs.clear();
      this.riskEl.querySelectorAll<HTMLElement>('.danger-zone-row').forEach(row => {
        const key = row.dataset.key!;
        this.chipRefs.set(key, row.querySelector<HTMLElement>('.chip')!);
      });
      refreshIcons();
    }

    // Values drift every tick — update the chips in place rather than rebuilding.
    for (const d of dangerZones) {
      const chip = this.chipRefs.get(`${d.side}:${d.zone.id}`);
      if (!chip) continue;
      const txt = String(Math.round(d.value));
      if (chip.textContent !== txt) chip.textContent = txt;
      chip.style.background = pressureColor(d.value);
    }
  }
}

// ─── Tiny DOM helpers ──────────────────────────────────────
function el<K extends keyof HTMLElementTagNameMap>(
  tag: K, className?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  return node;
}
function svgEl(tag: string): SVGElement {
  return document.createElementNS(SVGNS, tag) as SVGElement;
}

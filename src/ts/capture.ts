// capture.ts — Research Capture screen (#/capture), an OPERATOR tool for the
// 30-volunteer study, not part of the patient-facing UI. Not a tab; reached
// only by navigating to #/capture directly. See docs/reports/010-*.md and
// docs/SmartInsole_TestProtocol_v1.md (the authoritative protocol this
// implements).
//
// Flow: subject entry -> session calibration (30s, both feet required) ->
// recording (5 gait patterns, Start/Stop per take, mark-invalid) -> export
// (CSV + metadata JSON, possible at any point). Session state persists to
// IndexedDB (capture/store.ts) so a reload mid-session is recoverable — see
// checkForInterruptedSession() below.
//
// Recording writes from deviceManager.onRawSample() (50 Hz), batched and
// flushed by capture/recorder.ts — never from onSnapshot(). See
// capture/recorder.ts's top-of-file note for why and what was measured.

import { renderStatusBar } from './navigation.js';
import { refreshIcons } from './icons.js';
import { deviceManager } from './data/DeviceManager.js';
import type { CombinedSnapshot, ConnectionState, Unsubscribe } from './data/types.js';
import { isUsable } from './data/types.js';
import type { FootSide } from './types.js';
import { FSR_CHANNEL_ORDER } from './constants.js';
import {
  GAIT_LABELS, emptySubject, emptyPatternNotes, emptyPatternCounts,
} from './capture/types.js';
import type {
  GaitLabel, Sex, SubjectInfo, SessionCalibration, SideCalibration, SessionRecord, RotationNote,
} from './capture/types.js';
import {
  getActiveSessions, putSession, countSamples, recountPatterns,
  getStorageInfo, deleteSession,
} from './capture/store.js';
import { buildSessionCsv, buildSessionMetadataJson, downloadBlob } from './capture/csv.js';
import { Recorder } from './capture/recorder.js';

// ─── Local heuristics (UI-only — not Data Contract thresholds) ────
const CALIBRATION_MS = 30_000;
/** "Should be near zero" per the protocol; not a clinical threshold (that's TEMP_DELTA_THRESHOLD = 2.2°C in constants.ts) — this is a much tighter, UI-only warn level for "does this calibration look sane." */
const CALIBRATION_DELTA_WARN_C = 0.5;
/** Protocol calls for 3 min of walking per pattern (docs/SmartInsole_TestProtocol_v1.md §4). At 50 Hz / 100-sample windows that's 90 windows — used only to paint a soft "looks sufficient" checkmark, never to block anything. */
const RECORDING_TARGET_WINDOWS = 90;

type Step = 'loading' | 'resume-prompt' | 'entry' | 'calibrating' | 'calibration-review' | 'recording' | 'ended';

// ─── Module state ──────────────────────────────────────────────
let step: Step = 'loading';
let session: SessionRecord | null = null;
let recorder: Recorder | null = null;
let unsubs: Unsubscribe[] = [];

// Entry form draft (kept separate from SubjectInfo so partially-typed numbers don't need parsing on every keystroke)
let draftSubject: SubjectInfo = emptySubject();

// Calibration accumulation
type ZoneKey = typeof FSR_CHANNEL_ORDER[number];
interface CalibAccum {
  pressureSum: Record<FootSide, Record<ZoneKey, number>>;
  pressureN: Record<FootSide, number>;
  foreSum: Record<FootSide, number>;
  foreN: Record<FootSide, number>;
  heelSum: Record<FootSide, number>;
  heelN: Record<FootSide, number>;
}
let calibAccum: CalibAccum | null = null;
let calibDeadline = 0;
let calibTimer: ReturnType<typeof setInterval> | null = null;

function freshCalibAccum(): CalibAccum {
  const zeroZones = () => Object.fromEntries(FSR_CHANNEL_ORDER.map(k => [k, 0])) as Record<ZoneKey, number>;
  return {
    pressureSum: { left: zeroZones(), right: zeroZones() },
    pressureN: { left: 0, right: 0 },
    foreSum: { left: 0, right: 0 }, foreN: { left: 0, right: 0 },
    heelSum: { left: 0, right: 0 }, heelN: { left: 0, right: 0 },
  };
}

// ─── Header ──────────────────────────────────────────────────

function renderHeader(): void {
  const host = document.getElementById('app-header');
  if (!host) return;
  const exportBtn = session
    ? `<button id="cap-header-export" class="gear-btn" aria-label="ส่งออกข้อมูล" type="button"><i data-lucide="file-down"></i></button>`
    : '';
  host.innerHTML = `
    <div class="title-block">
      <span class="eyebrow">operator only · เฉพาะผู้ดำเนินการวิจัย</span>
      <div class="title">Research Capture</div>
    </div>
    <div style="display:flex;gap:8px">
      ${exportBtn}
      <a href="#/home" class="gear-btn" aria-label="ออก"><i data-lucide="x"></i></a>
    </div>
  `;
  host.querySelector('#cap-header-export')?.addEventListener('click', () => { void runExport(); });
}

// ─── Body root ───────────────────────────────────────────────

function body(): HTMLElement | null { return document.getElementById('capture-body'); }

function setStep(next: Step): void {
  step = next;
  renderHeader();
  renderStep();
}

function renderStep(): void {
  const host = body();
  if (!host) return;
  switch (step) {
    case 'loading':           host.innerHTML = `<div class="cap-loading">กำลังตรวจสอบเซสชัน… · checking for a session…</div>`; break;
    case 'resume-prompt':      renderResumePrompt(host); break;
    case 'entry':              renderEntry(host); break;
    case 'calibrating':        renderCalibrating(host); break;
    case 'calibration-review': renderCalibrationReview(host); break;
    case 'recording':          renderRecording(host); break;
    case 'ended':              renderEnded(host); break;
  }
  refreshIcons();
}

// ─── Resume prompt ───────────────────────────────────────────

let resumeCandidate: SessionRecord | null = null;

async function checkForInterruptedSession(): Promise<void> {
  const active = await getActiveSessions();
  if (active.length === 0) { setStep('entry'); return; }
  // Most recently started, if somehow more than one.
  resumeCandidate = active.reduce((a, b) => (a.startedAtUnixMs >= b.startedAtUnixMs ? a : b));
  setStep('resume-prompt');
}

function renderResumePrompt(host: HTMLElement): void {
  const s = resumeCandidate!;
  const startedAgo = formatElapsed(Date.now() - s.startedAtUnixMs);
  host.innerHTML = `
    <div class="cap-card cap-warn">
      <div class="cap-card-title">
        <i data-lucide="alert-triangle"></i>
        <div>
          <div class="th">พบเซสชันที่ค้างอยู่</div>
          <div class="en">Interrupted session found</div>
        </div>
      </div>
      <div class="cap-kv">
        <div><span class="k">Subject</span><span class="v">${escapeHtml(s.subject.subjectId)}</span></div>
        <div><span class="k">เริ่มเมื่อ</span><span class="v">${startedAgo} ago</span></div>
        <div><span class="k">Calibration</span><span class="v">${s.calibration ? 'บันทึกแล้ว · captured' : 'ยังไม่ได้ทำ · not done'}</span></div>
      </div>
      <p class="cap-note">ข้อมูลนี้ยังไม่ได้ถูกลบ — เลือกดำเนินการต่อหรือส่งออกสิ่งที่มีอยู่ก่อน ไม่มีตัวเลือกลบทิ้งตรงนี้โดยตั้งใจ</p>
      <div class="cap-btn-row">
        <button id="resume-btn" class="cap-btn primary" type="button">ดำเนินการต่อ · Resume</button>
        <button id="resume-export-btn" class="cap-btn" type="button">ส่งออกสิ่งที่มี · Export what exists</button>
      </div>
    </div>
  `;
  host.querySelector('#resume-btn')?.addEventListener('click', () => { void resumeSession(s); });
  host.querySelector('#resume-export-btn')?.addEventListener('click', () => { void exportThenResume(s); });
}

async function resumeSession(s: SessionRecord): Promise<void> {
  session = s;
  // Recompute from the actual rows — the persisted patternCounts is only as
  // fresh as the last flush before whatever interrupted the session.
  session.patternCounts = await recountPatterns(s.sessionId);
  recorder = new Recorder(session);
  setStep(session.calibration ? 'recording' : 'calibrating');
  if (!session.calibration) beginCalibrationCountdown();
}

async function exportThenResume(s: SessionRecord): Promise<void> {
  session = s;
  await runExport();
  await resumeSession(s);
}

// ─── Subject entry ───────────────────────────────────────────

function renderEntry(host: HTMLElement): void {
  const d = draftSubject;
  host.innerHTML = `
    <div class="cap-card cap-warn">
      <div class="th">รหัสสุ่มเท่านั้น — ห้ามบันทึกชื่อ นามสกุล หรือเลขบัตรประชาชน</div>
      <div class="en">Random code only — never record name, surname, or national ID (ethics requirement)</div>
    </div>
    <div class="cap-card">
      <div class="cap-field">
        <label class="th">รหัสอาสาสมัคร · Subject code</label>
        <input id="f-subjectId" class="cap-input" type="text" placeholder="SI-001" value="${escapeAttr(d.subjectId)}" />
      </div>
      <div class="cap-grid-2">
        <div class="cap-field"><label class="th">อายุ · Age</label><input id="f-age" class="cap-input" type="number" min="0" value="${d.age ?? ''}" /></div>
        <div class="cap-field">
          <label class="th">เพศ · Sex</label>
          <div class="cap-seg" id="f-sex">
            <div class="seg ${d.sex === 'male' ? 'active' : ''}" data-v="male">ชาย</div>
            <div class="seg ${d.sex === 'female' ? 'active' : ''}" data-v="female">หญิง</div>
            <div class="seg ${d.sex === 'other' ? 'active' : ''}" data-v="other">อื่นๆ</div>
          </div>
        </div>
      </div>
      <div class="cap-grid-2">
        <div class="cap-field"><label class="th">น้ำหนัก (kg)</label><input id="f-weight" class="cap-input" type="number" step="0.1" value="${d.weightKg ?? ''}" /></div>
        <div class="cap-field"><label class="th">ส่วนสูง (cm)</label><input id="f-height" class="cap-input" type="number" step="0.1" value="${d.heightCm ?? ''}" /></div>
      </div>
      <div class="cap-grid-2">
        <div class="cap-field"><label class="th">ความยาวเท้าซ้าย (cm)</label><input id="f-footL" class="cap-input" type="number" step="0.1" value="${d.footLengthLeftCm ?? ''}" /></div>
        <div class="cap-field"><label class="th">ความยาวเท้าขวา (cm)</label><input id="f-footR" class="cap-input" type="number" step="0.1" value="${d.footLengthRightCm ?? ''}" /></div>
      </div>
      <div class="cap-field">
        <label class="th">ข้างที่ถนัด · Dominant side</label>
        <div class="cap-seg" id="f-dom">
          <div class="seg ${d.dominantSide === 'left' ? 'active' : ''}" data-v="left">ซ้าย · L</div>
          <div class="seg ${d.dominantSide === 'right' ? 'active' : ''}" data-v="right">ขวา · R</div>
        </div>
      </div>
      <div class="cap-grid-2">
        <div class="cap-field"><label class="th">อุณหภูมิห้อง (°C)</label><input id="f-room" class="cap-input" type="number" step="0.1" value="${d.roomTempC ?? ''}" /></div>
        <div class="cap-field"><label class="th">ความชื้น (%)</label><input id="f-humid" class="cap-input" type="number" step="0.1" value="${d.humidityPct ?? ''}" /></div>
      </div>
    </div>
    <div class="cap-btn-row">
      <button id="start-session-btn" class="cap-btn primary" type="button" ${d.subjectId.trim() ? '' : 'disabled'}>เริ่มเซสชัน · Start Session</button>
    </div>
  `;

  const bind = (id: string, key: keyof SubjectInfo, parse: (v: string) => unknown) => {
    host.querySelector<HTMLInputElement>(`#${id}`)?.addEventListener('input', e => {
      (draftSubject as unknown as Record<string, unknown>)[key] = parse((e.target as HTMLInputElement).value);
      const btn = host.querySelector<HTMLButtonElement>('#start-session-btn');
      if (btn) btn.disabled = !draftSubject.subjectId.trim();
    });
  };
  bind('f-subjectId', 'subjectId', v => v);
  bind('f-age', 'age', v => (v === '' ? null : Number(v)));
  bind('f-weight', 'weightKg', v => (v === '' ? null : Number(v)));
  bind('f-height', 'heightCm', v => (v === '' ? null : Number(v)));
  bind('f-footL', 'footLengthLeftCm', v => (v === '' ? null : Number(v)));
  bind('f-footR', 'footLengthRightCm', v => (v === '' ? null : Number(v)));
  bind('f-room', 'roomTempC', v => (v === '' ? null : Number(v)));
  bind('f-humid', 'humidityPct', v => (v === '' ? null : Number(v)));

  host.querySelector('#f-sex')?.querySelectorAll('.seg').forEach(el => {
    el.addEventListener('click', () => {
      draftSubject.sex = (el as HTMLElement).dataset.v as Sex;
      host.querySelector('#f-sex')!.querySelectorAll('.seg').forEach(x => x.classList.toggle('active', x === el));
    });
  });
  host.querySelector('#f-dom')?.querySelectorAll('.seg').forEach(el => {
    el.addEventListener('click', () => {
      draftSubject.dominantSide = (el as HTMLElement).dataset.v as FootSide;
      host.querySelector('#f-dom')!.querySelectorAll('.seg').forEach(x => x.classList.toggle('active', x === el));
    });
  });

  host.querySelector('#start-session-btn')?.addEventListener('click', () => { void startSession(); });
}

async function startSession(): Promise<void> {
  const subjectId = draftSubject.subjectId.trim();
  if (!subjectId) return;
  const sessionId = `${subjectId}-${Date.now()}`;
  session = {
    sessionId,
    subject: { ...draftSubject, subjectId },
    calibration: null,
    notes: emptyPatternNotes(),
    startedAtUnixMs: Date.now(),
    endedAtUnixMs: null,
    exportedAtUnixMs: null,
    patternCounts: emptyPatternCounts(),
  };
  await putSession(session);
  recorder = new Recorder(session);
  draftSubject = emptySubject();
  setStep('calibrating');
  beginCalibrationCountdown();
}

// ─── Session calibration ─────────────────────────────────────

function bothConnected(): boolean {
  return deviceManager.getStateOf('left') === 'connected' && deviceManager.getStateOf('right') === 'connected';
}

function renderCalibrating(host: HTMLElement): void {
  const left = deviceManager.getStateOf('left');
  const right = deviceManager.getStateOf('right');
  const running = calibTimer !== null;
  const missing: string[] = [];
  if (left !== 'connected') missing.push('ซ้าย · left');
  if (right !== 'connected') missing.push('ขวา · right');

  host.innerHTML = `
    <div class="cap-card">
      <div class="cap-card-title">
        <div>
          <div class="th">การตั้งค่าฐานของเซสชัน</div>
          <div class="en">Session calibration — stand still, weight even on both feet</div>
        </div>
      </div>
      ${missing.length && !running
        ? `<div class="cap-blocker"><i data-lucide="bluetooth"></i> ยังไม่เชื่อมต่อ: ${missing.join(', ')} · not connected: ${missing.join(', ')}</div>`
        : ''}
      <div class="cap-countdown ${running ? 'active' : ''}" id="cap-countdown">${running ? secondsLeft() : '30'}</div>
      <div class="cap-btn-row">
        <button id="calib-start-btn" class="cap-btn primary" type="button" ${(!bothConnected() || running) ? 'disabled' : ''}>
          เริ่มนับถอยหลัง 30 วินาที · Start 30s countdown
        </button>
      </div>
    </div>
  `;
  host.querySelector('#calib-start-btn')?.addEventListener('click', () => { void runCalibrationCountdown(); });
}

function secondsLeft(): number { return Math.max(0, Math.ceil((calibDeadline - Date.now()) / 1000)); }

function beginCalibrationCountdown(): void {
  // Just render the gate; the operator presses Start once both sides show connected.
  unsubs.push(deviceManager.onSnapshot(() => {
    if (step === 'calibrating' && calibTimer === null) renderCalibrating(body()!);
  }));
}

async function runCalibrationCountdown(): Promise<void> {
  if (!bothConnected() || calibTimer !== null) return;
  calibAccum = freshCalibAccum();
  calibDeadline = Date.now() + CALIBRATION_MS;

  const collect = (snap: CombinedSnapshot) => {
    if (!calibAccum) return;
    for (const side of ['left', 'right'] as FootSide[]) {
      const s = side === 'left' ? snap.left : snap.right;
      if (!isUsable(s) || !s.pressure) continue;
      for (const zone of FSR_CHANNEL_ORDER) calibAccum.pressureSum[side][zone] += s.pressure[zone];
      calibAccum.pressureN[side]++;
      if (s.temp && s.temp.quality === 0) {   // quality 0 = normal reading (see docs/reports/011-*.md); was inverted
        if (s.temp.forefootC !== null) { calibAccum.foreSum[side] += s.temp.forefootC; calibAccum.foreN[side]++; }
        if (s.temp.heelC !== null) { calibAccum.heelSum[side] += s.temp.heelC; calibAccum.heelN[side]++; }
      }
    }
  };
  const collectUnsub = deviceManager.onSnapshot(collect);

  calibTimer = setInterval(() => {
    const el = document.getElementById('cap-countdown');
    if (el) el.textContent = String(secondsLeft());
    if (Date.now() >= calibDeadline) {
      collectUnsub();
      if (calibTimer) { clearInterval(calibTimer); calibTimer = null; }
      void finishCalibration();
    }
  }, 250);
  renderCalibrating(body()!);
}

async function finishCalibration(): Promise<void> {
  if (!calibAccum || !session) return;
  const a = calibAccum;
  const sideResult = (side: FootSide) => {
    let restingKpa: SideCalibration['restingKpa'] = null;
    if (a.pressureN[side] > 0) {
      const entries = FSR_CHANNEL_ORDER.map(z => [z, a.pressureSum[side][z] / a.pressureN[side]] as const);
      restingKpa = Object.fromEntries(entries) as NonNullable<SideCalibration['restingKpa']>;
    }
    const forefootC = a.foreN[side] > 0 ? a.foreSum[side] / a.foreN[side] : null;
    const heelC = a.heelN[side] > 0 ? a.heelSum[side] / a.heelN[side] : null;
    return { restingKpa, forefootC, heelC };
  };
  const left = sideResult('left');
  const right = sideResult('right');
  const startingDeltaTC = (left.forefootC !== null && right.forefootC !== null)
    ? Math.abs(left.forefootC - right.forefootC) : null;

  session.calibration = { capturedAtUnixMs: Date.now(), left, right, startingDeltaTC };
  await putSession(session);
  calibAccum = null;
  setStep('calibration-review');
}

function renderCalibrationReview(host: HTMLElement): void {
  const c = session!.calibration!;
  const warnDelta = c.startingDeltaTC !== null && c.startingDeltaTC > CALIBRATION_DELTA_WARN_C;

  const sideBlock = (label: string, s: SideCalibration) => `
    <div class="cap-calib-side">
      <div class="cap-calib-side-title">${label}</div>
      ${s.restingKpa
        ? `<table class="cap-table">${FSR_CHANNEL_ORDER.map(z => `<tr><td>${z}</td><td class="num">${s.restingKpa![z].toFixed(1)} kPa</td></tr>`).join('')}</table>`
        : `<div class="cap-nodata">ไม่มีข้อมูล · no data</div>`}
      <div class="cap-calib-temp">อุณหภูมิ: ${s.forefootC !== null ? s.forefootC.toFixed(2) + '°C (forefoot)' : '—'} · ${s.heelC !== null ? s.heelC.toFixed(2) + '°C (heel)' : '—'}</div>
    </div>
  `;

  host.innerHTML = `
    <div class="cap-card">
      <div class="cap-card-title">
        <div>
          <div class="th">ผลการตั้งค่าฐาน — ตรวจสอบก่อนดำเนินการต่อ</div>
          <div class="en">Calibration baseline — sanity-check before continuing</div>
        </div>
      </div>
      ${warnDelta
        ? `<div class="cap-warn-inline"><i data-lucide="alert-triangle"></i> ΔT เริ่มต้น ${c.startingDeltaTC!.toFixed(2)}°C ไม่ใกล้ศูนย์ — บันทึกไว้แล้ว ไม่ปิดกั้นการดำเนินการต่อ · starting ΔT is not near zero — recorded, not blocking</div>`
        : `<div class="cap-ok-inline"><i data-lucide="check"></i> ΔT เริ่มต้น ${c.startingDeltaTC !== null ? c.startingDeltaTC.toFixed(2) + '°C' : 'ไม่มีข้อมูล'}</div>`}
      <div class="cap-calib-grid">
        ${sideBlock('ซ้าย · L', c.left)}
        ${sideBlock('ขวา · R', c.right)}
      </div>
    </div>
    <div class="cap-btn-row">
      <button id="calib-redo-btn" class="cap-btn" type="button"><i data-lucide="refresh-ccw"></i> ทำใหม่ · Redo</button>
      <button id="calib-confirm-btn" class="cap-btn primary" type="button">ยืนยันและไปต่อ · Confirm & Continue</button>
    </div>
  `;
  host.querySelector('#calib-redo-btn')?.addEventListener('click', () => setStep('calibrating'));
  host.querySelector('#calib-confirm-btn')?.addEventListener('click', () => setStep('recording'));
}

// ─── Recording ─────────────────────────────────────────────────

let takeStartedAtMs: number | null = null;
let recBuilt = false;
let recEls: {
  timer: HTMLElement | null; invalidBtn: HTMLElement | null; invalidList: HTMLElement | null;
  startStopBtn: HTMLElement | null; connL: HTMLElement | null; connR: HTMLElement | null;
  patternRows: Partial<Record<GaitLabel, { left: HTMLElement; right: HTMLElement; check: HTMLElement }>>;
  extraField: HTMLElement | null; storage: HTMLElement | null;
} = { timer: null, invalidBtn: null, invalidList: null, startStopBtn: null, connL: null, connR: null, patternRows: {}, extraField: null, storage: null };
let lastInvalidCount = -1;

function renderRecording(host: HTMLElement): void {
  const label = recorder!.getLabel();
  host.innerHTML = `
    <div class="cap-card">
      <div class="cap-kv">
        <div><span class="k">Subject</span><span class="v">${escapeHtml(session!.subject.subjectId)}</span></div>
        <div><span class="k">เชื่อมต่อ</span><span class="v"><span id="cap-conn-l"></span> &nbsp; <span id="cap-conn-r"></span></span></div>
      </div>
    </div>
    <div class="cap-card">
      <div class="cap-card-title"><div class="th">รูปแบบการเดิน · Gait pattern</div></div>
      <div class="cap-pattern-grid" id="cap-pattern-grid">
        ${GAIT_LABELS.map(g => `
          <button type="button" class="cap-pattern-btn ${g.id === label ? 'active' : ''}" data-label="${g.id}">
            <span class="th">${g.th}</span><span class="en">${g.en}</span>
          </button>
        `).join('')}
      </div>
      <div id="cap-extra-field"></div>
    </div>
    <div class="cap-card">
      <div class="cap-timer" id="cap-timer">00:00</div>
      <div class="cap-btn-row">
        <button id="cap-startstop-btn" class="cap-btn primary big" type="button"><i data-lucide="play"></i> เริ่มบันทึก · Start</button>
      </div>
      <button id="cap-invalid-btn" class="cap-invalid-btn" type="button" disabled>
        <i data-lucide="alert-triangle"></i> ทำเครื่องหมายช่วงนี้ใช้ไม่ได้ · Mark segment invalid
      </button>
      <div class="cap-invalid-list" id="cap-invalid-list"></div>
    </div>
    <div class="cap-card">
      <div class="cap-card-title"><div class="th">ความคืบหน้าแต่ละรูปแบบ · Per-pattern progress</div></div>
      <div class="cap-progress-list" id="cap-progress-list">
        ${GAIT_LABELS.map(g => `
          <div class="cap-progress-row" data-label="${g.id}">
            <span class="cap-progress-check" data-check></span>
            <span class="cap-progress-name">${g.th} · ${g.en}</span>
            <span class="cap-progress-count" data-left></span>
            <span class="cap-progress-count" data-right></span>
          </div>
        `).join('')}
      </div>
    </div>
    <div class="cap-card">
      <div class="cap-card-title"><div class="th">ส่งออก & พื้นที่จัดเก็บ · Export & storage</div></div>
      <div id="cap-storage" class="cap-note">กำลังตรวจสอบ…</div>
      <div class="cap-btn-row">
        <button id="cap-export-btn" class="cap-btn primary" type="button"><i data-lucide="file-down"></i> ส่งออกเซสชันนี้ · Export session</button>
      </div>
      <div class="cap-btn-row">
        <button id="cap-end-btn" class="cap-btn" type="button">จบเซสชัน · End session</button>
        <button id="cap-delete-btn" class="cap-btn danger" type="button" disabled>ลบข้อมูลเซสชันนี้ · Delete session data</button>
      </div>
      <div class="cap-note" id="cap-delete-hint">ต้องส่งออกก่อนจึงจะลบได้ · export first to enable delete</div>
    </div>
  `;

  recEls = {
    timer: host.querySelector('#cap-timer'),
    invalidBtn: host.querySelector('#cap-invalid-btn'),
    invalidList: host.querySelector('#cap-invalid-list'),
    startStopBtn: host.querySelector('#cap-startstop-btn'),
    connL: host.querySelector('#cap-conn-l'),
    connR: host.querySelector('#cap-conn-r'),
    patternRows: {},
    extraField: host.querySelector('#cap-extra-field'),
    storage: host.querySelector('#cap-storage'),
  };
  host.querySelectorAll<HTMLElement>('.cap-progress-row').forEach(row => {
    const l = row.dataset.label as GaitLabel;
    recEls.patternRows[l] = {
      left: row.querySelector('[data-left]')!,
      right: row.querySelector('[data-right]')!,
      check: row.querySelector('[data-check]')!,
    };
  });
  recBuilt = true;
  lastInvalidCount = -1;

  host.querySelectorAll<HTMLElement>('.cap-pattern-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (recorder!.isRecording()) return;
      recorder!.setLabel(btn.dataset.label as GaitLabel);
      host.querySelectorAll('.cap-pattern-btn').forEach(b => b.classList.toggle('active', b === btn));
      renderExtraField();
      updateStartEnabled();
    });
  });
  host.querySelector('#cap-startstop-btn')?.addEventListener('click', () => toggleStartStop());
  host.querySelector('#cap-invalid-btn')?.addEventListener('click', () => {
    recorder!.toggleInvalid();
    updateInvalidButton();
    // Force the list to redraw now, not just on the next onSnapshot tick's
    // length-based check — closing a span only mutates the last entry's
    // endMs, which doesn't change the array's length, so without this the
    // just-closed span's duration would stay stuck showing "in progress"
    // until some LATER length change happened to redraw it.
    lastInvalidCount = -1;
    updateInvalidList();
  });
  host.querySelector('#cap-export-btn')?.addEventListener('click', () => { void runExport(); });
  host.querySelector('#cap-end-btn')?.addEventListener('click', () => { void endSession(); });
  host.querySelector('#cap-delete-btn')?.addEventListener('click', () => { void handleDeleteClick(); });

  renderExtraField();
  updateStartEnabled();
  updateProgressList();
  void refreshStorageInfo();
}

/** antalgic needs affectedSide, rotated_foot needs the in/out-toeing note, chosen once per session. */
function renderExtraField(): void {
  const el = recEls.extraField;
  if (!el) return;
  const label = recorder!.getLabel();
  if (label === 'antalgic') {
    const cur = session!.notes.antalgicAffectedSide;
    el.innerHTML = `
      <div class="cap-field">
        <label class="th">ข้างที่แกล้งเจ็บ (จำเป็น) · Affected side (required)</label>
        <div class="cap-seg" id="cap-affected-side">
          <div class="seg ${cur === 'left' ? 'active' : ''}" data-v="left">ซ้าย · L</div>
          <div class="seg ${cur === 'right' ? 'active' : ''}" data-v="right">ขวา · R</div>
        </div>
      </div>
    `;
    el.querySelectorAll('.seg').forEach(s => s.addEventListener('click', () => {
      session!.notes.antalgicAffectedSide = (s as HTMLElement).dataset.v as FootSide;
      void putSession(session!);
      el.querySelectorAll('.seg').forEach(x => x.classList.toggle('active', x === s));
      updateStartEnabled();
    }));
  } else if (label === 'rotated_foot') {
    const cur = session!.notes.rotatedFootNote;
    el.innerHTML = `
      <div class="cap-field">
        <label class="th">บิดเข้าใน/บิดออกนอก (จำเป็น) · in-toeing / out-toeing (required)</label>
        <div class="cap-seg" id="cap-rotation-note">
          <div class="seg ${cur === 'in-toeing' ? 'active' : ''}" data-v="in-toeing">In-toeing</div>
          <div class="seg ${cur === 'out-toeing' ? 'active' : ''}" data-v="out-toeing">Out-toeing</div>
        </div>
      </div>
    `;
    el.querySelectorAll('.seg').forEach(s => s.addEventListener('click', () => {
      session!.notes.rotatedFootNote = (s as HTMLElement).dataset.v as RotationNote;
      void putSession(session!);
      el.querySelectorAll('.seg').forEach(x => x.classList.toggle('active', x === s));
      updateStartEnabled();
    }));
  } else {
    el.innerHTML = '';
  }
}

function extraFieldSatisfied(): boolean {
  const label = recorder!.getLabel();
  if (label === 'antalgic') return session!.notes.antalgicAffectedSide !== null;
  if (label === 'rotated_foot') return session!.notes.rotatedFootNote !== null;
  return true;
}

function updateStartEnabled(): void {
  const btn = recEls.startStopBtn as HTMLButtonElement | null;
  if (!btn || recorder!.isRecording()) return;
  btn.disabled = !extraFieldSatisfied();
}

function toggleStartStop(): void {
  if (!recorder) return;
  if (!recorder.isRecording()) {
    if (!extraFieldSatisfied()) return;
    recorder.start();
    takeStartedAtMs = Date.now();
    setBtnHtml(recEls.startStopBtn, '<i data-lucide="square"></i> หยุด · Stop', true);
    refreshIcons();
    if (recEls.invalidBtn) (recEls.invalidBtn as HTMLButtonElement).disabled = false;
    host_disablePatternButtons(true);
  } else {
    recorder.stop();
    takeStartedAtMs = null;
    setBtnHtml(recEls.startStopBtn, '<i data-lucide="play"></i> เริ่มบันทึก · Start', false);
    refreshIcons();
    if (recEls.invalidBtn) (recEls.invalidBtn as HTMLButtonElement).disabled = true;
    updateInvalidButton();
    host_disablePatternButtons(false);
    void putSession(session!);   // persist the take's final counts promptly, not just on next flush tick
  }
}

function host_disablePatternButtons(disabled: boolean): void {
  body()?.querySelectorAll<HTMLButtonElement>('.cap-pattern-btn').forEach(b => { b.disabled = disabled; });
}

function setBtnHtml(el: HTMLElement | null, html: string, danger: boolean): void {
  if (!el) return;
  el.innerHTML = html;
  el.classList.toggle('recording', danger);
}

function updateInvalidButton(): void {
  const btn = recEls.invalidBtn;
  if (!btn) return;
  const active = recorder!.isInvalidActive();
  btn.classList.toggle('active', active);
  btn.innerHTML = active
    ? '<i data-lucide="alert-triangle"></i> กำลังทำเครื่องหมาย… กดเพื่อหยุด · Marking… tap to stop'
    : '<i data-lucide="alert-triangle"></i> ทำเครื่องหมายช่วงนี้ใช้ไม่ได้ · Mark segment invalid';
  refreshIcons();
}

function updateInvalidList(): void {
  const el = recEls.invalidList;
  if (!el) return;
  const intervals = recorder!.invalidIntervals;
  if (intervals.length === lastInvalidCount) return;
  lastInvalidCount = intervals.length;
  if (intervals.length === 0) { el.innerHTML = ''; return; }
  el.innerHTML = intervals.map(iv => {
    const dur = ((iv.endMs ?? Date.now()) - iv.startMs) / 1000;
    return `<div class="cap-invalid-entry">ช่วงที่ทำเครื่องหมาย: ${dur.toFixed(1)}s ${iv.endMs === null ? '(กำลังดำเนินอยู่)' : ''}</div>`;
  }).join('');
}

function updateProgressList(): void {
  for (const g of GAIT_LABELS) {
    const els = recEls.patternRows[g.id];
    if (!els) continue;
    const w = recorder!.windowCount(g.id);
    els.left.textContent = `L ${w.left}w`;
    els.right.textContent = `R ${w.right}w`;
    const done = w.left >= RECORDING_TARGET_WINDOWS && w.right >= RECORDING_TARGET_WINDOWS;
    els.check.textContent = done ? '✓' : '·';
    els.check.classList.toggle('done', done);
  }
}

function updateConnBadges(snap: CombinedSnapshot): void {
  const paint = (el: HTMLElement | null, side: 'L' | 'R', state: ConnectionState | undefined) => {
    if (!el) return;
    const s = state ?? 'disconnected';
    el.className = `cap-conn-dot state-${s}`;
    el.textContent = `${side}: ${s}`;
  };
  paint(recEls.connL, 'L', snap.left?.state);
  paint(recEls.connR, 'R', snap.right?.state);
}

function tickRecording(snap: CombinedSnapshot): void {
  if (!recBuilt || step !== 'recording') return;
  if (recEls.timer) {
    recEls.timer.textContent = takeStartedAtMs !== null ? formatElapsed(Date.now() - takeStartedAtMs) : '00:00';
  }
  updateConnBadges(snap);
  updateProgressList();
  updateInvalidList();
}

async function refreshStorageInfo(): Promise<void> {
  const info = await getStorageInfo();
  const el = recEls.storage;
  if (!el) return;
  if (info.usageBytes === null || info.quotaBytes === null) {
    el.textContent = 'ไม่สามารถประมาณพื้นที่จัดเก็บได้ในเบราว์เซอร์นี้ · storage estimate unavailable';
    return;
  }
  const pct = info.quotaBytes > 0 ? (info.usageBytes / info.quotaBytes) * 100 : 0;
  const warn = pct > 70;
  el.innerHTML = `ใช้ไปแล้ว ${formatBytes(info.usageBytes)} จาก ${formatBytes(info.quotaBytes)} (${pct.toFixed(1)}%)`;
  el.classList.toggle('cap-warn-text', warn);
  if (warn) el.innerHTML += `<br><span class="cap-warn-text"><i data-lucide="alert-triangle"></i> ใกล้เต็มพื้นที่จัดเก็บ — ส่งออกและลบข้อมูลเก่าโดยเร็ว · nearing storage quota — export and delete promptly</span>`;
  refreshIcons();
}

let deleteConfirmArmed = false;
let deleteConfirmTimer: ReturnType<typeof setTimeout> | null = null;

async function handleDeleteClick(): Promise<void> {
  const btn = body()?.querySelector<HTMLButtonElement>('#cap-delete-btn');
  if (!btn || btn.disabled) return;
  if (!deleteConfirmArmed) {
    deleteConfirmArmed = true;
    btn.textContent = 'แน่ใจ? กดอีกครั้งเพื่อลบ · Confirm? tap again to delete';
    deleteConfirmTimer = setTimeout(() => {
      deleteConfirmArmed = false;
      btn.textContent = 'ลบข้อมูลเซสชันนี้ · Delete session data';
    }, 4000);
    return;
  }
  if (deleteConfirmTimer) clearTimeout(deleteConfirmTimer);
  deleteConfirmArmed = false;
  await deleteSession(session!.sessionId);
  session = null;
  recorder?.dispose();
  recorder = null;
  setStep('entry');
}

// ─── Export ──────────────────────────────────────────────────

async function runExport(): Promise<void> {
  if (!session) return;
  const count = await countSamples(session.sessionId);
  const csvBlob = await buildSessionCsv(session.sessionId);
  const jsonBlob = buildSessionMetadataJson(session, count);
  downloadBlob(csvBlob, `${session.sessionId}_samples.csv`);
  downloadBlob(jsonBlob, `${session.sessionId}_metadata.json`);
  session.exportedAtUnixMs = Date.now();
  await putSession(session);
  const delBtn = body()?.querySelector<HTMLButtonElement>('#cap-delete-btn');
  const hint = body()?.querySelector<HTMLElement>('#cap-delete-hint');
  if (delBtn) delBtn.disabled = false;
  if (hint) hint.textContent = `ส่งออกล่าสุด: ${new Date(session.exportedAtUnixMs).toLocaleTimeString('th-TH')}`;
}

async function endSession(): Promise<void> {
  if (!session) return;
  session.endedAtUnixMs = Date.now();
  await putSession(session);
  setStep('ended');
}

function renderEnded(host: HTMLElement): void {
  host.innerHTML = `
    <div class="cap-card">
      <div class="cap-card-title">
        <i data-lucide="check"></i>
        <div>
          <div class="th">จบเซสชันแล้ว</div>
          <div class="en">Session ended</div>
        </div>
      </div>
      <p class="cap-note">อย่าลืมส่งออก CSV + JSON หากยังไม่ได้ทำ ก่อนเริ่มอาสาสมัครคนถัดไป · Export CSV + JSON if you haven't yet, before starting the next subject.</p>
      <div class="cap-btn-row">
        <button id="cap-export-again-btn" class="cap-btn primary" type="button"><i data-lucide="file-down"></i> ส่งออกอีกครั้ง · Export again</button>
      </div>
      <div class="cap-btn-row">
        <button id="cap-new-btn" class="cap-btn" type="button">เริ่มอาสาสมัครคนถัดไป · Start next subject</button>
      </div>
    </div>
  `;
  host.querySelector('#cap-export-again-btn')?.addEventListener('click', () => { void runExport(); });
  host.querySelector('#cap-new-btn')?.addEventListener('click', () => {
    session = null;
    recorder?.dispose();
    recorder = null;
    draftSubject = emptySubject();
    setStep('entry');
  });
}

// ─── Formatting helpers ────────────────────────────────────────

function formatElapsed(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}
function escapeAttr(s: string): string { return escapeHtml(s); }

// ─── Lifecycle ───────────────────────────────────────────────

export function mount(): void {
  renderStatusBar();
  step = 'loading';
  session = null;
  recorder = null;
  draftSubject = emptySubject();
  recBuilt = false;
  takeStartedAtMs = null;
  unsubs = [];

  renderHeader();
  renderStep();

  unsubs.push(deviceManager.onSnapshot(snap => {
    if (step === 'recording') tickRecording(snap);
  }));

  void checkForInterruptedSession();
}

export function unmount(): void {
  unsubs.forEach(u => u());
  unsubs = [];
  if (calibTimer) { clearInterval(calibTimer); calibTimer = null; }
  calibAccum = null;
  recorder?.dispose();
  recorder = null;
  session = null;
  recBuilt = false;
  recEls = { timer: null, invalidBtn: null, invalidList: null, startStopBtn: null, connL: null, connR: null, patternRows: {}, extraField: null, storage: null };
  if (deleteConfirmTimer) { clearTimeout(deleteConfirmTimer); deleteConfirmTimer = null; }
  deleteConfirmArmed = false;
  // Everything else lives inside #view and is discarded by the router.
}

// capture/store.ts — IndexedDB persistence for research capture mode.
//
// Two object stores:
//   `sessions` — one record per subject visit (keyPath sessionId). Small,
//                read/written whole.
//   `samples`  — one row per sample per side (autoIncrement key), indexed by
//                sessionId so a session's rows can be streamed out for CSV
//                export or deleted without touching any other session's data.
//
// Why IndexedDB and not memory: a 45-minute session lost to one accidental
// refresh is a subject who does not come back (see docs/reports/010-*.md).
// Every write here is batched by the caller (capture/recorder.ts) — this
// module does not throttle or debounce on its own, it just persists what it
// is given, in one transaction per call.

import { emptyPatternCounts } from './types.js';
import type { SessionRecord, SampleRow, GaitLabel } from './types.js';

const DB_NAME = 'smart-insole-capture';
const DB_VERSION = 1;
const SESSIONS_STORE = 'sessions';
const SAMPLES_STORE = 'samples';
const SAMPLES_SESSION_INDEX = 'bySessionId';

let dbPromise: Promise<IDBDatabase> | null = null;

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(SESSIONS_STORE)) {
        db.createObjectStore(SESSIONS_STORE, { keyPath: 'sessionId' });
      }
      if (!db.objectStoreNames.contains(SAMPLES_STORE)) {
        const samples = db.createObjectStore(SAMPLES_STORE, { keyPath: 'id', autoIncrement: true });
        samples.createIndex(SAMPLES_SESSION_INDEX, 'sessionId', { unique: false });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function reqToPromise<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function txDone(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

// ─── Sessions ────────────────────────────────────────────────────

export async function putSession(session: SessionRecord): Promise<void> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS_STORE, 'readwrite');
  tx.objectStore(SESSIONS_STORE).put(session);
  await txDone(tx);
}

export async function getSession(sessionId: string): Promise<SessionRecord | null> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS_STORE, 'readonly');
  const result = await reqToPromise(tx.objectStore(SESSIONS_STORE).get(sessionId));
  return (result as SessionRecord | undefined) ?? null;
}

/**
 * A session with endedAtUnixMs === null means the app never got a clean
 * Stop/End — a reload, a crash, a closed tab mid-recording. At most one of
 * these should exist at a time since this app records one subject at a
 * time, but this returns all of them defensively rather than assuming that.
 */
export async function getActiveSessions(): Promise<SessionRecord[]> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS_STORE, 'readonly');
  const all = (await reqToPromise(tx.objectStore(SESSIONS_STORE).getAll())) as SessionRecord[];
  return all.filter(s => s.endedAtUnixMs === null);
}

export async function listSessions(): Promise<SessionRecord[]> {
  const db = await openDb();
  const tx = db.transaction(SESSIONS_STORE, 'readonly');
  return (await reqToPromise(tx.objectStore(SESSIONS_STORE).getAll())) as SessionRecord[];
}

// ─── Samples ─────────────────────────────────────────────────────

/** Batched write — one transaction for the whole buffer, not one per row. */
export async function appendSamples(rows: SampleRow[]): Promise<void> {
  if (rows.length === 0) return;
  const db = await openDb();
  const tx = db.transaction(SAMPLES_STORE, 'readwrite');
  const store = tx.objectStore(SAMPLES_STORE);
  for (const row of rows) store.add(row);
  await txDone(tx);
}

/**
 * Streams every sample row for a session to `onRow`, oldest first, via a
 * cursor rather than loading the whole session into memory at once — a
 * 45-minute session is ~270k rows (docs/reports/010-*.md), and CSV export
 * should not require holding all of them as JS objects simultaneously.
 */
export async function streamSamples(sessionId: string, onRow: (row: SampleRow) => void): Promise<number> {
  const db = await openDb();
  const tx = db.transaction(SAMPLES_STORE, 'readonly');
  const index = tx.objectStore(SAMPLES_STORE).index(SAMPLES_SESSION_INDEX);
  let count = 0;
  await new Promise<void>((resolve, reject) => {
    const req = index.openCursor(IDBKeyRange.only(sessionId));
    req.onsuccess = () => {
      const cursor = req.result;
      if (!cursor) { resolve(); return; }
      onRow(cursor.value as SampleRow);
      count++;
      cursor.continue();
    };
    req.onerror = () => reject(req.error);
  });
  return count;
}

export async function countSamples(sessionId: string): Promise<number> {
  const db = await openDb();
  const tx = db.transaction(SAMPLES_STORE, 'readonly');
  const index = tx.objectStore(SAMPLES_STORE).index(SAMPLES_SESSION_INDEX);
  return reqToPromise(index.count(IDBKeyRange.only(sessionId)));
}

/** Deletes a session's record AND all its sample rows. Never called automatically — see capture.ts's delete-after-export gating. */
export async function deleteSession(sessionId: string): Promise<void> {
  const db = await openDb();

  const sampleTx = db.transaction(SAMPLES_STORE, 'readwrite');
  const index = sampleTx.objectStore(SAMPLES_STORE).index(SAMPLES_SESSION_INDEX);
  await new Promise<void>((resolve, reject) => {
    const req = index.openKeyCursor(IDBKeyRange.only(sessionId));
    req.onsuccess = () => {
      const cursor = req.result;
      if (!cursor) { resolve(); return; }
      sampleTx.objectStore(SAMPLES_STORE).delete(cursor.primaryKey);
      cursor.continue();
    };
    req.onerror = () => reject(req.error);
  });
  await txDone(sampleTx);

  const sessionTx = db.transaction(SESSIONS_STORE, 'readwrite');
  sessionTx.objectStore(SESSIONS_STORE).delete(sessionId);
  await txDone(sessionTx);
}

// ─── Storage estimate ──────────────────────────────────────────────

export interface StorageInfo {
  usageBytes: number | null;
  quotaBytes: number | null;
}

/** navigator.storage.estimate() is unsupported on some browsers — null fields mean "unknown", not "zero". */
export async function getStorageInfo(): Promise<StorageInfo> {
  if (!navigator.storage || !navigator.storage.estimate) {
    return { usageBytes: null, quotaBytes: null };
  }
  try {
    const est = await navigator.storage.estimate();
    return { usageBytes: est.usage ?? null, quotaBytes: est.quota ?? null };
  } catch {
    return { usageBytes: null, quotaBytes: null };
  }
}

/**
 * Recompute per-pattern, per-side counts by scanning a session's rows — used
 * only to rebuild the display after a reload finds an interrupted session;
 * live recording tracks counts in memory instead (see capture/recorder.ts).
 *
 * Seeded from emptyPatternCounts() so every GaitLabel key is always present,
 * even ones with zero rows — Recorder.windowCount() indexes this object
 * directly for whichever pattern is currently selected, and a missing key
 * throws rather than reading as zero. A session resumed before every
 * pattern had been recorded once hit exactly that: the object built from
 * only the rows seen so far omitted the untouched patterns entirely.
 */
export async function recountPatterns(sessionId: string): Promise<Record<GaitLabel, { left: number; right: number }>> {
  const counts = emptyPatternCounts();
  await streamSamples(sessionId, row => {
    const c = counts[row.gaitLabel];
    if (row.side === 'L') c.left++; else c.right++;
  });
  return counts;
}

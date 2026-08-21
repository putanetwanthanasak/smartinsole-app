// capture/csv.ts — CSV + metadata JSON export for research capture mode.
//
// Column order is CSV_COLUMNS from capture/types.ts, used explicitly rather
// than trusting object key order — this schema is parsed by name by an
// external Python training pipeline (docs/reports/010-*.md); do not change
// it here without checking with that pipeline's owner.

import { CSV_COLUMNS } from './types.js';
import type { SampleRow, SessionRecord } from './types.js';
import { streamSamples } from './store.js';

/**
 * isValid is written as the literal strings "true"/"false" (not 1/0, not
 * Python's "True"/"False") — the most interoperable encoding across a CSV
 * reader that doesn't already know this column is boolean. Documented here
 * because it was a real choice, not an obvious one — see docs/reports/010-*.md.
 */
function csvCell(v: string | number | boolean): string {
  const s = typeof v === 'boolean' ? String(v) : String(v);
  // Quote only if needed — none of these columns contain commas or quotes in
  // practice (numbers, 'L'/'R', the fixed gait-label strings, subjectId),
  // but quoting defensively costs nothing and protects against an operator
  // typing a comma into subjectId.
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

function rowToCsvLine(row: SampleRow): string {
  return CSV_COLUMNS.map(col => csvCell(row[col])).join(',');
}

/**
 * Streams a session's samples straight into CSV lines via the store's
 * cursor (not `streamSamples` collected into an array first) — a
 * 45-minute session is ~270k rows, and this avoids holding all of them as
 * JS objects at once just to immediately serialize and discard them.
 */
export async function buildSessionCsv(sessionId: string): Promise<Blob> {
  const lines: string[] = [CSV_COLUMNS.join(',')];
  await streamSamples(sessionId, row => { lines.push(rowToCsvLine(row)); });
  return new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' });
}

export function buildSessionMetadataJson(session: SessionRecord, sampleCount: number): Blob {
  const meta = {
    sessionId: session.sessionId,
    subject: session.subject,
    calibration: session.calibration,
    notes: session.notes,
    startedAtUnixMs: session.startedAtUnixMs,
    endedAtUnixMs: session.endedAtUnixMs,
    exportedAtUnixMs: session.exportedAtUnixMs,
    patternCounts: session.patternCounts,
    totalSampleRows: sampleCount,
  };
  return new Blob([JSON.stringify(meta, null, 2)], { type: 'application/json;charset=utf-8' });
}

/** Triggers a browser download of a Blob — a real app running in the user's own browser, not a sandboxed artifact, so a plain object-URL download is the correct mechanism here. */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Revoke on a delay, not immediately — some browsers cancel the download
  // if the object URL is revoked synchronously after click().
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}

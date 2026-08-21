# 002 — ΔT consecutive-reading gap logged as a defect; full §8.3 audit; reports convention adopted

**Scope:** docs only. `npm run build` clean. No source file touched.

---

## 1. `docs/BACKLOG.md` item 10 rewritten — marked as a DEFECT, not an enhancement

Item 10 already existed (added while reconciling against Data Contract
v1.1), but under-described its own severity — it read as a nice-to-have
contract-compliance gap rather than what it actually is: a live source of
false alerts in a diabetic foot monitor. Rewritten with:

- **What the contract requires vs. what the code does.** Contract §8.3:
  `TEMP_DELTA` fires only on "ΔT > 2.2°C ต่อเนื่อง ≥ 2 ครั้งวัด" — at least 2
  consecutive over-threshold measurements. `AlertStore.evaluate()`
  (`src/ts/data/AlertStore.ts`) fires `temp.delta` the instant one
  `CombinedSnapshot` crosses `TEMP_DELTA_THRESHOLD` — no consecutive-reading
  check exists at all.
- **Affected code path:** the `dT !== null && dT > TEMP_DELTA_THRESHOLD`
  branch in `AlertStore.evaluate()`, which runs on every
  `DeviceManager.onSnapshot()` tick (10 Hz) — so one noisy sample is
  sufficient to fire.
- **Why it matters, not just that it's non-compliant:** skin temperature
  fluctuates for mundane reasons — poor sensor contact, airflow, shoes just
  removed. The contract's 2-reading condition exists specifically to filter
  that noise before it reaches the patient. Firing on one reading means
  false alerts, and false alerts in this app risk alert fatigue — the
  patient tuning out the one alert that was real. Recorded as the same
  category of harm the bilateral-safety rule in `CLAUDE.md` exists to
  prevent: a technically-derived number reaching the patient as a false
  clinical signal.
- **What's correctly implemented, so it isn't confused with this gap:** the
  30-minute per-code repeat suppression (`REPEAT_SUPPRESSION_MS`) is present
  and matches contract §8.5 exactly. The defect is specifically in the
  *firing condition* (does a single noisy reading qualify at all), not in
  suppression (how often an already-valid alert can re-fire). Suppression
  cannot compensate for this gap — it only throttles repeats of an alert
  that already fired once.

Not fixed in this pass, as instructed — recorded and scoped only.

## 2. Audited every rule in the contract's §8.3 table against `AlertStore` — one more gap found

Asked specifically whether any other alert code has a similar
*implemented-but-under-conditioned* gap (as opposed to not being
implemented at all, which is item 9's territory). Full table:

| Code | Contract condition | Implemented as | Gap? |
| --- | --- | --- | --- |
| `TEMP_DELTA` | ΔT > 2.2°C, ≥2 consecutive readings | fires on 1 reading | **Yes — item 10, above** |
| `PRESSURE_WATCH` | any point > 75 kPa (contract itself attaches no persistence condition) | fires on 1 reading | No — matches; the contract's own rule is single-reading |
| `PRESSURE_PEAK` (→ `pressure.alert` in code) | Peak > 200 kPa **ขณะเดิน** ("while walking") | fires on 1 reading, **no walking/gait-state check exists anywhere in the codebase** | **Yes — new finding.** `walkingMinutes` on Home is a display-only mock summary stat (`src/ts/types.ts`, `mockData.ts`), not a live signal `AlertStore` can read. A foot resting under load while seated could raise this alert exactly as easily as an actual walking peak. Folded into item 10 rather than opened as a separate item, since it's the same class of defect on an adjacent rule. |
| `PRESSURE_PTI`, `ASYMMETRY_PEAK`, `LOAD_CONCENTRATION`, `GAIT_ABNORMAL`, `DEVICE_LOST`, `BATTERY_LOW` | — | not implemented at all | Out of scope here — whole-rule absence, already tracked in item 9 |

Recorded in `docs/BACKLOG.md` item 10 (the `PRESSURE_PEAK` row and the note
under it) rather than as a new item — same defect category, same fix
session likely to touch both once picked up.

## 3. Reports convention adopted

Three consecutive pass reports were truncated mid-sentence before reaching
the user — the last one lost the ΔT defect finding entirely. Going forward:

- Each pass's report is written to `docs/reports/NNN-<short-name>.md` and
  committed.
- Chat gets a short summary only: what changed, anything needing a
  decision, and a pointer to the file. If the chat summary would run long,
  that's a signal the report should carry it instead.

Added to `CLAUDE.md` under a new "Reporting" section so it survives past
this session rather than living only in chat history.

Report `001-dt-clinical-validation-and-thresholds-json.md` was written
retroactively in this same pass, reconstructing the previous (truncated)
pass's full content — the ΔT clinical-validation correction and the
`thresholds.json` promotion to item 11 — since that's what got lost.

---

## What changed, file by file

- `docs/BACKLOG.md` — item 10 rewritten in full (defect framing, code path,
  impact, §8.3 audit table, `PRESSURE_PEAK` walking-state finding folded
  in). Item 9 unchanged (its scope — whole-rule absence — doesn't overlap
  with this item's scope — partial conditions on existing rules).
- `CLAUDE.md` — new "Reporting" section documenting the
  `docs/reports/NNN-<short-name>.md` convention.
- `docs/reports/001-*.md`, `docs/reports/002-*.md` — new.

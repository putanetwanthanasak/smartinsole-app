# 029 — S6A: local storage (drift)

Branch `work/flutter-storage` (from `main` at the PR #24 merge, `c4766fa`)
· 2026-10-24 · Session S6A (`docs/SESSIONS.md` §3)
Spec: DESIGN-SPEC §4, §7, §8.2, §11, §14; DATA-CONTRACT v1.5 §8.3.

**Status: accepted by the user (2026-10-24).** Everything automated
passes, and the Note 10 check (temperature rows survive killing the app)
passes.

## Summary

- **Storage:** drift (SQLite), schema v1, 4 tables, each behind its own
  repository interface and exposed through Riverpod providers. Nothing
  outside `mobile/lib/storage/` imports drift or the row types.
- **Wired now:**
  - every temperature reading from `DeviceManager.temps` is written as it
    arrives, plus the day's max |ΔT|;
  - the Alerts tab badge reads the real unread count (0 when the table is
    empty);
  - retention runs at start, on resume, and once a day.
- **Not wired (as planned):** S7 connects AlertEngine to
  `AlertRepository.add`.
- **Privacy:** the database is in app-private storage, with no names or
  subject codes in it. **App backup and device-to-device transfer are now
  off** (section "Privacy").
- **Automated:** `flutter analyze` is clean, `dart format` is clean, and
  **all 437 tests pass** (384 before + 53 new). One golden changed: the BLE
  debug screen has a new Storage card.
- **Emulator** (`emulator-5554`):
  - the real-BLE build creates `files/smartinsole.sqlite` (mode 600, schema
    v1);
  - a mock run writes readings that show live on the debug screen and never
    reach that file;
  - no runtime errors.
- **Untouched:** the web app, `firmware/`, `mobile/lib/capture/`,
  `tools/capture/` and `shared/thresholds.json`.

## What changed

| Area | Files |
|---|---|
| Packages | `drift` 2.35, `drift_flutter` 0.3, `sqlite3` 3.8, `path`; dev: `drift_dev`, `build_runner`. `mobile/build.yaml` (drift options) |
| Storage | `mobile/lib/storage/`: `database.dart` (+ generated `database.g.dart`), `models.dart`, `local_date.dart`, 4 `*_repository.dart`, `retention.dart`, `temperature_recorder.dart`, `storage_providers.dart`, `storage_host.dart`, `README.md` |
| Wiring | `lib/ui/app.dart` (`StorageHost` around `MaterialApp`); `lib/ui/shell/app_shell.dart` (`unreadAlertCountProvider` now reads the store) |
| Debug screen | `lib/ui/screens/debug_ble_screen.dart`: "Storage" card with temperature rows per foot, the latest time, and how many readings this run wrote or failed to write |
| Android | `AndroidManifest.xml` (`allowBackup="false"`, `fullBackupContent`, `dataExtractionRules`); new `res/xml/data_extraction_rules.xml` and `res/xml/backup_rules.xml` |
| Schema dump | `mobile/drift_schemas/app_database/drift_schema_v1.json` |
| Tests | `test/storage/` (7 files), `test/drift/app_database/` (scaffold + generated v1 helpers), `test/helpers/pump_app.dart` and `test_driver/main_mcp.dart` use an in-memory database |
| Docs | `docs/SESSIONS.md` (v2.5 schedule, S6B scope, S6A result), `docs/design/DESIGN-SPEC.md` (§7.1/§14 notes on the "9"), `docs/BACKLOG.md` (note on item 9, new item 40), `mobile/CLAUDE.md` |

## Schema v1

All times are UTC ms (`*_ms`). `local_date` is the phone's calendar day
`YYYY-MM-DD` at that moment. Enums are stored by name, and alert codes by
their contract name. `PRAGMA foreign_keys = ON`.

**`alerts`**

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `code` | TEXT | One of the 8 contract codes, or `FOOT_CHECK_FINDING` |
| `level` | INTEGER | CHECK 1–5. Taken from the code, never passed in |
| `patient_status` | TEXT | `noData` / `safe` / `careful` / `rest`: what the patient saw when it was raised |
| `side` | TEXT? | `TEMP_DELTA`: the warmer foot |
| `zone` | TEXT? | `FootZone.id`, e.g. `hallux` |
| `site` | TEXT? | `forefoot` / `heel` |
| `measured_value`, `threshold` | REAL? | |
| `gait_class`, `gait_confidence` | TEXT?, REAL? | |
| `details` | TEXT? (JSON) | The extra numbers for the §7.3 detail rows, so S7 needs no schema change |
| `at_ms`, `local_date` | INTEGER, TEXT | |
| `read_at_ms` | INTEGER? | Decision 7. Set once; later opens keep the first time |
| `capture_stamp` | TEXT? | See "Research capture" |
| `foot_check_id` | INTEGER? | FK → `foot_checks`, ON DELETE SET NULL |

Indexes: `at_ms`, `read_at_ms`, `capture_stamp`.

**`temperature_readings`**

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `at_ms`, `local_date` | INTEGER, TEXT | |
| `side` | TEXT | |
| `forefoot_c`, `heel_c` | REAL? | null = wire `-32768` |
| `quality` | TEXT | `normal` / `poorContact` / `sensorFault` |
| `time_from_arrival` | BOOL | |

Indexes: (`side`, `at_ms`) and `local_date`. Every reading is stored, of
any quality, so the §8.2 "คุณภาพสัญญาณ" row can be filled. Connection gaps
are not stored: they are the time between rows, worked out when the chart
reads them. **S6B picks the gap rule** (for example, more than 2.5 × the
30 s period).

**`daily_summary`** (`local_date` is the PK)

| Column | Type | Notes |
|---|---|---|
| `steps`, `walking_min`, `worn_min` | INTEGER? | Filled from S8A. `setActivity` is ready |
| `max_delta_forefoot_c`, `max_delta_heel_c` | REAL? | |
| `alerts_l1` … `alerts_l5` | INTEGER, default 0 | |
| `foot_check_done` | BOOL | |
| `updated_at_ms` | INTEGER | |

Alert counts and `foot_check_done` are updated in the same transaction as
the alert or foot-check write. Max |ΔT| is updated by the recorder.

**`foot_checks`**

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `at_ms`, `local_date` | INTEGER, TEXT | Index on `local_date` |
| `q_redness`, `q_wound`, `q_swelling` | TEXT? | null / `none` / `yesOrUnsure` |
| `result` | TEXT | `saved` / `found` |
| `photo_sole_left`, `photo_sole_right`, `photo_top_left`, `photo_top_right` | TEXT? | Relative to `<support>/foot_photos/`; null = skipped |
| `answer_only` | BOOL | |

## Behaviour worth knowing

- **One visibility rule (user request).** `AlertKind.patientVisible`
  (level ≠ 2) is the only place the rule is written. One SQL expression in
  `DriftAlertRepository` is built from it, and both `watchVisible` (the list
  S6B builds) and `watchUnreadCount` (the badge) use that expression.
  - The same expression also limits both to the last 30 days, which the
    footer "แสดงย้อนหลัง 30 วัน" promises. This matters because research
    alerts can be older than that (see below).
  - A test fills the table with every kind at five ages, inside and outside
    the window, and checks that the count equals the unread rows in the
    list.
- **Foot checks (decision 4 of the plan).**
  - `save()` refuses a draft with any unanswered question, and nothing is
    written.
  - The result is decided by the repository, not by the caller: any
    `yesOrUnsure` gives `found` (rule 14).
  - A finding inserts a `FOOT_CHECK_FINDING` alert (level 3, "ควรระวัง")
    linked to its check, all in one transaction.
- **ΔT in the summary** uses `DeviceManager.snapshot()` at the moment a
  reading arrives. That is the same ΔT the screens show, and it is null
  unless both feet are usable (rule 4). A test checks that one foot alone
  never creates a summary row.
- **Mock runs use an in-memory database**, and so does the driver's
  `BLE_FAKE` run. On the emulator, 6 mock rows were written in a minute
  while the file kept 0 rows.
- **Storage errors never reach the BLE path.** A failed write is counted
  (`failed` on the debug card) and logged.

## Retention

- The cutoff is `now − 30 days`. A row **exactly 30 days old is kept; 30 days
  + 1 ms is deleted**. Both cases are tested for alerts, temperatures and
  foot checks.
- A `daily_summary` row is a whole day. It is deleted when its date is
  before the cutoff's local date, so the cutoff's own day is kept.
- **Alerts with a `capture_stamp` are never deleted by age.** They are study
  data for the warm-compress test, and go only through
  `AlertRepository.deleteForCapture` (tested).
- **Foot photos:**
  - The files are deleted first, then the row. A file that cannot be
    deleted keeps its row, and the next run tries again. This is tested
    with a read-only folder.
  - A file that is already missing is not an error.
  - Only paths inside `foot_photos/` are ever deleted. A test with
    `../research/…/trial.csv` and `/etc/hostname` as photo paths leaves both
    files untouched.
  - Research capture files (`app_flutter/research/`) are not in the database
    and are never touched.
- **Schedule** (`RetentionSchedule`): it runs at start, on resume (an
  `AppLifecycleListener` in `StorageHost`), and from an hourly timer. Each
  trigger runs it only if 24 h have passed since the last run.
  - "24 h have passed" is checked from timestamps at that moment. A starved
    timer therefore delays a run but never skips one, and a resume after
    two days runs at once (tested with fake_async).
  - A failed run is retried at the next check.
- 30 days is the constant `retentionPeriod` in `lib/storage/models.dart`. It
  is a storage policy, not a clinical threshold, so it is not in
  `thresholds.json`. No thresholds were added or read in this session.

## Research capture link

- `capture_stamp` holds only the time part of the session id
  (`SI-001_20261110-093000` → `20261110-093000`, `captureStampOf`). No
  subject code is stored (decision 2).
- `AlertRepository.forCapture(stamp)` returns a session's alerts, all
  levels, oldest first, ready for the export.
- **Not done here, now BACKLOG 40:**
  - S7 sets the stamp while a capture runs.
  - The export writes the alerts file, listed in the SHA-256 manifest and
    checked by `load_capture.py`.
  - **"Delete from phone" must call `deleteForCapture`.** I did not change
    `capture_summary.dart` because the capture flow was out of scope. Until
    it is wired, deleting a capture leaves its alerts in the database.
    There are none before S7, so nothing is affected yet.

## Privacy (IRB)

- **Location:** `/data/data/th.ac.kmutt.smartinsole/files/smartinsole.sqlite`,
  the app's private support folder, mode `-rw-------` (checked on the
  emulator). Foot photos will go in `files/foot_photos/`.
- **What is stored:** no names, no subject codes, no device addresses. Only
  times, sides, zones, values, answers and relative photo paths.
- **Encryption:**
  - The Note 10 uses Android **file-based encryption**: Android 10 and later
    require FBE on every device that launches with that version, and the
    Note 10 runs Android 12.
  - Confirmed on the phone: `ro.crypto.type` = `file`,
    `ro.crypto.state` = `encrypted`.
  - No SQLCipher was added.
- **Backup and transfer are now off (decision 3).**
  - Before this change, `allowBackup` was not set, so it defaulted to *on*.
    Google backup could copy the database, photos and capture files off the
    phone.
  - Now `android:allowBackup="false"`.
  - `android:dataExtractionRules` points to `data_extraction_rules.xml`,
    which excludes every domain for both `cloud-backup` and
    `device-transfer` (`allowBackup=false` alone does not stop
    device-to-device transfer on Android 12+).
  - `android:fullBackupContent` points to `backup_rules.xml`, which excludes
    the same domains for API ≤ 30.
  - Checked in the built APK: `aapt2 dump xmltree` shows all three
    attributes.
  - Checked on the emulator: `dumpsys package` flags no longer include
    `ALLOW_BACKUP`.

## Checks

| Check | Result |
|---|---|
| Insert and read every table | Pass (`alert_repository_test`, `temperature_and_summary_test`, `foot_check_repository_test`) |
| Mark-as-read (first time kept) and unread count (0 when empty, drops when one is opened, stream updates, level 2 excluded) | Pass |
| Badge from the store | Pass: a provider test counts 0 → 1 → 0, and a widget test shows a stored alert as badge "1" on the real shell |
| 30-day retention at the boundary (exactly 30 d kept, +1 ms deleted) | Pass |
| Photo files deleted with their rows; research files untouched; a failed delete keeps the row | Pass (`retention_test`) |
| Midnight / local-date grouping | Pass (`local_date_test`). 23:59:59.999 and 00:00:00.000 Bangkok land on their own days in alerts, temperatures, summaries and foot checks; the device default matches `DateTime.toLocal()`; a changing offset is applied per moment |
| File persistence: write, close, reopen | Pass (`persistence_test`, a real SQLite file in a temp folder) |
| Migration scaffold for v1 | Pass (`test/drift/app_database/migration_test.dart`). A database the app creates matches the committed dump, so a table change without a version bump fails; the app opens an existing v1 file unchanged. Two-version tests come from `make-migrations` once v2 exists |
| `flutter analyze` / `dart format` | Clean / 0 files changed |
| `flutter test` | **437 passed** |
| Emulator, real-BLE build | The file is created and is schema v1 (`PRAGMA user_version` 1, all tables and indexes); no runtime errors |
| Emulator, `MOCK=safe` | The debug card shows L 3 / R 3 rows after ~60 s and updates live; written 6, failed 0; the phone file still has 0 rows |
| **Note 10: rows survive killing the app** | **Pass** (see "Note 10 checkpoint"); accepted by the user |

Emulator screenshots: `029-flutter-storage/emulator-debug-storage-mock.png`
(1 row per foot just after start) and `emulator-storage-card-60s.png`
(3 per foot about a minute later).

Rule check against FLUTTER-PLAN §6:

- Rule 2: retention is timestamp-based, with nothing latched by a timer.
- Rule 4: the summary ΔT comes from two-foot snapshots only.
- Rule 12: no thresholds are hardcoded, and none are needed.
- Rule 14: the foot-check result is decided in the repository, and "not
  sure" counts as a finding.
- Rule 15: photos stay app-private and backup is off.
- The other rules are not touched.

## Release APK size

63,576,255 bytes, against 56,401,033 for S5, so **+7.2 MB**.

- About 5.2 MB is `libsqlite3.so`, stored uncompressed for 3 ABIs (about
  1.7 MB each). The rest is the drift code in `libapp.so`.
- On the Note 10 (arm64) only one copy of each is installed, so about
  +2.4 MB there.
- Split per-ABI APKs would remove the difference if size ever matters. Not
  changed now.

## Note 10 checkpoint (run by Claude, 2026-10-24; accepted by the user)

Short check: one simulator, 2 minutes, kill, reopen. The steps as planned:

1. Plug in the Note 10 and power **one** ESP32 simulator (left is enough).
2. I record the installed build's research sessions and `firstInstallTime`
   (data safety, as in report 028). Then I run `adb install -r` with this
   release APK; the install keeps app data.
3. I check FBE with `getprop ro.crypto.type` / `ro.crypto.state`.
4. Settings → "BLE debug (temporary)" → connect the left insole and let it
   stream for 2 minutes. The Storage card should show about 4 rows for LEFT
   (one per 30 s).
5. Kill the app (`adb shell am force-stop th.ac.kmutt.smartinsole`, or swipe
   it away), reopen it, and go to Settings → BLE debug **without
   connecting**. Pass if the Storage card still shows the same LEFT count
   and latest time, with "this run: written 0".

**Results:** phone `RF8M83P4STZ` (SM-N975F, Android 12), left simulator
board `88:57:21:B7:74:9E` only.

| Step | Result |
|---|---|
| Data safety before install | The installed build had `firstInstallTime` 2026-10-18 19:20:47 and the export staging folder `TEST-003_20261023-215802` (S5 checkpoint). Its flags still included `ALLOW_BACKUP` |
| `adb install -r` (release, the S6A code) | Success. `firstInstallTime` unchanged; `lastUpdateTime` 2026-10-24 16:39:37; the `TEST-003` folder still there; flags now `[ HAS_CODE ALLOW_CLEAR_USER_DATA ]`, **no `ALLOW_BACKUP`** |
| Encryption | `ro.crypto.type` = `file`, `ro.crypto.state` = `encrypted` (FBE) |
| Home after install | "ยังไม่ได้รับข้อมูล", **no badge** (empty alert table → 0) |
| Connect LEFT (BLE debug) | First attempt `ANDROID_SPECIFIC_ERROR (code 133)` at 16:41:50.9; the automatic retry connected (MTU 247, 8/pkt, N 6) at 16:41:54.0. This is the existing S3A retry path, not a storage issue |
| Streamed about 2.5 min | Storage card at 16:44:46: **LEFT 6 rows, latest 16:44:24, written 6, failed 0**. One reading at connect and one every 30 s. `note10-before-kill.png` |
| `am force-stop` at 16:44:56 | Process gone (`pidof` empty) |
| Reopen → Settings → BLE debug, **no connect** | **LEFT 7 rows, latest 16:44:54, "this run: written 0 · failed 0"**; the log shows only adapter/permission, no connection. `note10-after-restart.png` |

**Pass.** All rows written before the kill are still in the file. The 7th
row is the next 30 s reading (16:44:24 + 30 s), written at 16:44:54, after
the last screenshot (16:44:46) and before the force-stop (16:44:56). No row
was written after the restart.

The phone keeps this build (S6A release, debug-key signed, data kept). The
7 rows of simulator readings from this check stay in its database. They
are deleted by retention after 30 days, or by clearing the app's data.

## Leftovers and notes for later sessions

- **S6B:**
  - The list reads `AlertRepository.watchVisible(nowMs)`, and the
    temperature chart reads `TemperatureRepository.watchDay(localDate)`.
  - Choose the gap rule for the chart.
  - The visible window is fixed when the stream is subscribed. The badge
    provider subscribes once, so an alert crossing the 30-day line while the
    app stays open keeps counting until the next start or resume. Only
    research alerts can outlive retention, so this is an edge case. If S6B
    needs it exact, re-subscribe the list and badge on day change.
- **S7:** write alerts through `AlertRepository.add` with `patientLevel`,
  `details` and `captureStamp` (BACKLOG 40).
- **S8A:** `DailySummaryRepository.setActivity` for steps, walking and worn
  minutes.
- **S8C:**
  - Photos go in `footPhotoDirProvider()` (`files/foot_photos/`), and paths
    are stored relative to it.
  - `FootCheckRepository.save` does the result rule and the finding alert.
  - "ลบรูปถ่ายเท้าทั้งหมด" (delete all photos) still needs an API: delete
    the files and null the paths, or delete the rows. Decide in S8C.
- **BACKLOG 40:** wire research alerts into the export and "Delete from
  phone".

## Decisions needed

None. Everything in the plan was approved; the 4 questions were answered
before the code was written.

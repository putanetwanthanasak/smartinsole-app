# 030 — S7: alert rules (AlertEngine)

Branch `work/flutter-alert-rules` (from `main` at the PR #25 merge,
`5c4fd96`) · 2026-10-24 · Session S7 (`docs/SESSIONS.md` §3)
Spec: DATA-CONTRACT v1.5 §8.2–§8.5, FLUTTER-PLAN §6 and §7, DESIGN-SPEC
§6, §7 and Appendix A. Plan approved 2026-10-24, with the user's
additions on the ΔT boundary, phone step 3 and the SR checklist.

**Status: everything automated passes, and the Note 10 checkpoint ran
on 2026-10-24 with all 7 steps passing (section "Note 10 checkpoint").
Waiting for the user to accept it.**

## Summary

- **The engine:** `AlertEngine` (`mobile/lib/rules/alert_engine.dart`)
  implements all 8 codes of contract §8.3:
  - it runs on the 50 Hz path, with a per-foot walking gate (§8.3.2) and
    step detection;
  - ΔT needs 2 consecutive reading pairs;
  - suppression is 30 minutes per code + side + zone or site, and is read
    back from the alerts table, so it holds across a restart;
  - it maps levels 1–5 to the patient's 3 levels (FLUTTER-PLAN §7);
  - every code has plain-Thai copy (draft).
- **Rule 12:** every number is in `thresholds.json`. A new test fails on
  any numeric literal in `lib/rules/` other than 0, 0.5, 1, 100 and 1000.
  I checked that it catches a planted `75`.
- **Home** reads its status from the engine, and `InterimStatus` is
  deleted. This settles:
  - **BACKLOG 37:** the balance note turns orange while `ASYMMETRY_PEAK`
    holds;
  - **BACKLOG 38:** the connected foot's level 3+ wins over No data, and
    No data names the missing foot.
- **Research capture (BACKLOG 40):**
  - alerts raised while a session screen is open carry its stamp;
  - the export adds `alerts.csv`, hashed in the manifest;
  - "Delete from phone" deletes them;
  - `load_capture.py` checks the file.
- **Simulator** (decision 4, `firmware/simulator` only): serial commands
  `n` / `t` / `p` / `?`. `serial_log.py --commands FIFO` sends them without
  reopening the port, since a reopen resets the board.
- **Finding:** the simulator's normal walk is too gentle for the app's
  walking gate. The `p` scenario carries its own stronger motion, so the
  phone check still works. BACKLOG 42 holds the options for the user.
- **Automated checks:**
  - `flutter analyze` is clean and `dart format` changed 0 files;
  - **all 488 Flutter tests pass**;
  - `pio test -e native` passes (6 new scenario tests);
  - `pio run -e left -e right` builds;
  - `load_capture.py --selftest` passes.
- **Goldens:** 10 changed, all reviewed (see "Goldens").
- **Untouched:**
  - the web app;
  - capture recording and timing: every recorded file in the shared
    fixture is byte-identical, and only the manifest and the new
    `alerts.csv` changed;
  - BLE, the packet format and the contract's wire sections.

## What changed

| Area | Files |
|---|---|
| Thresholds | `shared/thresholds.json` + its asset copy: `pressure.ptiWindowMin` 60, `ptiMinSteps` 20, `peakHoldMs` 2500; `asymmetry.peakSteps` 20, `concentrationSteps` 20; `device.lostAfterMin` 5; `alerts.repeatMin` 30; `steps.contactKpa` 10, `minStanceMs` 250, `maxStanceMs` 2500. `lib/config/thresholds.dart` reads them |
| Rules (new) | `lib/rules/`: `alert_engine.dart`, `walking_gate.dart`, `step_detector.dart`, `alert_copy.dart`, `gait_note.dart`, `alert_providers.dart`, `README.md` |
| Rules (changed) | `alert_code.dart` (`carefulLevel`, `restLevel`); `patient_status.dart` (`PatientStatus.missing`, `patientLevelFor`, `alertKey`); `asymmetry.dart` / `weight_share.dart` (display windows moved to Home; docs). **Deleted:** `interim_status.dart` and its test |
| Storage | `alert_repository.dart`: `since(fromMs)`, `watchStats()` / `AlertStats`; `storage_host.dart` keeps the engine alive; `storage_providers.dart`: `alertStatsProvider` |
| Home | `home_model.dart` (engine view; `mapPeakWindowMs`, `balanceWindowMs`; `asymmetrySide`), `home_copy.dart` (copy from `alert_copy.dart`; No data names the missing foot), `home_screen.dart` (orange balance note) |
| Capture | `capture_providers.dart` (`activeCaptureProvider`); `capture_home_screen.dart` (sets and clears it around the flow screen); new `alerts_csv.dart`; `export.dart` (`stageExport(extra:)`, `exportSession`, `deleteSession`); `capture_summary.dart` uses them |
| Debug screen | Storage card: "alerts N · capture-tagged N · latest CODE time" |
| Tools | `tools/capture/load_capture.py`: loads and checks `alerts.csv`; `--selftest` covers it. `shared/capture_fixture/`: `alerts.csv` with one alert, manifest updated |
| Simulator | `lib/insole_core/src/scenario.{h,cpp}`, `src/main.cpp` (non-blocking serial commands), `test/test_scenario/`, `tools/serial_log.py --commands`, `README.md` |
| Tests | new `test/rules/` (`alert_engine_test` 36, `step_detector_test` 7, `walking_gate_test` 3, `no_threshold_literals_test` 3, `alert_copy_test` 3, `rules_rig.dart`), `test/capture/capture_alerts_test.dart` (4); updated Home, capture fixture, capture screens and thresholds tests |
| Docs | `docs/BACKLOG.md` (31, 37, 38, 40 resolved; notes on 18; new 41, 42), `docs/SESSIONS.md` (S7 result; SR checklist additions), `docs/DATA-CONTRACT.md` (§8.3 addendum + changelog row), DESIGN-SPEC Appendix A (S7 draft strings), `docs/STUDY-CAPTURE.md`, `mobile/CLAUDE.md`, `mobile/lib/capture/README.md`, `shared/README.md` |

## The rules as built

The table in `mobile/lib/rules/README.md` is the reference. Points worth
knowing:

- **Walking gate (§8.3.2):** the mean of |‖a‖ − 1 g| over the last
  `walkingWindowMs` of samples, compared in whole mg, so a mean exactly
  at `walkingAccelG` counts as walking whatever the float error. It is
  reset by a new connection or a seq gap.
- **Steps:**
  - a stance starts when the summed kPa goes above `contactKpa` and ends
    at the first sample at or below it;
  - it counts only if its length is within `minStanceMs`–`maxStanceMs`
    and the gate was on at any of its samples;
  - PTI per zone is a trapezoid sum over the samples' unix times.
- **`PRESSURE_PEAK`** (rule 7):
  - it starts on a sample above `alertKpa` taken while the gate is on;
  - it keeps holding for **`peakHoldMs`** (2.5 s, new and provisional)
    after the last such sample;
  - `PRESSURE_WATCH` holds the same way, with no gate.
  - **Why the hold:** without it, a rule that is true at every step would
    end and restart between steps. The approved plan said "clears on the
    next step at or below `alertKpa`". A time hold does the same job
    without depending on step detection. It is the one key added beyond
    the plan; see "Decisions needed".
  - A high load while standing is `PRESSURE_WATCH` only (tested).
- **`PRESSURE_PTI` and `LOAD_CONCENTRATION`** follow user decisions 1
  and 2:
  - they also need the foot to be **still walking** (its latest step
    ended within `maxStanceMs`);
  - without that, a PTI mean that stays above the line for an hour would
    keep Home on Be careful long after the person sits down;
  - the 60-minute window itself still decides whether PTI fires again
    once walking resumes.
- **`ASYMMETRY_PEAK`:**
  - evaluated on each completed step of either foot;
  - the other foot's latest step must have ended within `maxStanceMs`
    before this step started;
  - the run resets on a step at or below `peakPct`, and the rule clears
    when a foot is unusable.
- **`TEMP_DELTA`:**
  - a pair forms when both feet have a reading newer than the last pair;
  - a missed reading from one foot does not reset the run, but a pair
    with no ΔT does (poor contact, one foot unusable, or −32768);
  - the comparison is at 0.01 °C resolution, |ΔT| > `deltaC`.
  - **The doc 03 note** (user addition 5) is in the code doc,
    DATA-CONTRACT §8.3 and `docs/STUDY-CAPTURE.md`: the rule is strictly
    above 2.2 °C (Lavery 2004), while doc 03 counts a warm-compress event
    as qualifying at ≥ 2.2 °C on the reference thermometer. They differ
    only at exactly 2.20 °C, and the analysis uses doc 03's definition
    for qualifying events.
- **`DEVICE_LOST`:**
  - a foot that streamed in this run has had no data for more than
    `lostAfterMin`, measured from the arrival time (rule 3);
  - the user's own Disconnect never raises it;
  - the 1 s timer re-asks, so it fires with no data arriving (tested);
  - the stored alert records the last battery level.
- **`BATTERY_LOW`:** usable and below `lowPct`; the card does not change.
- **Status:**
  - higher level first;
  - within level 3, TEMP_DELTA > PTI > PEAK > LOAD_CONCENTRATION;
  - then the larger value ÷ threshold;
  - levels 1–2 never set the card.
- **Raising alerts:**
  - an alert is raised on a rule's rising edge, unless the same key was
    raised in the last `repeatMin`; exactly `repeatMin` later is allowed
    (tested both sides by one packet);
  - each stored row has the patient level shown at that moment, the
    detail numbers, the gait estimate (pressure codes only; null until
    S8A) and the capture stamp;
  - level 2 is stored and stays hidden by the S6A visibility rule.
- **Gait note** (§8.3.1):
  - `gaitNoteTh` gives the contract's text only at `minConfidence` or
    above, and only when the zone matches;
  - it never changes a level;
  - `rotated_foot` gets no note, because Model A has no in/out direction
    (BACKLOG 41).

## Research capture link (BACKLOG 40)

- **"Running" means the session's flow screen is open**, in any phase.
  `capture_home_screen._open` sets `activeCaptureProvider` before the
  push and clears it in a `finally`. Recording and timing code is not
  touched.
- **`alerts.csv`** is written in the export folder only and is listed and
  hashed in `manifest.json`. When there are no alerts it is header-only.
- **Columns:** `at_ms`, `code`, `level`, `patient_status`, `side`
  (L/R), `zone`, `site`, `measured_value`, `threshold`, `gait_class`,
  `gait_confidence`, `read_at_ms`, `details` (quoted JSON).
- **Change from the plan:** the planned `at_local` column was dropped. A
  local time without its offset is ambiguous, `at_ms` is exact, and the
  analysis can convert it.
- **`load_capture.py` checks:**
  - the header;
  - known codes, and a level that matches the code;
  - zone, site and side valid for the code;
  - time order, and nothing before the session's `createdUnixMs`;
  - numbers parse and `details` is a JSON object.
  - A missing file is a WARN (exports from before S7).
  - The self-test covers each failure, and a changed byte in
    `alerts.csv` fails the checksum.
- **"Delete from phone"** removes the session's alerts and no others
  (tested).

## Goldens

Ten goldens changed: `home_*_100` and `home_*_200` for watch,
safeOrangeDot, rest, oneFootMissing and lowBattery. I compared each old
and new image:

- **watch:**
  - the balance note is orange with the warning icon ("ลงน้ำหนักเท้า
    ซ้ายมากกว่า");
  - the Alerts badge shows 3: PEAK meta1 and PTI meta1 and meta3, the
    visible ones of the 10 stored. The other 7 are WATCH and ASYMMETRY
    at level 2.
- **safeOrangeDot:** orange balance note. Its PAI of about 45 % is a real
  level-2 `ASYMMETRY_PEAK`, so I kept the preset as it is (decision during
  implementation).
- **rest:** badge 1 (TEMP_DELTA).
- **lowBattery:** badge 1 (BATTERY_LOW).
- **oneFootMissing:** the detail names the right foot: "ยังไม่ได้เชื่อมต่อ
  แผ่นรองเท้าขวา จึงยังบอกไม่ได้ว่าเท้าขวาปลอดภัยหรือไม่".

The plan expected only watch and oneFootMissing to change. The badges
are new because alerts are now really stored, which is the intended
behaviour. No other screen's golden changed. The BLE debug goldens did
not change because the Storage card (and its new alerts line) is below
their 2000 px surface. The emulator screenshot shows that line.

## Checks

| Check | Result |
|---|---|
| Every code: trigger / no trigger / exact boundary | Pass (`alert_engine_test`):<br>• WATCH 75 vs 75.5<br>• PEAK 200 vs 200.5 while walking<br>• PTI exactly 80 vs 80.625 kPa·s<br>• CONC exactly 40 % vs 40.6 %<br>• ASYM exactly 15 % vs 16.2 %<br>• ΔT exactly 2.2 vs 2.6<br>• battery 15 vs 14<br>• lost exactly 5 min vs one packet more |
| Walking gate, step detector | Pass:<br>• gate at and below `walkingAccelG`<br>• stance limits<br>• standing ≠ step<br>• PTI integral exact |
| Counts | Pass:<br>• PTI with 19 vs 20 steps, and steps leaving the 60-min window<br>• CONC 19 vs 20 steps, a zone change restarts it<br>• ASYM 19 vs 20 steps |
| ΔT | Pass:<br>• 2 pairs needed<br>• exactly 2.2 resets the run<br>• a poor-contact pair resets it<br>• a missed reading in between keeps it |
| Rule 7 | Pass: high load while standing → WATCH only, never PEAK |
| Suppression | Pass:<br>• same key within 30 min → one alert<br>• exactly 30 min → allowed, one packet earlier → not<br>• a different zone → its own alert<br>• across a restart on the same database → still suppressed; 31 min later → raised again |
| Status | Pass:<br>• every FLUTTER-PLAN §7 row (`patientLevelFor` 1–5, every code)<br>• level 4 over level 3; PTI names the card over PEAK<br>• same code on both feet → the one further past its threshold<br>• BACKLOG 38 (one foot: level 3 wins; otherwise missing-foot No data) |
| Gait hook | Pass:<br>• stored with pressure alerts only; the level is unchanged<br>• note below `minConfidence` → none; zone mismatch → none; `rotated_foot` → none |
| Capture tagging | Pass:<br>• tagged while open, untagged after<br>• the flow screen sets and clears the stamp (widget test)<br>• `alerts.csv` exact rows and manifest hash<br>• header-only when empty<br>• delete removes only its alerts |
| No threshold literals | Pass; a planted `75` in `pressure_level.dart` is caught |
| Copy | Pass:<br>• every code × side × zone/site has Thai title, detail, steps, why and advice<br>• no "kPa", "kpa", "ΔT" or "PAI"<br>• the title names the foot<br>• Home strings only for level 3+ |
| `flutter analyze` / `dart format` | Clean / 0 changed |
| `flutter test` | **488 passed** |
| Simulator | `pio test -e native`: all pass, including `test_scenario` (6). `pio run -e left -e right`: both build (RAM 11.9 %, flash 47.5 %) |
| `load_capture.py --selftest` | PASS (8 new alerts.csv checks) |
| Release APK | 63,789,331 bytes, against 63,576,255 for S6A (+0.2 MB) |

### Emulator (`emulator-5554`, Dart MCP + adb screenshots)

All screenshots are in `030-flutter-alert-rules/`.

- **MOCK=watch, after a few seconds:** Be careful, "ปลายเท้าซ้ายรับ
  น้ำหนักมากตอนเดิน" (PEAK), badge 1. Screenshot:
  `emulator-watch-peak.png`.
- **MOCK=watch, after about 50 s:** the detail moved to the PTI text
  "…รับน้ำหนักมากต่อเนื่องนานเกินไป", badge 3, and the balance note is
  orange. Screenshots: `emulator-watch-pti.png`,
  `emulator-watch-balance-note.png`.
- **Debug Storage card:** "alerts 10 · capture-tagged 0 · latest
  PRESSURE_PTI", the same 10 as the golden run. Screenshot:
  `emulator-debug-storage-alerts.png`.
- **Switched live to `rest`:** Rest your feet, "เท้าขวาอุ่นกว่าเท้าซ้าย
  2.6 องศา ติดต่อกันมาสักพัก", badge 4. Screenshot: `emulator-rest.png`.
- **Fresh run with `oneFootMissing`:** No data naming the right foot, no
  badge. Screenshot: `emulator-oneFootMissing.png`.
- **A live switch from `watch` to `oneFootMissing`** showed Be careful
  (PTI, left) instead. This is correct: the left foot's last hour of steps
  still averages above 80 kPa·s, and a connected foot's level 3 wins over
  a missing foot (BACKLOG 38).
- A mock run uses an in-memory database (S6A), so each run starts with no
  alerts.
- No runtime errors.

Rule check against FLUTTER-PLAN §6:

| Rule | How S7 meets it |
|---|---|
| 2 | Every rule is derived from timestamps when asked; the timer only asks |
| 3 | `DEVICE_LOST` measures from arrival time |
| 4 | ΔT and asymmetry need both feet usable |
| 5 | No data stays grey |
| 6 | 2 consecutive pairs |
| 7 | PEAK only while the gate is on |
| 10 | The rules read the 50 Hz path; Home reads the 10 Hz view |
| 11 | The gait estimate is stored and noted, never a level |
| 12 | Thresholds come from `thresholds.json`, with a literal test |
| 13 | Every code has Thai advice |

## Simulator scenarios (decision 4)

- **Normal walk:** the 50 Hz task reads an atomic scenario id and asks
  `insole::scenario::source(id)` for a pure `DataSource`. `n` returns the
  same `synth::walking()` object, so the normal output is unchanged
  (tested byte for byte).
- **`t`:** the forefoot is 3.00 °C warmer; the heel and the quality byte
  are unchanged.
- **`p`:**
  - meta1 (FSR 1) gets a plateau of ADC 3180, about 249 kPa with the
    served calibration, over 60 % of stance;
  - per step, meta1's PTI is above 1.2 × `ptiKpaS` (tested over a
    minute, both sides);
  - the accel's dynamic part is ×4, so the app's gate is on in every
    800 ms window: lowest mean above 0.19 g, peaks about 4.6 g, well
    inside ±8 g.
- **Commands:** `loop()` reads them without blocking and prints
  `[scenario] …` on every change and at boot.

**Finding (BACKLOG 42).** The normal walk's lowest gate mean is 0.069 g
(L) and 0.071 g (R) against the 0.15 g gate. Its highest is about 0.16 g
without noise. So with the normal walk:

- the gate is on only briefly in each stride;
- PEAK can't be shown, because it needs the gate on at the high sample.

*Corrected after the Note 10 run:* the first version of this report said
the app "counts few steps" and that PTI, concentration and asymmetry
can't be shown. That was wrong. A step needs the gate on at only one of
its samples, and in the recorded normal trial 6 of 6 left and 5 of 6
right steps passed. That is why `ASYMMETRY_PEAK` fired on the phone.

The old native test passes because it checks the SD of ‖a‖, not the
contract's statistic. Changing the normal walk is outside the approved
firmware scope, so it is a decision for the user.

**Plan addition, phone step 3.** I checked whether the normal scenario
keeps the gate on. It doesn't. A walking trial wouldn't help either: the
board does not know which trial is running. The `p` scenario therefore
brings its own walking motion. **The phone check uses the first walking
trial (normal gait, 30 s in a TEST session)**, as the user's fallback
says, and PEAK fires there from the `p` motion.

## Leftovers and notes for later sessions

- **S6B:**
  - the Alerts list and detail use `alertCopyFor(code, side, channel,
    site, value, threshold)` for title, detail, steps, why and "ควรทำ";
  - the detail rows come from `StoredAlert.details` (e.g. TEMP_DELTA
    `leftC` / `rightC` / `consecutive`, DEVICE_LOST `lastBatteryPct`);
  - the gait note comes from `gaitNoteTh` with the stored class and
    confidence.
- **S8A:**
  - implement `gaitEstimateProvider` (Model A);
  - the step count can reuse `StepDetector` (one per foot, fed from the
    50 Hz path);
  - BACKLOG 41 (`rotated_foot` direction).
- **SR (added to `docs/SESSIONS.md`):** with the real boards, compare
  step detection against a hand count in one normal-gait trial, and
  record how often PTI and LOAD_CONCENTRATION fire in the normal-gait
  trials. Both use provisional values until then.
- **Contract owner:** the per-step readings and the new keys are a local
  addendum (DATA-CONTRACT §8.3), not sent yet.
- **Mock presets:** no preset changed. The planned optional end-to-end
  preset test was not added as a separate file. The Home goldens and
  `home_model_test` already run every preset through the real engine.

## Note 10 checkpoint (run 2026-10-24; waiting for the user to accept)

Plug in the Note 10 and both boards, then tell me. I will:

1. Flash both boards with the new firmware (`pio run -e left -t upload`,
   then `-e right`, each with `--upload-port` set to its by-path name).
2. Start both serial loggers with `--commands left.cmd` / `right.cmd`
   **before** the phone connects (opening a port resets the board).
3. Install the release build with `adb install -r`, which keeps the data.

Then:

| # | Step | Expected |
|---|---|---|
| 1 | Settings → BLE debug → connect both | Home: Safe. Debug card "alerts N · capture-tagged 0" |
| 2 | Research capture: new session `TEST-004`, run calibration (10 s) | Nothing new |
| 3 | First walking trial (normal gait, 30 s). About 5 s into recording, I send `p` to the left board | `[scenario] p …` in the left log. `PRESSURE_PEAK` (left, meta1) right away, then `PRESSURE_PTI` and `LOAD_CONCENTRATION` after about 22 s (20 steps) |
| 4 | Still in the session (summary screen): I send `n` to the left, then `t` to the right | `TEMP_DELTA` (right, forefoot) after 2 temperature readings, within about 30–90 s, as the warm-compress step would. Back on Home afterwards: Rest your feet while `t` is on |
| 5 | Summary → Export for USB → `export_capture.py` → `load_capture.py check` | PASS; `alerts.csv` is in the manifest with PEAK, PTI, CONC and TEMP_DELTA tagged rows; the debug card's capture-tagged count matches |
| 6 | `n` to both | Home goes back to Safe once the next readings arrive |
| 7 | Summary → Delete from phone (twice) | Debug card: capture-tagged 0; untagged alerts stay |

Step 4 differs from the plan's order. The plan sent `t` after the export
and the session. I moved it inside the session so it rehearses the
warm-compress step the way `docs/STUDY-CAPTURE.md` now describes, and so
the export proves a TEMP_DELTA row too.

### Results

**Setup.**
- The left board was not on the USB bus at first; you plugged it into
  port 6.
- I identified each board by its boot line before flashing: right on
  port 7, left on port 6. Both flashed with the S7 firmware.
- Loggers started at 18:39:43, both reading cleanly, and both boards
  answered `?` through the pipes.
- The release APK (63,789,331 bytes, from the PR code) was installed with
  `adb install -r`.
- Commands and board replies: `030-flutter-alert-rules/note10-scenario-log.txt`.

| # | Result |
|---|---|
| 1 | **Pass.** Both STREAMING; Home green "ตอนนี้เท้าปลอดภัย"; Storage "alerts 0 · capture-tagged 0". Board logs: one central each, MTU 247, 8/pkt, synced, no MTU drops |
| 2 | **Pass.** `TEST-004` session, 10 s calibration recorded, no alert |
| 3 | **Pass**, with a corrected expectation (below).<br>• `p` sent at 18:44:55.42; the left board confirmed at 18:44:55.43, about 6 s into the normal-gait recording.<br>• The trial: 1500 samples per foot, no gaps; both boards stayed on their connection with no notify failures.<br>• Alerts, all tagged:<br>  – `PRESSURE_PEAK` (and `PRESSURE_WATCH`), left meta1, 247.0 kPa, walking, at 18:44:56.48 (1.05 s after `p`);<br>  – `ASYMMETRY_PEAK`, left, 247.0 vs 48.5 kPa, 20 steps, at 18:45:07.39;<br>  – `LOAD_CONCENTRATION`, left meta1, 56.6 %, 20 steps, at 18:45:17.93.<br>• **No `PRESSURE_PTI`** (see below) |
| 4 | **Pass.** `n` left and `t` right at 18:45:55.7.<br>• `TEMP_DELTA` right forefoot at 18:46:36.10, 40 s later: ΔT 3.42 °C (L 31.52, R 34.94), 2 consecutive pairs, heel ΔT 0.25 °C, patient status rest.<br>• Home: red "ควรพักเท้าตอนนี้".<br>• Storage: "alerts 5 · capture-tagged 5" |
| 5 | **Pass.** "Staged 14 files (5 alerts) with manifest.json…". `export_capture.py` found every SHA-256 matching; `load_capture.py`:<br>• all 6 attempts at 20 ± 0.25 ms;<br>• "alerts.csv: 5 alert(s): ASYMMETRY_PEAK, LOAD_CONCENTRATION, PRESSURE_PEAK, PRESSURE_WATCH, TEMP_DELTA";<br>• PASS.<br>You also recorded the other 4 gaits, so the session is `done`. The staged copy was left on the phone. `alerts.csv`: `030-flutter-alert-rules/note10-alerts.csv` (no subject data in it) |
| 6 | **Pass.** `n` to both at 18:56:54; Home back to green "ตอนนี้เท้าปลอดภัย" |
| 7 | **Pass.** TEST-004 deleted from the phone; Storage "alerts 0 · capture-tagged 0" (all 5 alerts were tagged, so none remain) |

**Why no `PRESSURE_PTI`: the engine was right, my expectation was wrong.**
I reran the app's gate and step rules in Python on the recorded normal
trial:
- after `p`, 20 of 20 left steps passed, with a mean meta1 PTI of
  108.3 kPa·s per step, above `ptiKpaS` 80;
- before `p`, the steps were about 5 kPa·s each.

Decision 1 makes PTI the mean over **all walking steps in the last 60
minutes**, and that window held about 2.5 minutes of normal walking from
when the phone connected (around 140 steps at about 5 kPa·s). With about
55 `p` steps, the mean was about 34 kPa·s. At these numbers `p` would
need about 7 minutes of walking before the mean passed 80.

So the table's "PTI after about 22 s" was wrong: I forgot the earlier
steps in the window. The unit tests cover the boundary exactly, but they
start walking with high PTI from the first step. For SR: PTI responds
over minutes, not seconds, by design. A short high-pressure episode
inside a long normal walk does not raise it.

**Other observation for SR.** On the right foot (normal walk), 43
stances crossed `steps.contactKpa`, but only 27 were within the length
limits. The other 16 were short blips around the 10 kPa contact line,
which the limits rejected. The real-board step count check (SR) should
look at this.

## Decisions (user, 2026-10-24, after the PR)

1. **`pressure.peakHoldMs` 2500: keep it (provisional).** Added to the
   SR checklist next to the step-detection check.
2. **BACKLOG 42: not in S7; scheduled for S8A.** Raise the normal walk's
   motion (gate mean around 0.3 g), test with the contract's statistic,
   keep `t` / `p` / `n`. SR also records the gate statistic with the real
   boards and adjusts `motion.walkingAccelG` if needed. Both added to
   `docs/SESSIONS.md`.

## Decisions needed (as first written)

1. **`pressure.peakHoldMs` = 2500 (new key, provisional).** It replaces
   the plan's "clears after the next step at or below `alertKpa`" for
   PEAK, and applies to WATCH too. OK to keep?
2. **BACKLOG 42, the simulator's normal walk vs the walking gate.**
   Either:
   - raise the normal walk's motion (a change to the simulator's default
     output), and test it with the contract's statistic; or
   - leave it until the real boards set `walkingAccelG` in SR.

   I recommend leaving it. `p` covers the phone check, and the real IMU
   data is what should set the gate.

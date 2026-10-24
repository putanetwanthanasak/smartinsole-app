# Claude Code Session Plan — SmartInsole Flutter App (v2.4)

> Updated 2026-10-24 (v2.5: S6A + S7 on Sat 24, S6B now includes the My feet shell and the Pressure tab. v2.4, 2026-10-22: two sessions a day, all sessions finish by 2026-10-27. v2.3, 2026-10-22: all sessions finish by 2026-10-31; model-input units fixed for S4C/S8A. v2.2: the phone app becomes the research capture tool; new sessions S4C and SR) · Use together with `docs/FLUTTER-PLAN.md` and `docs/design/DESIGN-SPEC.md`
> Run Claude Code on the Ubuntu machine in `~/smartinsole-app`

---

## Status (2026-10-21)

| Session | Result | PR / report |
|---|---|---|
| S0A | ✅ Tools installed (Flutter 3.47.7, Android SDK 36, Note 10, emulator Pixel 7, Claude Code, Dart MCP) | — |
| S0B | ✅ Repo setup, plan docs, `shared/thresholds.json` | PR #15 · report 019 |
| S1A | ◐ Home (4 states) + Foot check (4 screens) designed; Gait, Temperature, Alerts, Connection, Settings still to design | design canvas |
| S1B | ✅ `mobile/` scaffold, theme, bundled fonts, motion, 7 placeholder screens, goldens | PR #16 · report 020 |
| S2A | ✅ Dart parser for N FSR, 69 test vectors from the TS parser, 129 tests | PR #17 · report 021 |
| S2B | ✅ New simulator core; 10-min bleak run: 3,750 packets, 0 gaps, 6.25 Hz; encoders match vectors 33/33 | PR #18 · report 022 |
| S2C | ✅ All 6 opcodes; TARE → NVS; 2 concurrent centrals (laptop 1,896 packets with no gaps while the phone stopped/reconnected); MTU 120 → 4-sample packets live | PR #19 · report 023 |
| S3A | ✅ Per-foot BLE (connect sequence, rules 8/9, reconnect), temporary debug screen, 183 tests; Note 10 checkpoint passed: both feet 6.25 Hz with 0 gaps, interval 11.25 ms | PR #20 · report 024 |
| S3B | ✅ Web app fallback works with the new simulator: 9-min capture, both feet 26 984 rows, no lost packets, 20 ms spacing; resync steps of 160 ms (BACKLOG 28) and reconnect via the picker (BACKLOG 29) handled in `docs/STUDY-FALLBACK.md` | PR #21 · report 025 |
| S4 | ✅ DeviceManager (50 Hz / 10 Hz, read-time staleness, ΔT), DeviceClock (no steps, never backwards), 7 mock presets, 242 tests; Note 10 checkpoint passed: L/R ≤ 3.4 ms (laptop-clock method, ±3 ms), 0 lost over 10.6 min, 20 ± 0.25 ms steps; BACKLOG 27 fixed and seen on the phone | PR #22 · report 026 |
| S4C → S10 | ⏳ All finish by 2026-10-31 (see the schedule below); SR 2–5 Nov; study starts 2026-11-10 | — |

**Demo state of the app:** installed on the Note 10 as a release build; all screens are placeholders ("ยังไม่พร้อมใช้งาน") until their sessions.

## Study plan (decided 2026-10-21)

- **Data collection starts 2026-11-10.** One researcher (the user) runs every session alone and walks beside the volunteer during the abnormal gaits.
- **The phone app is the research capture tool** (new session S4C). Each insole has exactly one central during a study session: the phone. The researcher carries the phone, so Bluetooth range and operating two devices are not a problem.
- **The laptop web app is a fallback only.** S3B now only checks that it can still capture from the new simulator on its own. It is never connected at the same time as the phone during a study session. The dual-central test is dropped.
- **The user is also the AI team**, so the CSV format is designed for training (S4C), not copied from the web app.

What the study protocol (proposal doc 03) needs from the app:

| Protocol step | Needs | Session |
|---|---|---|
| 30 s standing calibration, 5 gaits × 3 min, raw 50 Hz data with labels | Research capture mode | S4 + S4C |
| Warm-compress test: watch alerts and link continuity, alert times recorded | Alert rules + stored alert history | S6A + S7 |
| Volunteer usability tasks: pressure map, alert list, explain an alert message | Home with heatmap, Alerts screen, plain-Thai advice | S5 + S6B + S7 |
| Alert text shown to volunteers | Reviewed by the medical expert | before 2026-11-05 |

Schedule (v2.5, user decision 2026-10-24; v2.4 2026-10-22: two sessions a day, every session finished by 27 Oct):

| Date | Session 1 | Session 2 | Design needed (Claude chat) |
|---|---|---|---|
| Thu 22 Oct | S4 ✅ | S4C | user picks Home style A/B/C → Home, 4 states |
| Fri 23 Oct | S4C Note 10 checkpoint | S5 | Alerts + Temperature |
| Sat 24 Oct | S6A | S7 | My feet (gait) + Connection + Settings |
| Sun 25 Oct | S6B (incl. My feet shell + Pressure tab) | S8A + S8B | Foot check (4 screens, new style) · advisor slides |
| **Mon 26 Oct** | advisor meeting | S8C | — |
| Tue 27 Oct | S9 (simulator boards) | S10 | — |
| Wed 28 Oct – Sun 1 Nov | buffer · changes from the advisor · send alert text to the medical expert | | — |
| Mon 2 – Thu 5 Nov | SR: real boards + full 75-minute rehearsal | | — |
| Fri 6 – Mon 9 Nov | buffer, expert text changes, final install | | — |
| **Tue 10 Nov** | study starts | | — |

If a day slips, move S8A, S8B, S8C to after 10 Nov first (not needed for the study). Never drop S4C, S5, S6A, S7 or S6B. **During the study (10–30 Nov) the study phone's build is frozen:** new work goes on branches and is tested on the emulator or another phone.

If real boards are not ready by 2 Nov, SR runs on the simulator and the real-board check moves to the buffer days.

### Decisions made during S2A–S2C
- Parser keeps `lengthMismatch`: every sensor notification must be exactly `8 + count × (2N + 12)` bytes; never padded.
- Simulator verification uses a laptop bleak script (`firmware/simulator/tools/sim_check.py`) and `shared/test_vectors/`, not the web app. The web app first connects to the new simulator in S3B.
- Normal synthetic walk stays below `watchKpa` (heel peak ≈ 60 kPa); higher pressure comes from the future scenario mode (BACKLOG 18).
- Simulated battery never falls below 50 %; low battery comes from scenario mode.
- `seq` restarts at 0 on every `START_STREAM`, per connection; `t0_ms` counts from boot and never restarts (BACKLOG 19 asks the contract owner to add this).
- Rule 9 design for S3A/S4 (BACKLOG 20): primary checks are (1) drop packets before this connection's START is acknowledged and (2) `t0` never goes backwards within a connection. Seq look-ahead is only an optional idea. (S4: check 1 now opens at the START write, not its ack; BACKLOG 27.)
- Opcode scope: START, STOP, SYNC_TIME per connection; SET_RATE, TARE, REBOOT device-wide.
- SET_RATE accepts only 50 Hz (other values logged and ignored) because the packet has no sample-spacing field (rule 1).
- TARE in the simulator = per-channel minimum over one stride (55 samples), flags bit1 during the window.
- SYNC_TIME is validated (8-byte payload) and logged only; nothing changes on the wire.
- BACKLOG 21: the phone app must guard REBOOT and TARE (confirmation dialog, no research capture running, or hidden during the study); real TARE needs the foot lifted off the insole.

### Carry-forward notes for later sessions
- **S3A:** request MTU 247 on every connect and reconnect. At MTU 23 the simulator sends nothing (by design) with no error, so the app must show a problem state if the MTU is too small. Pick the device by service UUID and judge the side only by `foot_side` (BlueZ/Android cache device names).
- **S3A:** opening the ESP32 serial port resets the board; start any serial log before connecting centrals.
- **S4:** `deviceMs` uint32 wrap; L/R timing check ±10 ms. The Note 10 grants an 11.25 ms connection interval after the HIGH request (BACKLOG 25).
- **S4:** the first packet after START can be dropped as "before START" when Android delivers it before the write ack; the gap counter misses it (BACKLOG 27).
- **S4:** do not copy the web app's resync formula (offset = send time − last received sample): it is quantised to the 160 ms packet period and gives ±160 ms steps (BACKLOG 28). Anchor the offset to each packet's own arrival time.
- **S4 checkpoint:** the left board's USB (laptop port 3-6, old cable) re-enumerated 4 times at plug-in and dropped once in S3B; replace that cable or use another port before the next serial log. (Done in S4: new cable, port 6, no drops.)
- **Note 10 checkpoints:** restart adb (`adb kill-server`) if it loses the phone while USB stays attached; serial output can be garbage for the first minutes after plugging in a board, so check it reads cleanly before a test; if it stays garbled, kill that logger by PID and reopen it before the phone connects (S4).
- **S4C:** read `DeviceManager.batches` (50 Hz, unix-timed, raw ADC kept) and take the column order from `shared/model_input.json`; write `seq`.
- **S7:** `thresholds.json` has no battery threshold (BACKLOG 30); confirm with the contract owner that PTI and concentration are per step, as the mock presets assume (BACKLOG 31). (Done in S7: per step, user decision; still to send to the contract owner.)
- **S9:** the L/R timing check needs both boards' serial logs on one laptop; real insoles have no serial port, so it needs another reference (report 026).
- **S5 / S7:** zero load reads ≈ 0.01 kPa (display rounding); ADC 4095 ≈ 37,000 kPa (saturation; flags bit0).
- **S8B:** REBOOT/TARE guard (BACKLOG 21).

### Waiting on others
- **Phumirapee (hardware):** final FSR/NTC count and positions; NTC 6 per foot possible?; exact-length packets; SET_RATE must not change the real rate (or add a spacing field); contract gaps BACKLOG 15, 16, 19.
- **Phumirapee:** when will the real boards be ready? Needed by 2026-11-02 for SR.
- **Advisor (2026-10-26):** daily foot check in scope?; IRB notification needed?; medical expert to review advice text; NTC 6 per foot.
- **User:** a full-app redesign started on 2026-10-20 (three Home directions A/B/C on the design canvas). Pick one before S5; the Alerts and Temperature designs are needed before S6B. DESIGN-SPEC is updated after the choice.

---

## 0. Rules for every session

| Topic | Rule |
|---|---|
| Order | **Plan → Do → Verify → Report.** Never skip a step. |
| Plan approval | Use plan mode, then **stop and wait for the user's approval** before changing anything. |
| Git | Branch `work/<topic>` from the latest `main` → push → open a PR → **the user merges**. Never push to `main`. |
| Report | `docs/reports/NNN-<name>.md` (next number after the highest existing one) + a chat summary of at most 10 lines |
| Size | If a session is too big, split it into sub-sessions (A, B, …); each sub-session still does all 4 steps. |
| New session | The user runs `/clear` before every session. |
| Web app | **Do not modify** unless the user asks because of a bug that affects data capture. |
| Uncertainty | Never guess. Ask. |
| Language | English for everything you write: code, comments, commits, reports, docs. Thai only for quoted UI strings. |

### Step 1: Plan
1. Read `CLAUDE.md`, `mobile/CLAUDE.md` (if it exists), `docs/FLUTTER-PLAN.md`, the relevant parts of `docs/DATA-CONTRACT.md` / `docs/design/DESIGN-SPEC.md`, and the latest reports.
2. Check the session's "Requires". If anything is missing, stop and say so.
3. Propose a plan: files to create/change, ordered steps, how each "Done when" item will be verified, risks, open questions.
4. **Stop and wait for approval.**

### Step 2: Do
- Create the branch; commit in small steps.
- Stay within scope. Problems found outside scope go into the report, not into code.

### Step 3: Verify
- Flutter work: `flutter analyze` has no errors and `flutter test` passes.
- Check your diff against the 16 rules in `docs/FLUTTER-PLAN.md` section 6, one relevant rule at a time.
- Check every "Done when" item.
- **UI checks are done by you, not the user:** run the app on the Android emulator (`flutter run -d emulator-…`, with `MockDataSource` when no ESP32 is needed), use the Dart & Flutter MCP server to take screenshots, inspect the widget tree and read runtime errors, and compare against `docs/design/DESIGN-SPEC.md`. Add golden tests for every screen state you build. Put the screenshots you checked into the report.
- **The user tests on the Note 10 only at the checkpoints listed in section 2** (anything needing real Bluetooth or the real camera). For those, write a checklist for the user and **wait for their results**. Never mark them passed yourself.
- If the Dart MCP server is not connected or no emulator is running, stop and tell the user what to start; do not skip the check.

### Step 4: Report
1. Write the report: what was done / result of each check (pass, fail, waiting on user) / leftovers / decisions needed / suggestion for next session.
2. Update `docs/BACKLOG.md` if there is new leftover work.
3. Commit → push → open PR.
4. Short chat summary pointing to the report.

---

## 1. Prompt template (prompts are always in English)

```
Session [ID]: [title]
Read docs/SESSIONS.md section 0 and follow it in order: Plan → Do → Verify → Report.
Use plan mode and stop for my approval before writing any code.
Session details are in docs/SESSIONS.md, section [ID].
Additional info: [optional]
```

---

## 2. Overview

**Test tooling (set up by the user before S1B):** an Android emulator (Pixel 7, created in Android Studio → Virtual Device Manager) and the Dart & Flutter MCP server (`claude mcp add --transport stdio dart -- dart mcp-server`, run once in the repo root). The MCP runtime tools need `flutter run` running in a separate terminal.

**Simulator tooling:** PlatformIO; ESP32 on a CP2102 bridge (select the port by `/dev/serial/by-id/usb-Silicon_Labs_CP2102…`; the other ttyUSB is a Quectel LTE modem, never touch it); user `pumon` in `dialout`; laptop checks with `firmware/simulator/tools/sim_check.py` (bleak); phone checks with nRF Connect.

**Note 10 checkpoints (user):** after S3A (both ESP32 connect) ✅, S4 (left/right timing), S4C (a full capture session on the phone), SR (study rehearsal with real boards), S8C (real camera), S9 (full 30-minute run).

| Date | Session | Who | Work | Branch |
|---|---|---|---|---|
| 0 | S0A ✅ | User | Install Flutter, SDK, Note 10, Claude Code | — |
| 0 | S0B ✅ | Claude Code | Repo setup + docs | `work/repo-setup` |
| 1 | S1A ◐ | Claude chat + user | Design: Home ✅, Foot check ✅, 5 more screens (in parallel) | — |
| 1 | S1B ✅ | Claude Code | `mobile/` scaffold + theme + fonts + shared motion + 7 empty screens + golden-test setup | `work/flutter-scaffold` |
| 2 | S2A ✅ | Claude Code | Parser + test vectors | `work/flutter-parser` |
| 2 | S2B ✅ | Claude Code + user | New simulator: core | `work/sim-core` |
| 3 | S2C ✅ | Claude Code + user | New simulator: control + 2 concurrent connections | `work/sim-control` |
| 21 Oct | S3A ✅ | Claude Code + user | BLE, both feet | `work/flutter-ble` |
| 21–22 Oct | S3B ✅ | Claude Code + user | Web app fallback check (laptop only) | `work/webapp-fallback-check` |
| 22 Oct | S4 ✅ | Claude Code + user | DeviceManager + timing checks | `work/flutter-device-manager` |
| 22–23 Oct | S4C | Claude Code + user | Research capture mode | `work/flutter-capture` |
| 23 Oct | S5 ✅ | Claude Code | Heatmap + Home + animation (style D) | `work/s5-home-style-d` |
| 24 Oct | S6A ✅ | Claude Code | SQLite (drift) | `work/flutter-storage` |
| 24 Oct | S7 | Claude Code | 8 alert rules + risk level + 3-level mapping | `work/flutter-rules` |
| 25 Oct | S6B | Claude Code | My feet shell + Pressure, Temperature and Alerts screens | `work/flutter-temp-alerts` |
| 2–5 Nov | SR | User + Claude Code | Study rehearsal with real boards | `work/study-readiness` |
| 25 Oct | S8A | Claude Code | Gait screen + model slot | `work/flutter-gait` |
| 25 Oct | S8B | Claude Code | Connection + Settings screens | `work/flutter-connect-settings` |
| 26 Oct | S8C | Claude Code + user | Daily foot check | `work/flutter-footcheck` |
| 27 Oct | S9 | User + Claude Code | Integration test + APK | `work/flutter-integration` |
| 27 Oct | S10 | Claude Code | Wrap-up + docs + screenshots | `work/flutter-wrapup` |

---

## 3. Session details

### S0B — Repo setup ✅
- **Requires:** S0A done; repo at `~/smartinsole-app`; the 3 plan files available.
- **Do:**
  1. Put the plan files at `docs/FLUTTER-PLAN.md`, `docs/SESSIONS.md`, `docs/design/DESIGN-SPEC.md`.
  2. Create `shared/` with `thresholds.json` (copied from `public/thresholds.json`) and `shared/README.md` explaining the web app still uses `public/` (frozen).
  3. Create `firmware/simulator/README.md` (placeholder until S2B) and `.gitignore` entries for `.pio/`, `mobile/build/`, `.dart_tool/`.
  4. Add a "Flutter app (Oct 2026)" section to `CLAUDE.md`: web app frozen, pointers to `docs/FLUTTER-PLAN.md` and `docs/SESSIONS.md`.
- **Verify:** `npm ci && npm run build` passes (web not broken); `git status` shows no build output.
- **Done when:** PR is open.

### S1A — Design (in Claude chat, not Claude Code)
- First version: Home (4 states) ✅ · Foot check (4 screens) ✅
- Redesign (started 2026-10-20): three Home directions on the canvas; the user picks one, then every screen is redone in that style (Home before S5, Alerts/Temperature before S6B, the rest after the study starts).
- Results go into `docs/design/DESIGN-SPEC.md` once approved.

### S1B — `mobile/` scaffold + theme ✅
- **Requires:** S0B merged.
- **Do:**
  1. `flutter create --platforms android --org th.ac.kmutt.smartinsole mobile` (ask the user to confirm the package id first).
  2. Add only the packages needed now (latest stable): Riverpod, `flutter_animate`, `animations`.
  3. `lib/` folders as in FLUTTER-PLAN section 3.
  4. Theme from DESIGN-SPEC: colours, type scale, radii, spacing.
  5. **Bundle fonts** IBM Plex Sans Thai and IBM Plex Sans Thai Looped in `assets/fonts/` (from Google Fonts or IBM's GitHub; check the OFL licence).
  6. Shared motion file `lib/ui/motion.dart` (durations, curves, reduce-motion check).
  7. 7 empty screens + bottom bar with 4 tabs (Home, Gait, Temperature, Alerts) + Settings button + routes to Connection and Foot check.
  8. Home placeholder includes the slot for the "foot check not done today" card (no logic yet).
  9. `mobile/CLAUDE.md`: the 16 rules, common commands, motion rules, "do not touch the web app", English-only rule, and the testing approach (emulator + Dart MCP + golden tests; Note 10 only at the 4 checkpoints).
  10. Golden-test setup (Thai fonts loaded in tests so goldens render real glyphs) + one golden per empty screen.
- **Verify:** analyze/test pass · widget test that every screen opens · **You:** run on the emulator, switch through all 7 screens, take screenshots via the Dart MCP server, confirm Thai text renders with the bundled fonts and the theme matches DESIGN-SPEC.
- **Done when:** all 7 screens reachable on the emulator, screenshots in the report, goldens committed.

### S2A — Parser + test vectors ✅
- **Requires:** S1B merged.
- **Do:** a Node script that uses the existing TS parser (read-only, do not modify the web app) to generate `shared/test_vectors/*.json` (normal packet, `count` < 8, ADC 0/4095, `offset_adc`, temperature `-32768`, quality 1/2, every status state, calibration blob) → Dart parser supporting N FSR → unit conversion per `BLE-INTERFACE.md`.
- **Verify:** 100% of test vectors pass; N = 4/6/8 pass; kPa matches TS to 3 decimal places.
- **Done when:** Dart and TS give identical values for every case.

### S2B — New simulator: core ✅
- **Requires:** S0B merged; PlatformIO installed; at least one BLE-capable ESP32.
- **Do:** PlatformIO + NimBLE-Arduino per `BLE-INTERFACE.md`: advertise the Service UUID, 5 GATT characteristics, sensor stream 8 samples/packet at 6.25 Hz (synthetic gait data), temperature every 30 s, status; build flags `FOOT_SIDE` and `FSR_COUNT`. Keep data generation in separate functions (future scenario mode).
- **Verify:** `pio run` passes for both L and R envs · packet encoders reproduce `shared/test_vectors/` byte-for-byte (`pio test -e native`) · flash and check the live stream with the laptop bleak script (`firmware/simulator/tools/sim_check.py`): exact packet sizes, no `seq` gaps, 6.25 Hz, temperature every 30 s, status. The web app is not used here; its first connection to the new simulator is in S3B.
- **Done when:** the bleak script passes a 10-minute live run and the encoder tests match every test vector.

### S2C — New simulator: control ✅
- **Requires:** S2B merged.
- **Do:** `START/STOP/SYNC_TIME/SET_RATE/TARE/REBOOT`, calibration blob (JSON, long read), at least 2 concurrent connections. **Do not** implement `0x10 SET_SCENARIO` now (backlog).
- **Verify:** the laptop bleak script covers the `docs/BLE-TEST-CHECKLIST.md` items that apply to the simulator (every opcode, calibration long read), and two centrals connect at once; one disconnecting or sending `STOP_STREAM` does not stop the other's stream. Packet bytes still match `shared/test_vectors/`. The web app is not used here; its first connection to the new simulator is in S3B.
- **Done when:** the bleak checks pass and nothing deviates from the contract.

### S3A — BLE, both feet ✅
- **Requires:** S2A and S2C merged; L and R boards flashed (second board → `pio run -e right`).
- **Do:** one `BleDataSource` per foot following FLUTTER-PLAN section 5; reject wrong side; auto-reconnect (request MTU 247 again on every reconnect); runtime permissions; temporary debug screen; rule 9 checks from BACKLOG 20.
- **Verify:** unit test of the connect sequence with a fake BLE · **User:** connect both, power-cycle a board and confirm auto-reconnect, swap slots and confirm rejection.
- **Done when:** both feet stream continuously for 5 minutes.

### S3B — Web app fallback check (reduced scope, decided 2026-10-21) ✅
- **Requires:** S3A merged; Google Chrome on Ubuntu.
- **Why:** the phone is now the capture tool (S4C). The laptop web app must still work as a fallback if phone capture fails on a study day. This is the frozen web app's first connection to the new simulator.
- **Do:** check on paper, then live, that the web app connects to both new simulator boards on its own (no phone connected), accepts per-connection `seq` (restarts at 0 on START) and boot-based `t0_ms`, that its report-015 stale check does not misfire, and that its raw capture mode exports a usable CSV. A small script analyses that CSV (missing `seq`, sample spacing, both feet present). **Do not modify the web app**; if it cannot capture correctly, stop and report the smallest fix, and the user decides.
- **Verify (user runs it, sends results):** 5 minutes of web-app raw capture from both boards, no missing `seq`, 20 ms spacing.
- **Done when:** the fallback capture works, or the problem and the smallest fix are documented for the user to decide.

### S4 — DeviceManager + timing
- **Do:** 50 Hz processing / 10 Hz display, read-time staleness, ΔT null when a foot is missing, `seq` gap detection, stale-packet drop, `SYNC_TIME` every 5 min, temperature history, timing log. Also a `MockDataSource` (same interface as `BleDataSource`) with presets for every Home state (safe, watch, rest, no data, one foot missing, low battery) so later UI sessions can run on the emulator without ESP32. Selectable only in debug builds.
- **Verify:** unit tests (stale, ΔT null, stale packet, seq wrap at 65535, `deviceMs` uint32 wrap) · **User:** run 10 minutes and send the log.
- **Done when:** L/R offset ≤ ±10 ms, 20 ms spacing, no lost packets. **Do not start S5 if this fails.**

### S4C — Research capture mode (new, decided 2026-10-21)
- **Requires:** S4 merged.
- **Do:** a researcher-only capture flow in the app, built for one person who walks beside the volunteer:
  1. Session setup: subject code (no names), room temperature, pre-checks (both feet streaming, battery ≥ 80 % on both, firmware/calibration recorded). Generates the trial order: normal gait first, then the 4 abnormal gaits in a random order per subject; simulated-pain side by odd/even subject number (proposal doc 03).
  2. 30 s standing calibration trial, then each gait trial: 3-minute timer that stops and saves by itself, sound + vibration cues at start, 10 s before the end and at the end, long press to stop early, "redo trial" (the old file is kept and marked invalid), large touch targets, screen kept on (`wakelock_plus`), no accidental input while the phone is in a pocket.
  3. Link loss during a trial: vibrate, keep recording after reconnect, and record the gap in the file.
  4. Files in the app's private storage: one CSV per trial (unix time from S4, side, seq, raw ADC and kPa per channel, IMU, temperature, flags) + one JSON sidecar (subject code, gait class, pain side, start/end, room temperature, app/firmware versions, calibration, gaps). **Model-input convention (user decision 2026-10-22):** FSR in kPa (raw ADC kept too), accel in g, gyro in °/s, and the 24 model channels in the exact order of DATA-CONTRACT §7.1. The app and the training scripts must use the same conversion code path (checked against `shared/test_vectors/`), so a model trained on these files runs unchanged in the app. Do not copy the web app's resync offset formula (BACKLOG 28). Export to the laptop over USB (`adb pull` script) with a manifest and checksums.
  5. A short `docs/STUDY-CAPTURE.md` for the user: the exact study-day steps on the phone, and how to export.
- **Verify:** unit tests (trial order and pain-side rules, timer stop, file contents, gap recording, redo) · **You:** emulator with `MockDataSource` for the flow, screenshots · **User checkpoint (Note 10):** one full simulated session with both simulator boards (calibration + 5 trials, shortened timers allowed), export, and the analysis script confirms 50 Hz with no gaps.
- **Done when:** a full session can be run alone on the phone and the exported files load cleanly in Python.

### S5 — Heatmap + Home
- **Do:** heatmap with `CustomPainter` from `sensor_layout.json`; Home per DESIGN-SPEC in all 4 states; animations per FLUTTER-PLAN section 8.
- **Verify:** widget + golden tests for the 4 states (no-data must not be green); reduce-motion disables animations · **You:** run on the emulator with each `MockDataSource` preset, screenshot via Dart MCP, compare with DESIGN-SPEC, check for jank in the 10 Hz updates.
- **Done when:** matches the mockup in every state and runs smoothly on the emulator. (Real-sensor check happens at the S9 checkpoint.)

### S6A — SQLite
- **Do:** tables for alerts, temperature history, daily summary, foot-check entries (date, answers, photo paths) with `drift`, behind a repository pattern.
- **Verify:** unit tests for write/read/delete of data older than 30 days.
- **Done when:** data survives an app restart.
- **Result (report 029):** drift schema v1 behind 4 repository interfaces; 30-day retention (alerts of a research capture are kept); app backup and device transfer turned off.

### S6B — My feet shell + Pressure, Temperature + Alerts
- **Requires:** S5 and S6A merged; these two designs approved.
- **Do:** per DESIGN-SPEC + animations: the My feet shell with its sub-tabs and the Pressure tab (DESIGN-SPEC §8, §8.1), the Temperature tab (§8.2) and the Alerts list and detail (§7). Read alerts, temperatures and summaries only through the S6A repositories; the list uses `AlertRepository.watchVisible` (same visibility rule as the badge).
- **Verify:** widget + golden tests · **You:** emulator + mock presets (including ΔT above threshold and one foot missing), screenshots via Dart MCP.
- **Done when:** both screens show mock data correctly in every state.

### S7 — Alert rules
- **Do:** 8 codes per contract §8.3, walking gate, ΔT 2 consecutive readings, 30-minute repeat suppression, level 1–5 (max), 3-level mapping per FLUTTER-PLAN section 7, plain-Thai advice for every code, thresholds from `thresholds.json`.
- **Verify:** unit tests for every code (trigger / no trigger / boundary) and every row of the mapping table.
- **Done when:** every rule passes; no threshold numbers in code.
- **Result (report 030):** `AlertEngine` with all 8 codes on the 50 Hz path, walking gate and step detection (per-step PTI, concentration and asymmetry, user decision); suppression read back from the alerts table (holds across a restart); Home status from the engine (BACKLOG 37/38); research alerts tagged, exported as `alerts.csv` and deleted with their capture (BACKLOG 40); simulator serial scenarios `t`/`p`/`n`/`?`. Note 10 check pending the user.

### SR — Study readiness (new, decided 2026-10-21)
- **Requires:** S4C, S5, S6A, S7, S6B merged; real boards from Phumirapee (fall back to the simulator if not ready).
- **Do:** run the full protocol from proposal doc 03 end to end on the phone (about 75 minutes): device checklist, calibration, 5 trials, warm-compress alert check, the 3 usability tasks, export. Confirm the alert text the volunteers will see is the version the medical expert reviewed. Install the final build.
- **Verify (user runs it, sends results):** all trial files complete at 50 Hz with no unexplained gaps; alerts appear with times recorded; nothing on the phone needs the laptop.
- **Also check with the real boards (added in S7):**
  - **Step detection.** In one normal-gait trial, count the volunteer's steps by hand (per foot) and compare with the app's count of walking steps (`steps.contactKpa`, `minStanceMs`, `maxStanceMs` and the walking gate `motion.*` are provisional). Adjust `thresholds.json` if they disagree.
  - **How often `PRESSURE_PTI` and `LOAD_CONCENTRATION` fire** during the normal-gait trials (from each session's `alerts.csv`). Both use provisional readings (BACKLOG 31); frequent firing on healthy volunteers' normal gait means the values need review before the study.
  - The warm-compress step is done with the session screen open, so its `TEMP_DELTA` lands in that session's `alerts.csv` (`docs/STUDY-CAPTURE.md`).
- **Done when:** the user is confident to run the study on 2026-11-10.

### S8A — Gait screen
- **Do:** PAI, CoP, step count, label "estimate, not a diagnosis", animations. `GaitClassifier` interface with a rule-based implementation and a TFLite implementation in an isolate per DATA-CONTRACT §7: loads `assets/models/model_a.tflite` + `normalization.json` when present, input `[1,100,24]` (2 s window, 1 s stride, channel order §7.1, units as in S4C), outputs `gait_probs` [1,5] and `gait_embedding` [1,32]; falls back to the rules when the model is missing or confidence < 0.60. Prove the slot with a dummy model of the right shapes generated by a committed Python script (untrained weights): loads, channel order correct, inference ≤ 100 ms on the Note 10. Swapping in the real model in December must need only the two asset files. Model B stays out of scope (S7 rules give the status level).
- **Verify:** unit + golden tests · **You:** emulator + mock presets, screenshots via Dart MCP.
- **Done when:** values shown from mock data; classifier swappable without touching the screen.

### S8B — Connection + Settings
- **Do:** connect left/right separately, per-side status, battery, firmware, scanning/success animations · Settings: text size, sound, TARE (with confirmation; BACKLOG 21 guard), foot-check reminder time, app info · hide the debug screen.
- **Verify:** golden tests for every connection state (scanning, connected, wrong side, error) · **You:** emulator with mock connection states, screenshots via Dart MCP. (Connecting real devices unaided is checked at the S9 checkpoint.)
- **Done when:** every state renders per DESIGN-SPEC.

### S8C — Daily foot check
- **Requires:** S6A merged.
- **Do:** 4 screens per DESIGN-SPEC; Home card shown until today's check is done; camera with guide outline + self-timer; photos in the app's private folder; compare with yesterday; 3 questions; "not sure" = abnormal; abnormal result logged as an alert; in-app evening reminder; photos deletable.
- **Verify:** unit/widget/golden tests for answer logic and the Home card · **You:** emulator (its virtual camera) for the flow · **User checkpoint:** real photos on the Note 10; photos do not appear in the gallery.
- **Done when:** a full check takes about 1 minute and photos stay inside the app.

### S9 — Integration + APK
- **Do:** integration checklist; 30 minutes with 2 boards on the phone (simulator boards; real boards are SR); battery and smoothness; reduce-motion; release APK. **User checkpoint** also covers: press sensors and watch the right dots change, warm one temperature sensor and watch ΔT, connect both insoles unaided.
- **Done when:** the APK works for 30 minutes with no serious issues.

### S10 — Wrap-up
- **Do:** fix leftover bugs; update `mobile/CLAUDE.md`, `docs/PROGRESS.md`, `docs/BACKLOG.md`; screenshots of every screen in `docs/screenshots/`.
- **Done when:** docs match the code.

---

## 4. If a session fails
- Do not start any session whose "Requires" depends on it.
- Open `S<ID>-fix` and do all 4 steps.
- If stuck for more than a day, the user brings it back to Claude chat to re-plan.

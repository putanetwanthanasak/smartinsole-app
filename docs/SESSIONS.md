# Claude Code Session Plan — SmartInsole Flutter App (v2.6)

> Updated 2026-10-29 (v2.6: the real insole is final at 8 FSR + 8 NTC per foot; new session S8D (split S8D-1 / S8D-2); real boards about 8 Nov, SR 8–11 Nov, study starts 2026-11-12. v2.5, 2026-10-24: S6A + S7 on Sat 24, S6B now includes the My feet shell and the Pressure tab. v2.4, 2026-10-22: two sessions a day, all sessions finish by 2026-10-27. v2.3, 2026-10-22: all sessions finish by 2026-10-31; model-input units fixed for S4C/S8A. v2.2: the phone app becomes the research capture tool; new sessions S4C and SR) · Use together with `docs/FLUTTER-PLAN.md` and `docs/design/DESIGN-SPEC.md`
> Run Claude Code on the Ubuntu machine in `~/smartinsole-app`

---

## Status (2026-10-29)

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
| S4C | ✅ Research capture mode on the phone | PR #23 · report 027 |
| S5 | ✅ Home (style D), 4-tab navigation | PR #24 · report 028 |
| S6A | ✅ Local storage (drift), retention | PR #25 · report 029 |
| S7 | ✅ AlertEngine (8 codes) | PR #26 · report 030 |
| S6B | ✅ Alerts list and detail (part 1), My feet shell, Pressure and Temperature tabs (part 2) | PR #27, #29 · reports 031, 033 |
| S8A | ✅ Gait tab, GaitClassifier + Model A slot | PR #30 · report 034 |
| S8B | ✅ Connection, Settings, Researcher | PR #31 · report 035 |
| S8C | ✅ Daily foot check, evening reminder | PR #32 · report 036 |
| S8D → S10 | ⏳ S8D-1 30 Oct, S8D-2 31 Oct, S9 1–3 Nov, S10 4–5 Nov (schedule v2.6 below); SR 8–11 Nov; study starts 2026-11-12 | — |

**Demo state of the app:** installed on the Note 10 as a release build (S8C); every screen is built. Until S8D-1 the app and the simulator boards are on 6 FSR + 2 temperature sites per foot.

## Study plan (decided 2026-10-21)

- **Data collection starts 2026-11-12** (moved from 10 Nov on 2026-10-29, inside the IRB window 1–30 Nov). One researcher (the user) runs every session alone and walks beside the volunteer during the abnormal gaits.
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

Schedule (v2.6, user decision 2026-10-29: the real insole is final at 8 FSR + 8 NTC per foot, NTC i next to FSR i; the IRB confirmed no amendment is needed; real boards ready about 8 Nov):

| Date | Session | Notes |
|---|---|---|
| Thu 29 Oct | S8C Note 10 run · S8D plan | S8C merged (PR #32) |
| Fri 30 Oct | **S8D-1** (data path) + its Note 10 checkpoint | both simulator boards reflashed to 8 + 8 |
| Sat 31 Oct | **S8D-2** (UI for 8 sites) | requires S8D-1 merged |
| Sun 1 – Tue 3 Nov | S9 (integration + APK) | first item: BACKLOG 51; the user answers the web-fallback decision (BACKLOG 63) before S9 |
| Wed 4 – Thu 5 Nov | S10 (wrap-up) | **medical text review by Thu 5 Nov** (Appendix A) |
| Fri 6 – Sat 7 Nov | buffer | |
| Sun 8 – Wed 11 Nov | SR with the real boards | boards ready about 8 Nov; the simulator if not |
| **Thu 12 Nov** | **study starts** | IRB window 1–30 Nov; study phone build frozen 12–30 Nov |

Earlier schedules (v2.5, 2026-10-24; v2.4, 2026-10-22) put SR on 2–5 Nov and the study start on 10 Nov; both are replaced by the table above.

If a day slips, use the buffer (6–7 Nov) first. S8D-1 is needed for the study (the real boards speak only the v1.6 format); S8D-2 is the UI for 8 sites and S10 is wrap-up. **During the study (12–30 Nov) the study phone's build is frozen:** new work goes on branches and is tested on the emulator or another phone.

If real boards are not ready by 8 Nov, SR runs on the simulator boards (8 + 8 since S8D-1) and the real-board checks move to the last SR days.

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
- **Phumirapee (hardware):** firmware to DATA-CONTRACT v1.6 (8 FSR + 8 NTC, 232-byte sensor packets, 32-byte temperature v2; the contract's Appendix C is the hand-off the user sends); exact-length packets; SET_RATE must not change the real rate (or add a spacing field); contract gap BACKLOG 19. (Count and positions decided 2026-10-29.)
- **Phumirapee:** real boards ready about 8 Nov for SR.
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

**Note 10 checkpoints (user):** after S3A (both ESP32 connect) ✅, S4 (left/right timing), S4C (a full capture session on the phone), SR (study rehearsal with real boards), S8C (real camera), S8D-1 (both simulator boards on 8 + 8), S9 (full 30-minute run).

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
| 8–11 Nov | SR | User + Claude Code | Study rehearsal with real boards | `work/study-readiness` |
| 25 Oct | S8A | Claude Code | Gait screen + model slot | `work/flutter-gait` |
| 25 Oct | S8B | Claude Code | Connection + Settings screens | `work/flutter-connect-settings` |
| 26 Oct | S8C ✅ | Claude Code + user | Daily foot check | `work/flutter-footcheck` |
| 30 Oct | S8D-1 | Claude Code + user | 8 FSR + 8 NTC: data path, simulator, contract v1.6 | `work/flutter-8-sensors` |
| 31 Oct | S8D-2 | Claude Code | 8 FSR + 8 NTC: UI | `work/flutter-8-sensors-ui` |
| 1–3 Nov | S9 | User + Claude Code | Integration test + APK | `work/flutter-integration` |
| 4–5 Nov | S10 | Claude Code | Wrap-up + docs + screenshots | `work/flutter-wrapup` |

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
- **Result (report 030):** `AlertEngine` with all 8 codes on the 50 Hz path, walking gate and step detection (per-step PTI, concentration and asymmetry, user decision); suppression read back from the alerts table (holds across a restart); Home status from the engine (BACKLOG 37/38); research alerts tagged, exported as `alerts.csv` and deleted with their capture (BACKLOG 40); simulator serial scenarios `t`/`p`/`n`/`?`. Note 10 checkpoint 7/7 passed; **accepted by the user 2026-10-24**. `PRESSURE_PTI` (60-min mean) is not expected to fire in 3-min study trials; its evaluation relies on the unit tests.

### SR — Study readiness (new, decided 2026-10-21)
- **Requires:** S4C, S5, S6A, S7, S6B merged; real boards from Phumirapee (fall back to the simulator if not ready).
- **Do:** run the full protocol from proposal doc 03 end to end on the phone (about 75 minutes): device checklist, calibration, 5 trials, warm-compress alert check, the 3 usability tasks, export. Confirm the alert text the volunteers will see is the version the medical expert reviewed. Install the final build.
- **Verify (user runs it, sends results):** all trial files complete at 50 Hz with no unexplained gaps; alerts appear with times recorded; nothing on the phone needs the laptop.
- **First, on the first real-board connection (added in S8D, user decision 2026-10-29):** on Researcher › Diagnostics, each foot must show N = 8 (from its calibration), "temperature v2, 8 sites" and 0 rejects. If not, **stop** and compare the boards' packets and calibration JSON against DATA-CONTRACT v1.6 Appendix C before anything else: the app refuses N ≠ 8, the old 12-byte temperature packet and any temperature packet that is not 32 bytes with count 8, by design.
- **Also check with the real boards (added in S7):**
  - **Step detection.** In one normal-gait trial, count the volunteer's steps by hand (per foot) and compare with the app's count of walking steps. These keys are provisional: `steps.contactKpa`, `minStanceMs` and `maxStanceMs`, the dip keys added in S9 (BACKLOG 51) and the walking gate `motion.*`. Adjust `thresholds.json` if the counts disagree. Kept after S9's fix (user decision 2026-10-25): a real foot with a weak midfoot is the case the fix targets, and only a hand count shows it works. Also note how many stances are rejected as too short (in the S7 simulator run, 16 of 43 right-foot stances were blips around `contactKpa`).
  - **Peak hold** (`pressure.peakHoldMs` 2500, provisional, user decision 2026-10-24). In the same trial, check that `PRESSURE_WATCH` / `PRESSURE_PEAK` hold steadily through a walk rather than ending and restarting between steps (one alert per walk, not one per stride), and that they end within a few seconds of stopping. Adjust it in `thresholds.json` if not.
  - **Walking gate statistic** (BACKLOG 42, user decision 2026-10-24). Record the gate statistic (mean |‖a‖ − 1 g| over `motion.walkingWindowMs`) in the standing calibration and in each normal-gait trial, and adjust `motion.walkingAccelG` in `thresholds.json` if standing and walking do not sit clearly on either side of it.
  - **How often `PRESSURE_PTI` and `LOAD_CONCENTRATION` fire** during the normal-gait trials (from each session's `alerts.csv`). Both use provisional readings (BACKLOG 31); frequent firing on healthy volunteers' normal gait means the values need review before the study. **`asymmetry.concentrationPct` (40 %) was set for 6 sensors and now divides by 8 zones** (an even share drops from 16.7 % to 12.5 %); S8D kept it unchanged on purpose. Record the per-step top-zone share in the normal-gait trials and decide whether 40 % still means "one point carries too much" (BACKLOG 64). The same goes for `steps.contactKpa` (now a sum over 8 zones) and the `gait.*` shares (BACKLOG 65).
  - **Rule-based gait classes** (added in S8A, user decision 2026-10-25). For each of the 5 gait trials, note the class the Gait tab shows (My feet › การเดิน, "(กฎพื้นฐาน)" results; the release build has no model) against the instructed gait, in a small confusion table (rows = instructed gait, columns = class shown; "no result" is a column). The `gait.*` keys in `thresholds.json` are provisional best guesses (DATA-CONTRACT §8 S8A addendum): tune them before 2026-11-12 if the table shows they misclassify. Since S8D the heel share is zones 5 + 7 and the forefoot share zones 0–3, out of 8 zones (BACKLOG 65). Rule-based classes are display-only estimates: they add no gait note (only Model A results do) and never change a level (rule 11). `rotated_foot` is model-only, so the rules can never show it.
  - The warm-compress step is done with the session screen open, so its `TEMP_DELTA` lands in that session's `alerts.csv` (`docs/STUDY-CAPTURE.md`).
- **Clear the test data before 2026-11-12 (added in S6B).** On the study phone, Research capture → **4 · App database (test data)** → *Clear app database (test data)* (2 confirmations; see `docs/STUDY-CAPTURE.md`). It deletes untagged alerts, temperature readings, daily summaries, foot checks and foot photos; it never deletes capture-tagged alerts, capture session folders or the export folder. Then restart the app and confirm on Researcher › Diagnostics (S8B) that "alerts N" equals "capture-tagged N".
- **Done when:** the user is confident to run the study on 2026-11-12.

### S8A — Gait screen
- **Do:** PAI, CoP, step count, label "estimate, not a diagnosis", animations. `GaitClassifier` interface with a rule-based implementation and a TFLite implementation in an isolate per DATA-CONTRACT §7: loads `assets/models/model_a.tflite` + `normalization.json` when present, input `[1,100,24]` (2 s window, 1 s stride, channel order §7.1, units as in S4C), outputs `gait_probs` [1,5] and `gait_embedding` [1,32]; falls back to the rules when the model is missing or confidence < 0.60. Prove the slot with a dummy model of the right shapes generated by a committed Python script (untrained weights): loads, channel order correct, inference ≤ 100 ms on the Note 10. Swapping in the real model after data collection (late Nov) must need only the two asset files. Model B stays out of scope (S7 rules give the status level).
- **Verify:** unit + golden tests · **You:** emulator + mock presets, screenshots via Dart MCP.
- **Done when:** values shown from mock data; classifier swappable without touching the screen.
- **Also (BACKLOG 42, user decision 2026-10-24; the step count depends on it):** raise the simulator's normal-walk motion so the walking-gate statistic (contract §8.3.2: mean |‖a‖ − 1 g| over `walkingWindowMs`) is on for most of each stride, aiming for a mean around 0.3 g (typical of a heel-mounted IMU). Test it with the contract's statistic (not the SD), and keep `t` / `p` / `n` working.
- **Result (report 034):** Gait tab per DESIGN-SPEC §8.3 / §8.5; `lib/gait/` with the Model A slot (`tflite_flutter` 0.12.1 in its own long-lived isolate; release slot empty, dummy only in debug/profile with `GAIT_MODEL=dummy`), rule-based fallback (provisional `gait.*` keys), gait-note source (model results only), steps in `daily_summary.steps`; simulator walk gate lowest 0.17 g / mean 0.34 g, one step per stance. Note 10 (run 2026-10-25): dummy inference median 3.1 ms / max 21 ms, real BLE 109.4 steps a minute, drop-in release proof passed; **accepted by the user 2026-10-25** (screenshots match FeetDGait, FeetDGaitToe and FeetDGaitIdle). Follow-up: the app's step detector splits a stance on a short dip, now S9's first item (BACKLOG 51).

### S8B — Connection + Settings
- **Do:** connect left/right separately, per-side status, battery, firmware, scanning/success animations · Settings: text size, sound, TARE (with confirmation; BACKLOG 21 guard), foot-check reminder time, app info · hide the debug screen.
- **Verify:** golden tests for every connection state (scanning, connected, wrong side, error) · **You:** emulator with mock connection states, screenshots via Dart MCP. (Connecting real devices unaided is checked at the S9 checkpoint.)
- **Done when:** every state renders per DESIGN-SPEC.

### S8C — Daily foot check
- **Requires:** S6A merged.
- **Do:** 4 screens per DESIGN-SPEC; Home card shown until today's check is done; camera with guide outline + self-timer; photos in the app's private folder; compare with yesterday; 3 questions; "not sure" = abnormal; abnormal result logged as an alert; in-app evening reminder; photos deletable.
- **Verify:** unit/widget/golden tests for answer logic and the Home card · **You:** emulator (its virtual camera) for the flow · **User checkpoint:** real photos on the Note 10; photos do not appear in the gallery.
- **Done when:** a full check takes about 1 minute and photos stay inside the app.

### S8D — 8 FSR + 8 NTC per foot (new, user decision 2026-10-29)
- **Requires:** S8C merged (PR #32, including the reminder fixes from its Note 10 run).
- **Why:** the real insole is final: 8 FSR + 8 NTC per foot, NTC i next to FSR i; the IRB confirmed no amendment is needed. The contract is ours to define (v1.6); the user sends it to the hardware team.
- **Contract (user decisions 2026-10-29):**
  1. Channel order, same on both feet: 0 hallux, 1 MTH1, 2 MTH2–3, 3 MTH5, 4 lateral midfoot, 5 heel centre, 6 medial arch (new), 7 lateral heel (new). Indices 0–5 keep their old meaning. Approximate positions in mm (x from the lateral edge toward medial, y from the back edge of the heel; right foot mirrored): 0 (70, 247), 1 (75, 197), 2 (48, 205), 3 (22, 197), 4 (18, 140), 5 (43, 38), 6 (59, 126), 7 (22, 82).
  2. Sensor stream: same format with N = 8 → 28-byte samples, 232-byte packets (fits MTU 247).
  3. Temperature v2, 32 bytes, every 30 s: `seq` u16, `t_ms` u32, `count` u8 (= 8), reserved u8, temp int16 × 8 (0.01 °C, −32768 = invalid), quality u8 × 8 (0 ok, 1 poor contact, 2 error). The old 12-byte packet is not kept (rejected with a named reason).
  4. DATA-CONTRACT v1.6. Model A input becomes 28 channels (8 FSR × 2 feet + 6 IMU × 2); temperature is still not a model input.
- **Split** (too big for one session; plan approved 2026-10-29):
  - **S8D-1 — data path** (30 Oct, `work/flutter-8-sensors`): contract v1.6 with a hardware appendix (Appendix C: exactly 8 calibration channels, what the app rejects, one generated hex example of each packet); `shared/sensor_layout.json`; parser and new test vectors; simulator 8 FSR + temperature v2 by default (`t` warms site 1, MTH1; `p` / `n` unchanged); DeviceManager ΔT per site for all 8 sites (rule 4); storage schema v2 (additive); AlertEngine: `TEMP_DELTA` over the 8 site pairs, one alert per warmer foot listing every qualifying site, peak / PTI / concentration / asymmetry over 8 zones (the 40 % share unchanged, flagged for SR); rule-based gait and CoP zone mapping; research capture schema 2, `load_capture.py` (old 6-FSR files still load), export; Model A slot `[1,100,28]` with a regenerated dummy and drop-in check; mechanical UI fallout (maps get 8 dots; the Temperature tab keeps its widgets on the two sites with the largest difference until S8D-2); Diagnostics shows N, temperature format and rejects. The web app stays frozen: the report says whether its fallback can still capture and what is lost.
  - **S8D-2 — UI** (31 Oct, `work/flutter-8-sensors-ui`, requires S8D-1 merged): the Temperature tab for 8 sites (layout A, user decision 2026-10-29: both feet with 8 site dots, the 3 sites with the largest difference, one chart line = the largest difference of the 8 sites, details table × 8), the alert-detail temperature map with every qualifying site, dot sizes at 8 zones, zone names in all copy (Appendix A), DESIGN-SPEC, FLUTTER-PLAN, `mobile/CLAUDE.md`, BACKLOG.
- **Zone names (user decision 2026-10-29, draft for the medical review):** 0 "นิ้วหัวแม่เท้า", 1 "โคนนิ้วหัวแม่เท้า", 2 "กลางหน้าเท้า", 3 "โคนนิ้วก้อย", 4 "ขอบเท้าด้านนอก", 5 "กลางส้นเท้า" (renamed), 6 "อุ้งเท้า", 7 "ส้นเท้าด้านนอก". The heel group for the gait rules and the heel-walking note is 5 + 7.
- **`TEMP_DELTA` (user decision 2026-10-29):** rule 6 stays per site (the same site above `deltaC` on 2 consecutive reading pairs). One alert per warmer foot names the site with the largest difference; its details list every qualifying site with its difference and time, `alerts.csv` has a `temp_sites` column, and a site that qualifies on that foot during the 30-minute suppression is added to the open alert's details.
- **Verify:** analyze/test, goldens, `node shared/test_vectors/generate.mjs --check`, `pio test -e native`, `load_capture.py --selftest` (schema 1 and 2), emulator + Dart MCP screenshots, `spec-reviewer`.
- **Note 10 checkpoint (end of S8D-1, user):** both simulator boards on 8 + 8: connect, Diagnostics shows N = 8 and temperature v2 with 0 rejects, a 5-minute stream with no gaps, a `TEMP_DELTA` alert from `t`, a short capture → export → load.
- **Done when:** both feet stream 8 + 8 on the phone with every rule and capture working, and S8D-2's screens show 8 sites per DESIGN-SPEC.

### S9 — Integration + APK
- **First, before anything else in S9: one step per stance (BACKLOG 51, user decision 2026-10-25, must be done before SR).**
  - **Problem:** the app's `StepDetector` (`mobile/lib/rules/step_detector.dart`) must not split one stance when the summed kPa dips briefly below `steps.contactKpa`.
  - **Fix:** add hysteresis, or merge stances separated by a short dip.
  - **Keys:** the fix uses new provisional keys in the `steps` block of `thresholds.json`.
    - Keep both copies byte-identical.
    - Add the keys to the DATA-CONTRACT §8 addendum, next to the step definition.
    - `version` stays 1.
  - **Tests replay the pre-fix simulator walk:** `synth.cpp` before `2e2a326`, which has midfoot channel `{0.40, 0.40, 860}` and a midfoot peak of about 18 kPa. Each walk is replayed at TARE offsets 12 and 19, the two boards' offsets. The tests expect:
    - one step per stance;
    - every stance between `minStanceMs` and `maxStanceMs`;
    - the two feet's mean-stance PAI below `gait.stanceAsymmetryPct` / 2, so the rules read that walk as normal, not antalgic.
  - **Must not change:**
    - the current simulator walk, the existing step-detector tests and the alert rules that use steps;
    - two real steps separated by a genuine swing must still count as two steps.
  - If merging delays a step's end, the delay is at most the merge window; state it in the contract addendum.
  - Do this before the 30-minute run, so the run uses the fixed detector.
- **Do:** integration checklist; 30 minutes with 2 boards on the phone (simulator boards; real boards are SR); battery and smoothness; reduce-motion; release APK. **User checkpoint** also covers: press sensors and watch the right dots change, warm one temperature sensor and watch ΔT, connect both insoles unaided.
- **DEVICE_LOST check (added in S6B):** with both boards streaming, power off one board for more than 5 minutes (`alerts.deviceLostAfterMin`). `DEVICE_LOST` is raised for that foot, appears on the Alerts list, and its card opens the right detail (`เรื่องอุปกรณ์`, "เชื่อมต่อได้ครั้งล่าสุด", "เชื่อมต่ออีกครั้ง" → Connection).
- **Auto-reconnect check (added after S6B, BACKLOG 45, before SR):** keep both serial loggers running. While both boards stream, reset one board (EN button) twice: once with the phone screen on, and once with the screen off and the app in the background. Each time, record the time from the reset to streaming again, from the board's log and Researcher › Diagnostics (its Reconnects card and event log, S8B). Expected: it reconnects well within `alerts.deviceLostAfterMin` and raises no DEVICE_LOST. If it does not reconnect, find why (BACKLOG 45) and fix it before SR.
- **My feet check (added in S6B part 2, user request 2026-10-25):** with both simulator boards streaming over real BLE, open My feet › "แรงกด" and › "อุณหภูมิ", then send `p` (pressure) and `t` (temperature) on the boards' serial consoles. Confirm that the banner, the detail figures (peak while walking, PTI, single point), the site cards and the chart behave as in the S6B part 2 mock run (report 033): Be careful with "ดูสิ่งที่ควรทำ" opening the newest alert, Rest only after 2 readings above the threshold, the chart's line and end dot. Then power off one board for a few minutes: the chart shows "ขาดข้อมูล / ตั้งแต่ HH:mm" with no line after it, the Temperature banner turns to "เทียบความอุ่นไม่ได้", and the line goes on (with a closed gap) once the board streams again.
- **Done when:** the APK works for 30 minutes with no serious issues.

### S10 — Wrap-up
- **Do:** fix leftover bugs; update `mobile/CLAUDE.md`, `docs/PROGRESS.md`, `docs/BACKLOG.md`; screenshots of every screen in `docs/screenshots/`.
- **Done when:** docs match the code.

---

## 4. If a session fails
- Do not start any session whose "Requires" depends on it.
- Open `S<ID>-fix` and do all 4 steps.
- If stuck for more than a day, the user brings it back to Claude chat to re-plan.

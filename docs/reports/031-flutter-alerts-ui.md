# 031 — S6B part 1: Alerts list and alert detail (style D)

Branch `work/flutter-alerts-ui` (from `main` at the PR #26 merge,
`33aa0d3`) · 2026-10-24 · Session S6B part 1 (`docs/SESSIONS.md` §3)
Spec: DESIGN-SPEC §3, §4, §5, §7, §12, §13, §14 and Appendix A; report 030
"Leftovers". Plan approved 2026-10-24, with the user's decisions on
threshold sources, the map snapshot, the debug seed, the SR clear step,
the release reinstall and the clear action's scope.

**Status: waiting for the user's acceptance of the Note 10 checkpoint.**
Everything automated passes. I ran the phone checks myself (section
"Note 10 checkpoint"); the screenshots are for the user to compare with
the boards.

## Summary

- **Alerts tab (§7.2):**
  - title, an unread line that is also a live region, day groups, cards, a 30-day footer, and the empty state;
  - TalkBack label per card;
  - entrance stagger on every tab selection;
  - a new alert's row opens at the top while the bell wiggles and the badge pops.
- **Alert detail (§7.3):** for TEMP_DELTA, PRESSURE_PEAK, PRESSURE_PTI,
  LOAD_CONCENTRATION and DEVICE_LOST. It has:
  - the status card;
  - "สิ่งที่ควรทำ" steps;
  - "ตำแหน่งที่พบ": temperature sites, or the pressure map stored with the alert;
  - "ทำไมแอปถึงเตือน", with the gait note when one applies;
  - the details expander, with dates in the Buddhist year and "ที่มาของเกณฑ์";
  - the disclaimer and the action button.
- **Read state (decision 7):** an alert is read when its detail opens.
  BATTERY_LOW is marked read when its card opens Connection, and a
  foot-check finding when its card opens Foot check › Something found.
  The badge, the chip and the unread line follow the stored rows live.
- **Navigation (§4):**
  - My feet sub-tab targets (`openMyFeet`): temperature for TEMP_DELTA, pressure for the pressure codes and for Home's "ดูเพิ่ม";
  - Connection for DEVICE_LOST;
  - `/foot-check-found` with the foot check's id.

  Targets built later open placeholders that already receive their target.
- **Shared widgets** (`lib/ui/widgets/`, for part 2 and S8):
  - new: `status_tag`, `new_chip`, `details_expander` (`DetailRow`), `numbered_steps`, `disclaimer_line`, `back_link`, `detail_status_card`, `temp_site_map`;
  - `FootMap` gains "not recorded" dots, the trigger ring and `pulse`;
  - the emphasised card is the existing `AppCard(emphasised:)`.
- **Small approved data and rule changes:**
  - **Threshold sources:** `thresholds.json` gets a `sources` block copied from contract §8.3, read through `Thresholds.sourceOf`. Version stays 1.
  - **Map snapshot:** the engine stores both feet's 2 s rolling-peak map with every pressure alert (`details.map`). There is no schema change.
- **Debug seed** (mock runs only, in-memory database): Settings → "Seed
  sample alerts (debug)" writes one alert of each listed kind with the
  boards' values.
- **Researcher clear action:** Research capture → *4 · App database
  (test data)* → *Clear app database (test data)*.
  - It deletes untagged alerts, temperature readings, daily summaries, foot checks and foot photos.
  - It never deletes capture-tagged alerts, session folders or the export folder.
  - It asks twice before it runs.
- **Independent review** (your request): a separate agent compared §4,
  §5, §7, §12 and §13 with the diff. It found no high- or medium-severity
  mismatches and 4 low ones. Two are fixed; the other two are a BACKLOG
  item and a spec note (table below).

## What changed

| Area | Files |
|---|---|
| Screens | `lib/ui/screens/alerts_screen.dart` (rewritten), `alert_detail_screen.dart`, `alerts/alert_view.dart` (pure view model), `foot_check_found_screen.dart` (placeholder), `my_feet_screen.dart` (shows the target) |
| Widgets | `lib/ui/widgets/`: 8 new files, as listed above; `foot_map.dart`, `buttons.dart` (`trailingIcon`), `motion_widgets.dart` (each item keyed by its child's key) |
| Shell and routes | `app_shell.dart` (`MyFeetTab`, `myFeetTabProvider`, `openMyFeet`, `unreadAlertsKnownProvider`), `bottom_bar.dart` (no wiggle for the first stored count at start-up), `routes.dart`, `app.dart`, `home_screen.dart` ("ดูเพิ่ม" → pressure) |
| Theme and motion | `clock.dart` (Buddhist-year date, relative day, weekday + day + month), `typography.dart`, `dimens.dart`, `colors.dart` (`FootDotColors.notRecorded`, trigger ring, `TempSiteColors`), `motion.dart` (`newRowSlide`) |
| Storage | `storage_providers.dart` (`visibleAlertsProvider`, `alertByIdProvider`, `clearTestDataProvider`), `test_data.dart` (`clearTestData`), `sample_alerts.dart` (debug seed) |
| Rules and config | `alert_engine.dart` (`details.map`), `alert_code.dart` (`maxLevel`, `pressureCodes`), `gait_note.dart` (`gaitClassTh`), `config/thresholds.dart` (`sources`), `device/rolling_peaks.dart` (`mapPeaksOf`, shared with Home), `ble/ble_protocol.dart` (`TempLayout.notifyPeriod`) |
| Shared | `shared/thresholds.json` and its asset copy: `sources` |
| Capture | `capture_home_screen.dart` (section 4, the clear action); `tools/capture/load_capture.py` (selftest case for nested `details`) |
| Docs | `BACKLOG.md` 43 and 44, `SESSIONS.md` (SR clear step, S9 DEVICE_LOST step), `STUDY-CAPTURE.md` (clearing test data), DESIGN-SPEC §7.1–§7.3, §14, Appendix A, `lib/rules/README.md`, `shared/README.md`, `mobile/CLAUDE.md` |

## Decisions and how they were applied

- **Copy:**
  - All health copy comes from `alertCopyFor`, which is DRAFT until the medical expert reviews it.
  - A finding's title and advice come from §7.1.
  - Detail-row labels follow the §7.3 boards.
  - The PTI and LOAD_CONCENTRATION rows are new S6B drafts, now in §7.3 and Appendix A:
    - PTI: "{v} kPa·s เฉลี่ยต่อก้าว ที่{zone}{side}", "เกณฑ์ {t} kPa·s เฉลี่ยต่อก้าว ขณะเดิน", "จำนวนก้าวที่ใช้ {n} ก้าว ใน {m} นาทีล่าสุด";
    - CONC: "{v}% ของแรงกดทั้งฝ่าเท้า ที่…", "เกณฑ์ {t}% ติดกัน {n} ก้าว", "{n} ก้าวติดกัน".
- **No thresholds hardcoded:**
  - row thresholds are the value stored with the alert; otherwise they come from `thresholds.json`;
  - the measurement period "วัดทุก 30 วินาที" is the wire constant `TempLayout.notifyPeriod`;
  - the footer is `retentionPeriod.inDays`.
- **Threshold source:** the screen shows `sources` exactly as stored, and
  hides the row for "—" (DEVICE_LOST, BATTERY_LOW), as on the board.
  - **Not verified:** "Waaijman et al. (2014)" does not confirm 80 kPa·s for PTI. This is BACKLOG 43, to settle before the medical expert review (2026-11-05). The screen does not mention it.
- **Map snapshot and its fallback:**
  - Pressure alerts raised from now on store both feet's levels and kPa, so the map shows what Home showed at that moment.
  - A foot that was not usable then is stored as `null` and drawn in the No-data style, because it really had no data.
  - **Fallback** for rows stored before S6B (none exist on the study phone; a golden covers it): only the ringed zone is filled.
    - PEAK fills it at its kPa level.
    - PTI and CONC fill nothing, because their values are not kPa.
    - Every other zone is a plain `inkMuted` outline circle with no fill and no dashes, never the No-data style.
  - The engine test checks that the stored map equals `mapPeaksOf` + `pressureLevel` on the same batches at raise time. All 65 rules tests from S7 still pass, plus 3 new ones.
- **Rule 5:** DEVICE_LOST and BATTERY_LOW tags use the No-data palette, never green.
- **Rule 16:** under reduce motion the stagger, new row, wiggle, pop and chevron are all instant (a widget test checks for no running animation).
- **Badge at start-up:** the bell and badge animate only when both the old
  and the new count are known. An app that opens with stored alerts shows
  the badge without a wiggle (tested).
- **Live region:** the unread line's `Semantics(liveRegion)` node stays in
  the tree, empty at 0, so TalkBack also announces the change from 0 to 1.
  On screen it is hidden at 0, as §14 proposed.
- **Older days:** the detail's time for days before yesterday is "{weekday
  d MMM} HH:mm". The spec only gave today and yesterday; the format is now
  in §7.3.

## Independent review (spec vs implementation)

A separate agent that did not write the code compared DESIGN-SPEC §4, §5,
§7, §12 and §13 with the S6B-1 diff (`main...c769d56`). Its findings:

| # | Area | Spec says | Implementation did | Severity | Outcome |
|---|---|---|---|---|---|
| 1 | Icon stroke | §5: back link `chevron-left` and status-tag icon "stroke 2.25" | `flutter_lucide` font glyphs, whose stroke is fixed at 2 (every screen since S5) | low | **Not changed here.** BACKLOG 44 (S10): accept 2 in §5, or switch every icon to the Lucide SVGs at 2.25. Changing only these screens would make the app inconsistent |
| 2 | TalkBack (list card) | §7.2: the card shows a source line and "ควรทำ: …"; §13 does not fix the label | The label had only tag, time, title and read state, so the advice was not read out | low (ambiguous) | **Fixed** (`2914823`). The label now adds the source line and "ควรทำ: {advice}" (rule 13). New widget test; §7.2 documents the label. The role stays button, like every other card in the app |
| 3 | Detail time | §7.3: "วันนี้ {HH:mm}" or "เมื่อวาน {HH:mm}" only | "{weekday d MMM} HH:mm" for older days | low (ambiguous) | **Spec updated** (§7.3); the code was right |
| 4 | Board copy vs Appendix A | §7.1 and §7.3 board text (CONC standing advice, PEAK "หลายก้าวติดกัน") | `alertCopyFor` follows Appendix A (S7) | low (ambiguous; the code was right) | **Spec note added** (§7.1): Appendix A wins where the two differ |

The reviewer also listed what it checked and found matching. That covers:
- list tokens and states;
- every tag, palette and icon;
- the empty state;
- the level-2 exclusion from the list and badge;
- every navigation target and read-state path;
- the detail's order, sizes and colours;
- both maps and their labels;
- the gait note, the expander and the disclaimer;
- motion, reduce motion and 200 % text.

## Verify

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `dart format lib test test_driver` | 0 changed |
| `flutter test` | **548 passed** (was 493 on `main`; +55) |
| Goldens | 15 new at 100 % and 200 %: the list (read and unread over 3 days), empty, details for TEMP_DELTA, PEAK (numbers open, gait note), PTI, CONC and DEVICE_LOST, plus the no-snapshot fallback at 100 %. Changed on purpose: `alerts.png`, `my_feet.png` (placeholder now names its target) and `settings_mock.png` (seed button). I reviewed each one |
| `pio test -e native` (simulator, reads `thresholds.json`) | 40/40 passed |
| `load_capture.py --selftest` | PASS, including the new nested-`details` case |
| Emulator dry run (MOCK=watch) | The engine raised a live PEAK; list, badge and detail with the stored map (`031-flutter-alerts-ui/emulator/`) |

New tests:
- `test/alerts/alerts_screen_test.dart` (21):
  - grouping and footer; empty;
  - the unread line and its live region; card labels;
  - read state for detail, BATTERY_LOW and finding;
  - the 4 My feet targets, DEVICE_LOST → Connection, and Home "ดูเพิ่ม";
  - bell wiggle and row opening; no wiggle at start-up; reduce motion;
  - expander semantics; map labels; gait note.
- `alert_view_test.dart` (13): rows per code, maps and fallback, looks, targets, dates across midnight.
- `test/storage/test_data_test.dart` (2).
- `test/capture/clear_test_data_test.dart` (2): two confirmations, the session count line, and that tagged alerts and session folders survive.
- 3 engine tests, the `sources` test and the date helpers.

## Note 10 checkpoint (run 2026-10-24, 20:37–21:01)

Setup:
- Both boards stayed on the S7 firmware; nothing was flashed.
- Loggers ran on port 6 (left, needed one reopen: it read nothing at first, as in the serial-port note) and port 7 (right), started before any phone connection.
- Debug builds went in with `adb install -r` over the S7 release build, which keeps the data.
- **The phone's font scale was 1.3.** I set it to 1.0 for the 100 % screenshots and back to 1.3 at the end.

Screenshots (phone, 720 px wide): `031-flutter-alerts-ui/phone/`.
Compare with the boards:

| Board | Screenshots | Source |
|---|---|---|
| AlertsDEmpty | `01-alerts-empty` | MOCK=safe, fresh start |
| AlertsD | `02-alerts-watch`, `05-alerts-mixed-read`, `08-alerts-seeded-a/b/c` (3 days, read and unread) | live engine (watch, rest) + seed |
| AlertDetailDPressure | `03-detail-peak-a/b/c` (numbers open), `10-detail-peak-gait-note-a/b/c` (toe-walking note, "รูปแบบการเดิน" row) | live PEAK 240 kPa; seeded PEAK 236 kPa |
| (PTI, new draft) | `04-detail-pti-a/b/c` | live PTI 81 kPa·s, 74 steps in 60 min |
| AlertDetailD | `06-detail-temp-delta-a/b/c` | live TEMP_DELTA forefoot 2.6 °C, 2 readings |
| (CONC, new draft) | `09-detail-load-concentration-a/b/c` | seeded, right heel 46 % |
| AlertDetailDDevice | `11-detail-device-lost-a/b/c` | seeded: yesterday 16:20, 43 %, 6 min |
| Navigation | `12-device-lost-action-connection`, `13-finding-opens-found-placeholder` ("foot check 1") | seed |

Live check, as planned. The real-Bluetooth debug build used the phone's own database:

| # | Step | Result |
|---|---|---|
| 1 | Open the app on the phone's database | **One untagged alert was already stored** (`14-…`, `15-…`): "alerts 1 · capture-tagged 0 · latest DEVICE_LOST 10/24 19:10:56", left foot. The left temperature rows stop at 19:05:36, so the left board went quiet at the end of S7 and DEVICE_LOST fired 5 min later, most likely after the "alerts 0" card you read. It was not capture-tagged, so it was not your stop case. The clear removed it |
| 2 | Connect both from BLE debug | Left and right both STREAMING, MTU 247, 8 per packet, START at 20:52:07 / 20:52:21; Home Safe, both 98 % |
| 3 | Alerts tab open, screen recording on, `t` to the right board | `t` sent at 20:52:51.454; the board confirmed at 20:52:51.478. TEMP_DELTA (right forefoot) appeared on the list about 60 s after `t` (the recording started about 2 s before `t`, and the list changed at 61.8 s into it), which fits 2 readings at 30 s. A UI poll confirmed the row at 20:53:55 |
| 4 | Bell wiggle, badge pop, new row | **Pass**, from the recording (`16-live-t-frames-*.png`): the new row opens at the top with height and fade, pushing the DEVICE_LOST card down (+0 to +167 ms); the bell tilts left, then right (+50 to +267 ms); the badge "2" pops and settles. The video itself (3.3 MB) is not committed |
| 5 | `n` to the right board, then *Clear app database (test data)* | The first confirmation has no session line (no sessions on the phone, as you said: "No sessions yet"). The result: "Removed 2 alerts, 169 temperature readings, 1 daily summaries, 0 foot checks and 0 photo files" (`18`–`20`) |
| 6 | Restart; BLE debug card | **"alerts 0 · capture-tagged 0"** (`21-…`), as you expected. One left temperature row (20:58:08) was written by the old process between the clear and the restart, because the insoles were still connected. `STUDY-CAPTURE.md` now says to disconnect both insoles before clearing, and to check that both temperature-row counts read 0 |
| 7 | Release build back | `flutter build apk --release` from `2914823` (64,199,211 bytes), `adb install -r`. Package flags `[ HAS_CODE ALLOW_CLEAR_USER_DATA ]` (no DEBUGGABLE); the app starts. **The Note 10 is left on the release build**, font scale 1.3 |

**How this session's TEMP_DELTA was cleared:** it was raised outside a
capture session, so it was untagged. The new action removed it, together
with the S7 DEVICE_LOST, in the debug build at 20:57 (step 5).

Serial lines (boot, connections, `t` / `n`): `031-flutter-alerts-ui/note10-serial-log.txt`.

## Leftovers and notes for the next sessions

- **BACKLOG 43 (deadline 2026-11-05):** find a verified source for PTI 80 kPa·s, or change the value.
- **BACKLOG 44 (S10):** icon stroke 2 vs 2.25.
- **S6B part 2:** My feet already receives its target sub-tab (`myFeetTabProvider`), and the shared widgets are ready.
- **S8C** replaces the Found placeholder; the route already passes the foot check's id.
- **S9:** check DEVICE_LOST on the real path. This session saw one by accident (step 1), but listing it and opening its detail were not checked with a real board. That step is in `SESSIONS.md`.
- **SR:** the clear step and its check are in `SESSIONS.md` and `STUDY-CAPTURE.md`.
- **Wording:** the clear result says "1 daily summaries"; the English is researcher-only and was left as is.

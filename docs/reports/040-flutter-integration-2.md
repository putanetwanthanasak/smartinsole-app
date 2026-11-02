# 040 — S9-2: one baseline function, release APK, Note 10 checkpoint

Branch `work/flutter-integration-2` · 2026-11-02 · from main b2f8eb5 (PR
#35, S9-1). Plan approved 2026-11-02 with user decisions 1a, 2a, 3a, 4b,
5b, 6a (below). Part A is code (BACKLOG 74). Part B is the release APK.
Part C is the Note 10 checkpoint, report 039's checklist plus the S9-2
additions. **The checkpoint is waiting on user:** the results below are
what was observed in this session. Nothing is marked passed until the
user confirms it.

## Summary

- **BACKLOG 74 resolved: one baseline function.**
  - `FootBaselineWindow` (Dart) and `foot_baseline_window` (Python) take
    the first `baselineSeconds` × 50 Hz rows per foot that pass the rules
    (decision 1a). The rules are applied in one order, and each failure
    has a name.
  - A row marked invalid fails the baseline (2a).
  - Training takes the newest valid trial-00 attempt that passes (3a).
  - A shared trial-00 fixture gives the same failure, row count and
    float64 medians in Python, in the app's trial path and in the live
    recorder.
- **Decision 4b:** the capture Saved screen shows trial 00's baseline
  result, and `load_capture.py check` reports it (FAIL for a study session,
  INFO for a rehearsal). Display only; capture recording and timing are
  unchanged.
- **Final APK for SR: 1.0.0+5** (decision 6a; +2, +3, +4 went on the
  Note 10 before it). Every build was installed with `adb install -r` and
  passed the resource check. The model slot is empty.
- **Checkpoint fixes:**
  - Item 8: opening an alert inside the app now removes its notification
    from the tray (+3).
  - Item 9: the capture Ready and Saved screens show "Alerts this
    session" (+4, user's "small fix now").
  - Spec review finding 1: a trial 00 up to 5 samples short still gives a
    baseline (+5, user decision 2026-11-02).
- **Checkpoint:** items 2, 3, 4, 6, 7, 8, 9, 10, 11 and 12 were run on the
  Note 10. Items 1 and 5 were moved to SR by the user (battery 15 %).
  **Waiting on user.**

## What changed

| Commit | Content |
|---|---|
| 37af0b4 | `lib/gait/baseline_window.dart`: `FootBaselineWindow`, `BaselineRow`, `BaselineFailure` (+ `markedInvalid`, `tooShort`); `BaselineRecorder` is an adapter over it (exactly 1500 samples per foot; the old time rule kept 1501 on the emulator); `test/gait/baseline_window_test.dart` |
| e6f7009 | `tools/model/preprocess.py`: `WalkingGate` (Dart rounding), `foot_baseline_window`, `trial_baseline`, `session_baseline` per 3a, `baseline` command; `shared/test_vectors/baseline/` (ok + 7 failure cases, `expected.json`); selftest |
| 7e04a65 | `lib/capture/trial_baseline.dart` (`checkTrialBaseline`); `test/capture/trial_baseline_test.dart` (every fixture case, bit-identical; the ok trial through the live recorder) |
| 34fabcb | `TrialBaselineLine` on the capture Saved screen (4b); widget tests; goldens `capture_baseline_ok`, `capture_baseline_failed`, `capture_saved`, `baseline_recording_100` |
| a3b7c80 | `tools/capture/load_capture.py check`: trial 00's baseline (OK / FAIL study / INFO rehearsal) |
| d9c9980 | Version 1.0.0+2; `mobile/CLAUDE.md` build-number rule; DATA-CONTRACT §7.1 + history row; STUDY-CAPTURE; gait and capture READMEs; SESSIONS §S9 item 9; BACKLOG 74 resolved |
| 8520e84 | Emulator screenshots |
| 0f083eb | Item 8: `AlertNotificationService.markRead` marks the alert read and cancels its notification (`AlertNotifier.cancel`); the detail screen and the Alerts list go through it; 2 tests |
| d633edd | Version 1.0.0+3 |
| 6e3dd77 | Item 9: `AlertRepository.watchForCapture`, `captureAlertsProvider`; `SessionAlertsLine` on the capture Ready and Saved screens ("Alerts this session: N (no notification) · latest CODE side HH:mm", grey, only when there are any); widget rig gets an in-memory database; 1 test; STUDY-CAPTURE session step 5; version 1.0.0+4 |
| d894d81 | Spec review finding 1: `baselineToleranceSamples` (5) in `model_preprocess.json`; `FootBaselineWindow.end()` and `foot_baseline_window` accept a trial 00 that ends at most that many samples short with every rule passed; fixture case `slow_clock` (20.05 ms step, 1497 / 1496 rows); tests for the boundary; DATA-CONTRACT §7.1; version 1.0.0+5 |
| a73ed54 | Report 040 and screenshots; BACKLOG 45, 52, 72 results and new items 75–77; FLUTTER-PLAN §1, DESIGN-SPEC §11.9 (screen-off result, session screen named); STUDY-CAPTURE (redo wording, tolerance) |

Checks on the final state: `flutter analyze` no issues; `flutter test`
**1066 passed** (goldens unchanged since 34fabcb); `preprocess.py
--selftest` PASS and `--make-vectors` reproduces `shared/test_vectors/`;
`load_capture.py --selftest` PASS; `generate.mjs --check` up to date.

## Release APK

| Build | Version | SHA-256 | Size | Installed |
|---|---|---|---|---|
| +2 | 1.0.0+2 (versionCode 2) | `681f93def3659717302011e2e2d45bc4dde09af354d4a2090cac09f25d28571f` | 93,786,761 B | 2026-11-02 14:16:18, `adb install -r` over 1.0.0+1 |
| +3 | 1.0.0+3 | `5b8ef9278098942495453fe53096722ce67e6336371d483948c05ac5b213d957` | 93,803,149 B | 15:39:58 (item 8 fix) |
| +4 | 1.0.0+4 | `0f257b7094be806108c9e6c25691219acf920cfe5b545aafe9d3ec1dd2b3a1c7` | 93,803,149 B | 16:30:09 (session alerts line) |
| **+5 (for SR)** | 1.0.0+5 | `28217ee8a6bfd117ae26fe6ac87e419237a9dd16da685a56f937a1d7e902ec92` | 93,803,325 B | 16:56:37 (baseline tolerance) |

- Built with `flutter build apk --release` from the commit in the row
  (+5 from d894d81).
- After each install the app came back without help: auto-reconnect R
  2.8 / 2.4 / 2.1 s and L 4.5 s each time (+3 had 1 failed try, GATT 133).
- Installing an update removed the app's notifications from the tray.

- `tool/check_release_resources.sh` passed on it (`ic_stat_foot_check`,
  `ic_stat_foot_alert`).
- The release model slot `assets/models/` holds only its README. The dummy
  model is bundled for debug only, and release ignores it.

## Note 10 checkpoint (waiting on user)

Phone: Note 10, RF8M83P4STZ, Android 12 (sdk 31), font scale 1.3.

Boards:

- Left: `88:57:21:B7:74:9E`, on the laptop. Serial log on the by-path
  CP2102 port, started before the phone connected.
- Right: `38:18:2B:8A:26:D6`, calibration SIM-R-001, on a USB charger.

Order run: 11 → 2 + 3 → 7 + 8 → 4 → 6 → 10 → 9 + 12, then the item 9
fix on TEST-013.

Screenshots are in `docs/reports/040-flutter-integration-2/`.

### 11. Connect both insoles unaided (forget both first)

- Both feet were forgotten on Connection with the user's approval
  (14:19:08 L, 14:19:18 R).
- **Left:** "เชื่อมต่อเท้าซ้าย" was tapped at 14:19:29.7, and the left
  board was streaming at 14:19:36.5 (6.8 s).
  - The scan first reached the right board and refused it by its side
    byte (rule 8), then connected the left.
  - The log calls that refusal "disconnected by user". The label is
    misleading (leftover).
- **Right:** tapped at 14:20:09, streaming at 14:20:14.2 (5.2 s).
- **BACKLOG 73:** the permission ask ran when both feet were first
  streaming. Android 12 shows no dialog; notifications are allowed.
- **Diagnostics, right:** `N 8 · temperature v2, 8 sites · rejects 0`,
  link losses 0.
- **Before the forget,** auto-reconnect after the install took R 2.8 s
  and L 4.8 s (1 failed try, GATT 133).

### 2. My feet on the S8D-2 UI with `p` and `t` (left board)

**Pressure** (`p` at 14:22:34):

- **Notifications:**
  - PRESSURE_PEAK notified at 14:22:37.9: "ปลายเท้าซ้ายรับน้ำหนักมากตอนเดิน",
    "ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่".
  - LOAD_CONCENTRATION followed at 14:22:59.2.
  - Two sound notifications came 21 s apart from one event (see
    leftovers).
- 8 zones per foot. The left MTH1 dot is red with a pulse ring, and the
  top-3 list is shown.
- **Details:** left MTH1 247 kPa; peak while walking L 247 / R 58 kPa; PTI
  L 26 / R 5 kPa·s; single point L 49 % / R 19 %.

**Temperature** (`t` at 14:23:44):

- **First reading:** the map marks the left MTH1 as warmer, and the banner
  stays green ("สองข้างอุ่นใกล้เคียงกัน"). That is correct: Rest needs 2
  readings.
- **14:24:44:** TEMP_DELTA was notified. The banner turned to Rest:
  "โคนนิ้วหัวแม่เท้าซ้ายอุ่นกว่าขวา 2.9 องศา ติดต่อกันมาสักพัก".
- **Top-3 rows:** MTH1 2.9° (warmer, alert icon), then two "ใกล้เคียงกัน"
  rows.
- **One-line chart:** the line enters "ระดับที่ควรระวัง" with the site
  label "โคนนิ้วหัวแม่เท้า". The install gap was labelled
  "ขาดข้อมูล 14:16–14:18".

**Right board off** (the user unplugged it at 14:38):

- The banner turned grey: "เทียบความอุ่นไม่ได้ · เท้าขวาหลุดการเชื่อมต่อตั้งแต่
  14:38", with "เชื่อมต่อแผ่นรองเท้า".
- The map shows the right foot dashed, and "ต้องเชื่อมต่อทั้งสองข้าง".
- The chart reads "ขาดข้อมูล ตั้งแต่ 14:38".
- **Back on:** the line resumed at 15:02, and the gap reads "ขาดข้อมูล
  14:38–15:02".
- **How it reconnected:**
  - At 15:02:39 the log shows a manual Disconnect → find on the right foot
    (connected in 2.0 s). That cancelled the auto-reconnect that had been
    searching since 14:38.
  - At 15:03:19 the right link dropped again, and auto-reconnect recovered
    it in 16.8 s with 0 failed tries.
  - Whether the user tapped is to be confirmed by the user. Item 4 measures
    auto-reconnect on its own.

### 3. DEVICE_LOST

- **Raised** for the right foot at 14:43, 5 min after its last packet
  (14:38:17).
- **In the app only, with no system notification.** That is by design:
  user decision 4 of 2026-11-01 notifies only the four foot codes.
- **Alerts card:** "อุปกรณ์ 14:43 แผ่นรองเท้าขวาหลุดการเชื่อมต่อ".
- **Detail:**
  - "เรื่องอุปกรณ์ · วันนี้ 14:43", "ขาดการเชื่อมต่อนานกว่า 5 นาที";
  - steps: switch on, phone nearby;
  - figures: "เชื่อมต่อได้ครั้งล่าสุด 2 พ.ย. 2569 14:38:17", "หลุดการเชื่อมต่อนาน
    6 นาที (เกณฑ์ 5 นาที)" (whole minutes rounded up, by design), last
    battery 96 %, level 1 of 5.
- **"เชื่อมต่ออีกครั้ง"** opens Connection with the right foot
  "กำลังค้นหา…".

### 7. Alert notifications

**Screen on, app on screen:**

- TEMP_DELTA (14:24:44) gave one notification: "เท้าซ้ายอุ่นกว่าเท้าขวา",
  "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม".
- It was posted on channel `foot_alert` (importance 4, private on the lock
  screen, sound = the phone's default notification sound).
- Android logged `notification_alert … ,1,1,0` (buzz and beep) for each
  foot alert. The user did not hear the 14:22–14:24 sounds. The user did
  hear the 15:04:36 TEMP_DELTA (#27), raised again after the 30-minute
  repeat window.
- **Tap:** opens the alert detail ("ควรพักเท้า · วันนี้ 14:24", the warmer
  site, 3 steps). The notification leaves the tray (auto-cancel).
- **Back:** goes to Alerts with the alert marked read.

**App in the background, screen on:**

- `p` was sent 1 min after Home (15:07:37). PRESSURE_PEAK #29 was notified
  at 15:07:41.5 and LOAD_CONCENTRATION #31 at 15:08:03.0, both with sound.
- Samsung's MARs/Freecess logged no freeze.

**Screen off, app in the background** (BACKLOG 72):

- The first try was spoiled: a tap woke the screen (Samsung "tap to
  show"). The screen was then off 15:14:43–15:19:54 (woken by touches at
  15:19:54 and 15:20:16) and again from 15:31:06 (10-min timeout).
- `t` at 15:34:12 → TEMP_DELTA #32 posted at 15:35:06 with sound
  (`notification_alert …,1,1,0`). At that point the screen had been off
  4 min, and the app in the background for 28.5 min.
- Freecess froze `com.shopee.th` at 15:15:44 but never the app. BLE kept
  streaming the whole time.
- Android grouped the app's notifications (`ranker_group`).
- The separate 1- and 5-minute points had no fresh alert code (30-minute
  repeat window). For them only "not frozen, still streaming" was checked.
- **To confirm by the user:** whether the 15:35 sound was heard, and
  whether the phone was touched at about 15:20.
- The limitation stands (no foreground service). It is recorded in
  BACKLOG 72, FLUTTER-PLAN §1 and DESIGN-SPEC §11.9. A longer screen-off
  run is for SR.

### 8. Badge

- **Launcher badge** after the foot alerts: "smartinsole, 2 การแจ้งเตือน",
  counting the notifications in the tray.
- **Opening LOAD_CONCENTRATION #24 from the Alerts list** (not from the
  tray) marked it read in the app, but its notification stayed in the tray
  and the badge stayed at 2. **That was a defect.**
- **Fixed in 0f083eb:** marking an alert read cancels its notification.
- **On build +3:** `p` at 15:43:36 → PEAK #34 and LOAD #36. Opening #36
  from the Alerts list removed it from the tray, and the badge went
  2 → 1.
- **Leftover (BACKLOG 75):** the bell counts every unread alert (16 here),
  and the badge counts only the tray.

### 4. Auto-reconnect after a reset (BACKLOG 45)

Android notices a dead link about 8.3–8.7 s after the board loses power.
Auto-reconnect then takes 1.9–3.2 s, with 0 failed tries every time. No
DEVICE_LOST.

| Case | Link lost | Streaming again | Auto-reconnect |
|---|---|---|---|
| Screen on: the user replugged left USB (15:47:08) | 15:47:16.35 | 15:47:18.5 | 2.2 s (10.4 s from power off) |
| Screen on, app on screen: EN | 15:52:14.7 | 15:52:16.9 | 2.2 s |
| Screen off, background: 3 USB drops (flaky cable) | 15:53:42.7 / 15:54:01.7 / 15:54:10.2 | +3.2 / +2.0 / +2.3 s | 0 failed tries |
| Screen off, background: EN (about 15:54:13) | 15:54:21.6 | 15:54:23.6 | 2.0 s |
| Screen off: logger reopen resets the board (boot 15:57:27.2) | — | 15:57:37.0 | 1.9 s (9.8 s from boot) |

The first reset was a USB replug, not EN; the EN press time is not in a
serial log. The S7 failure (no reconnect for 5 min) did not happen again.

### 6. Reduce motion

- With the user's approval, the user turned on "Remove animations"
  themselves. All three animation scales read 0.0, and the Pressure
  danger ring was static over 6 frames (`note10-i6-on-1.png`).
- After the user turned it off: the scales read 1, and the ring pulses
  again (the frames differ).

### 9. Alerts during a research capture

- **Session TEST-012_20261102-161054 on +3:**
  - Trial 00's Saved line: "Baseline not checked: it needs 30 s of
    standing; this rehearsal calibration is 10 s" (500 / 500 samples).
  - All 6 trials completed: 1500 samples per foot (trial 05 L 1501), no
    gaps.
- **Alerts stored, no notification:**
  - `t` at 16:11:26 → TEMP_DELTA at 16:12:20, tagged with the capture.
  - `p` during trial 02 → PRESSURE_WATCH, PRESSURE_PEAK (16:16:08),
    ASYMMETRY_PEAK (16:16:18) and LOAD_CONCENTRATION (16:16:29).
  - No `notification_alert` was logged after 16:00.
- **A tray tap** on #34 during recording logged "alerts: tap on #34
  ignored during a capture", and the trial completed.
- **The session screen showed no alerts on +3, a gap against DESIGN-SPEC
  §11.9.** Fixed in 6e3dd77 (+4). Checked on the phone with TEST-013:
  - Ready (trial 00): "Alerts this session: 3 (no notification) · latest
    ASYMMETRY_PEAK L 16:46" (`note10-i9b-ready-line.png`);
  - after trial 00: Saved, "Alerts this session: 4 (no notification) ·
    latest LOAD_CONCENTRATION L 16:47" (`note10-i9b-saved-line.png`);
  - the line is not shown while recording;
  - no notification was posted. TEST-013 was then left with only trial
    00 recorded; it stays on the phone.

### 10. Researcher baseline on the real phone

- With both boards walking, "บันทึกค่ายืนนิ่ง 30 วินาที" was refused within
  3 s: "ไม่ได้ลงน้ำหนักบนแผ่นรองเท้า (เท้าซ้าย) · The foot was not loaded …
  ไม่ได้บันทึก ให้บันทึกใหม่". Nothing was saved (`note10-i10-refused.png`).
- **Not reachable with walking simulators** (decision 5b, no simulator
  change): accepted while standing still, refused as "moved", refused on
  a disconnect. These go to SR on real boards.
- Gait reads "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม": no model in
  release, the correct reason (`note10-i10-gait-reason.png`).

### 12. Export and check

- TEST-012 export: "Staged 14 files (5 alerts)".
- `export_capture.py --dest ~/smartinsole-data --serial RF8M83P4STZ
  --session TEST-012_20261102-161054`: every SHA-256 OK, PASS.
- `load_capture.py check` PASS, with INFO for the trial-00 baseline
  (rehearsal: L notLoaded, R moved; the simulators walk) and
  `alerts.csv` OK with 5 alerts.
- The staged copy is kept on the phone (TEST-003 and TEST-004 are still
  staged there too).

### 1 and 5. 30-minute run, scanning cost

Not run. Both need the Note 10 unplugged at ≥ 60 % battery over adb Wi-Fi.
It was at 15 % on laptop USB, and the user moved them to SR
(2026-11-02). BACKLOG 52 has the one data point there is.

## Spec review

`spec-reviewer` on `git diff main...HEAD` at 6e3dd77, against
DATA-CONTRACT §7.1 and §8.3.2, DESIGN-SPEC §10.2 and §11.9, FLUTTER-PLAN
§6, STUDY-CAPTURE, BACKLOG 74, SESSIONS §S9 item 9 and mobile/CLAUDE.md.
Copied as returned (paths shortened), with a resolution column.

| # | Severity | File:line | Spec | Mismatch | Resolution |
|---|---|---|---|---|---|
| 1 | major | `mobile/lib/gait/baseline_window.dart:155` (with `capture_session.dart:463-464`, `device_clock.dart:33-34`) | DATA-CONTRACT §7.1: "a capture trial window `[start, start + 30 s)` holds exactly 1500 samples per foot when nothing is lost" | The trial window is 30 000 ms of phone time; `DeviceClock` allows 20 ± 0.25 ms between samples, so a board clock slow against the phone (or a rising latency estimate) can put 1499 samples in a clean trial 00 → `tooShort`, "Baseline failed (… shorter than 30 s)", FAIL in `check`, no baseline. The fixture only covers the > 1500 case (19.95 ms step). | **Fixed in d894d81** (user decision 2026-11-02, "small tolerance"): `baselineToleranceSamples` 5; fixture `slow_clock`; §7.1 reworded ("about 1500 … 1499–1501"). On the Note 10, 12 foot-trials of 30 s held 1500 or 1501. |

| Spec gap (returned) | Resolution |
|---|---|
| §7.1 does not say what a loss-free trial 00 slightly under `baselineSeconds` × 50 means | Now stated in §7.1 (finding 1). |
| STUDY-CAPTURE bolds "Redo this trial now, while the volunteer is here"; the screen says "Redo trial 00 now, while the volunteer is here" | STUDY-CAPTURE now quotes the screen text. |
| DESIGN-SPEC §11.9 "shown on the session screen" does not name which screens; Practice and the end-of-session summary show no alerts line | §11.9 now names the Ready and Saved screens. An alert during the last gait shows on that trial's Saved screen and in `alerts.csv`; the summary is left as is (decision for S10 if wanted). |
| DESIGN-SPEC §10.2 lacks the two new `baseline_screen.dart` strings (marked invalid, too short), which the live recorder cannot produce | Left: unreachable on the Researcher screen; the strings exist so the switch is exhaustive. |
| §7.1 says the vectors are matched "through … its live recorder", but only `ok` goes through the live recorder | Left: the failure cases are covered row by row through the same `FootBaselineWindow`; the live test proves the adapter feeds it the same rows. |
| Python reports `wrongInsole` on any missing or empty model cell; Dart only when not 8 FSR, and throws on an empty accel/gyro cell | Left: the app never writes empty cells in schema 2. Both refuse such a row (one with a failure, one with an error). Noted for S10 if malformed files ever turn up. |

## Leftovers

- **BACKLOG 75:** the launcher badge (tray) and the in-app bell (unread
  alerts) count different things.
- **BACKLOG 76:** one `p` event gives two sound notifications about 21 s
  apart (PRESSURE_PEAK, then LOAD_CONCENTRATION). Needs a user decision.
- **BACKLOG 77:** a board refused by its side byte is logged as
  "disconnected by user".
- An app update removes the app's notifications from the tray (Android
  behaviour; BACKLOG 72 notes it).
- The left board's USB cable is flaky: 4 drops at 15:53–15:54. Use
  another cable at SR.
- Item 2: whether the user tapped Disconnect on the right foot at 15:02:39
  is unconfirmed.
- The phone still holds TEST-003, TEST-004 and TEST-012 staged, and
  TEST-013 (trial 00 only). Nothing was deleted.

## Decisions needed

1. Confirm or reject each checkpoint item above (waiting on user).
2. BACKLOG 76: two sounds for one cause. Keep, make the second one
   silent, or group them?
3. BACKLOG 75: leave the badge vs. bell difference, or set the badge
   from the unread count (S10)?

## SR must still check (8–11 Nov, real boards)

1. **Items 1 and 5:** 30-minute run unplugged (gaps, steps, smoothness,
   battery) and scanning cost, at ≥ 60 % battery.
2. **Baseline on real boards standing still:** Researcher recording
   accepted. If it is refused as "moved", record the walking-gate
   statistic and tune `motion.walkingAccelG`. Also refused as "moved"
   when the person shifts, and on a disconnect.
3. **A real 30 s trial 00** in a rehearsal shows "Baseline … OK", with
   the sample counts per foot (1495–1501 is fine).
4. **Sound:** that a foot alert is heard on the study phone at the
   volume the volunteer will use.
5. **Screen off for longer:** a foot alert after 1, 5 and 15 min with
   the screen off (BACKLOG 72), during the 30-minute run.
6. **The auto-reconnect search cost** with one board off for a long
   time (BACKLOG 52).

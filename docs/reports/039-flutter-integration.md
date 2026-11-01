# 039 — S9-1: step merge, preprocessing "ทางเอ", foot alert notifications

Branch `work/flutter-integration` · 2026-11-01 · from main 8e90b87. Plan
approved 2026-11-01 with user decisions 1–11 (SESSIONS §S9). S9 is split:
this report covers **S9-1 (code)**. The Note 10 checkpoint and the release
APK are **S9-2** (`work/flutter-integration-2`, report 040) and start once
this PR is merged.

## Summary

- **STEP 0:** the evening reminder is not an app bug. Android delivered it
  late, inside its inexact window, and the notification is still in the
  tray, unseen (evidence below). Report 037 is corrected: `allowNoti=false`
  is printed for every app on this build, and foot alerts had no system
  notifications before S9.
- **BACKLOG 63 closed:** one phone only. STUDY-FALLBACK is retired.
  STUDY-CAPTURE now says to export after every participant and run
  `load_capture.py` check before the next one, and lists the study-day kit.
- **BACKLOG 51 resolved:** stances are merged across a dip shorter than
  `steps.mergeGapMs` (new provisional key, 120 ms). It was checked against a
  replay of the pre-fix simulator walk.
- **Preprocessing "ทางเอ":**
  - a per-insole quiet-standing baseline (median, all 28 channels), then
    Min-Max with no clipping;
  - a Python reference and Dart code, matched bit for bit by shared test
    vectors;
  - drift schema v3, which adds the baselines table;
  - Researcher › "บันทึกค่ายืนนิ่ง 30 วินาที";
  - without both baselines the Gait tab uses its rules and says why.
- **Foot alert notifications:** TEMP_DELTA, PRESSURE_PEAK, PRESSURE_PTI and
  LOAD_CONCENTRATION.
  - None during a research capture.
  - Sound or silent channel, picked by "เสียงแจ้งเตือน".
  - A tap opens the alert's detail over Alerts. During a capture a tap
    navigates nowhere (spec-review fix).
  - New icon `ic_stat_foot_alert`, added to keep.xml.
- **Tests:** 1034 pass and analyze is clean. All emulator checks pass. The
  spec review found 1 blocker, 1 major and 1 minor issue; all 3 are fixed.

## What changed (5 commits)

| Commit | Content |
|---|---|
| 48eadae | Docs first: SESSIONS §S9 (decisions, split, STEP 0), STUDY-FALLBACK retired, STUDY-CAPTURE, FLUTTER-PLAN, BACKLOG 63 closed, report 037 corrected |
| 632cd84 | BACKLOG 51: `StepDetector` merge, `steps.mergeGapMs` (both `thresholds.json` copies), replay harness `firmware/simulator/tools/presplit_walk/` + fixture, tests, 6 Gait goldens (58 → 57 steps) |
| ec98dee | Preprocessing "ทางเอ": `shared/model_preprocess.json`, `tools/model/preprocess.py`, `lib/gait/preprocess.dart`, vectors, `normalization.json` → baseline-minmax, schema v3 + `baseline_repository.dart`, `baseline_recorder.dart`, `baseline_screen.dart`, `RulesBecause.noBaseline`, dummy model regenerated, goldens |
| 9d88bf9 | Alert notifications: `LocalNotifications` (one plugin init, taps routed by payload), `AlertNotifier`/`LocalAlertNotifier`, `AlertNotificationService`, `AlertEngine.raised`, `AlertNotificationHost`, icon + keep.xml, tests, DESIGN-SPEC §11.9, BACKLOG 72–74 |
| a86c952 | Spec-review fixes (table below) |

## STEP 0: the evening reminder on the Note 10 (read-only)

The phone is the Note 10, serial RF8M83P4STZ. It was checked with
`dumpsys notification`, `dumpsys alarm`, the standby bucket, the Samsung
sleeping-app lists and the app's foot-check table. Nothing was changed.

- **31 Oct alarm:**
  - due 16:22:00, delivered 16:32:29, inside the inexact 1 h window
    (BACKLOG 62);
  - the app posted id 20261031 at 16:32:59 on `foot_check_reminder`
    (importance 4);
  - it is still in the tray unseen, with launcher badge 1.
- **Pending alarms:** 13, for 1–13 Nov at 16:22.
- **App state:**
  - no foot check saved today;
  - standby bucket 40;
  - not in Samsung's sleeping or deep-sleeping lists.
- **Phone settings:** the ringer was on VIBRATE and DND was off. With the
  screen off, a vibrate-only notification is easy to miss.
- `allowNoti=false` is printed for every package on this One UI build, so
  it does not reflect the app's switch. Report 037 had misread it.
- **Cause:** Android posted the reminder late and quietly; the app did not
  fail to post it. Lateness stays for S10 (decision 10). There is no
  foreground service, so Freecess freezes the app once it leaves the
  screen. S9-2 measures what that does to foot alert notifications
  (decision 9, BACKLOG 72).

## Verify

### Static checks and tests

| Check | Result |
|---|---|
| `flutter analyze` | pass, no issues |
| `flutter test` (incl. goldens) | pass, 1034 tests |
| `node shared/test_vectors/generate.mjs --check` | pass, "test vectors up to date" |
| `python3 tools/model/preprocess.py --selftest` | pass (also after the review fixes) |
| `python3 tools/capture/load_capture.py --selftest` | pass |
| `pio test` (simulator, after the replay harness) | pass, 7/7 |
| Dart preprocessing vs `shared/test_vectors/model_preprocess/` | pass, bit-identical float32 for all 4 cases |
| Drift migrations v1→v3, v2→v3 | pass, rows kept |

### Rules (FLUTTER-PLAN §6)

| Rule | How it holds |
|---|---|
| 2 staleness at read time | Researcher "connected now" reads the 10 Hz snapshot's `usable`, computed at read time, not the leftover calibration (review fix 2) |
| 4 two-foot metrics | Model A runs only with a baseline for **both** connected insoles; the recorder needs both feet streaming |
| 10 50 Hz path separate | the recorder listens to `DeviceManager.batches`; the display reads the 10 Hz snapshot |
| 11 gait is not risk | gait results never notify; only the 4 foot-alert codes do |
| 12 no hardcoded thresholds | `mergeGapMs` and `contactKpa` come from `thresholds.json`, `baselineSeconds` from `model_preprocess.json`; `no_threshold_literals_test` passes |
| 13 plain-Thai advice | each notification carries the alert's own "ควรทำ" line from `alert_copy.dart` (draft, Appendix A) |
| 15 photos stay on device | notifications carry no photo; lock-screen visibility is private |
| 16 reduce motion | no new animation; the recorder's bar is determinate and set by sample count |
| capture unchanged | capture recording, export and timing are untouched; only the clear-test-data dialog text changed |

### Emulator (Pixel 7 AVD, driver build, `MOCK=standing`, `GAIT_MODEL=dummy`)

All screenshots are in `docs/reports/039-flutter-integration/`.

| # | Check | Result |
|---|---|---|
| 1 | Gait tab, toeWalk, dummy model, no baseline: "ประเมินด้วยกฎพื้นฐาน เพราะยังไม่ได้บันทึกค่ายืนนิ่ง" | pass (`emu-gait-no-baseline.png`) |
| 2 | Researcher › "บันทึกค่ายืนนิ่ง 30 วินาที", standing: recording, then both feet saved with 1501 samples each | pass (`emu-baseline-recording.png`, `emu-baseline-saved.png`) |
| 3 | Gait tab, toeWalk, with both baselines: the model runs. The reason changes to "…เพราะโมเดล AI ยังไม่มั่นใจพอ", as expected for the dummy model | pass (`emu-gait-model-with-baseline.png`) |
| 4 | Preset `rest`: TEMP_DELTA posted ("alerts: notified tempDelta #1 (silent)") on `foot_alert_silent` (Settings sound is off on the AVD). dumpsys shows `vis=PRIVATE` and BigText | pass (`emu-notification-shade.png`) |
| 5 | Tapping the notification opens that alert's detail; Back goes to the Alerts list | pass (`emu-alert-detail-from-tap.png`, `emu-alerts-after-back.png`) |
| 6 | `get_runtime_errors` | 3 entries, all "Guarded function conflict" inside the flutter_driver extension from overlapping driver taps (one had timed out). None came from the app, and the run log had no app exceptions |

## Independent review (spec vs implementation)

`spec-reviewer` ran on `git diff main...HEAD` (at 9d88bf9). Its findings
are copied as returned, with a resolution column added.

| # | Severity | File:line | Spec | Mismatch | Resolution |
|---|---|---|---|---|---|
| 1 | blocker | `mobile/lib/ui/alert_notification_host.dart:38` | DOCS STUDY-CAPTURE.md "While recording, nothing reacts to a short touch, and Back is blocked. The only controls are two hold-for-2-seconds buttons"; FLUTTER-PLAN §1 "needs a long press to stop early"; DESIGN-SPEC §11.9 "Never during a research capture" | No notification is posted during a capture, but a tap on one already in the tray is still handled. If an alert notification was posted before the session screen opened, a tap on it during recording runs `popUntil((r) => r.isFirst)`. `Navigator.pop`/`popUntil` skip `PopScope(canPop: !_busy)` (`capture_flow_screen.dart:81`), so `CaptureFlowScreen` is disposed and its `dispose()` calls `session.dispose()`. That finalizes the running trial as `EndReason.interrupted` (`capture_session.dart:543-547`) and closes the active capture stamp. One short tap ends a recording, with no long press. The reminder tap at `foot_check_host.dart:77` already did the same before this branch; this branch adds a second, much more likely trigger. | **Fixed (a86c952).** Confirmed in code. Both `AlertNotificationHost._openAlert` and `FootCheckHost._openFootCheckTab` return without navigating while `activeCaptureProvider` is set. The tapped alert stays in the Alerts list. DESIGN-SPEC §11.9 now states this. New test: a tap during a capture, on an alert or on the reminder, leaves the route and the tab unchanged. |
| 2 | major | `mobile/lib/ui/screens/researcher_screen.dart:234`, `mobile/lib/ui/screens/researcher/baseline_screen.dart:58,112,293` | DESIGN-SPEC §10.2: the value is "เชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน" … "(for the insoles connected now)" | Whether an insole is "connected" is read from `calibration?.deviceId`. `BleDataSource._cal` is only cleared when `connectTo` binds a different device (`ble_data_source.dart:156`), not on disconnect or loss. So once both insoles have been connected in this run, the Researcher row never shows "เชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน". It shows "บันทึกแล้วทั้งสองข้าง · …" / "ยังไม่ได้บันทึก: …" for insoles that are no longer connected, and the recorder's foot card never shows "ไม่ได้เชื่อมต่อ". Gait is not affected: the estimator also needs both feet usable, and Start needs both streaming. | **Fixed (a86c952).** New `streamingInsoleId()`: the calibration id only when the snapshot says that foot is usable (streaming and fresh). Both the Researcher row and the recorder use it. The test uses the mock `noData` preset, which keeps a calibration while not streaming, so it reproduces this case. |
| 3 | minor | `mobile/lib/gait/preprocess.dart:31-50` (and `tools/model/preprocess.py` `load_spec`) | DATA-CONTRACT §7.1 "Preprocessing, S9": "version 1: `baselineSeconds` 30, … the app refuses any other value" | `PreprocessSpec.parse` and the Python `load_spec` check version, statistic, channels, scale, clip and method, but accept any `baselineSeconds`. A file with, say, 10 would load, and the recorder would use 10 s. | **Fixed by aligning the wording (a86c952).** `baselineSeconds` is a duration that is read, like a threshold (rule 12), not a method switch. Dart now refuses a value that is not a positive whole number (tests: 0, 2.5). Contract §7.1 and the `_comment` in `model_preprocess.json` now say that only the method values are refused. Both copies stay byte-identical. |

**Spec gaps it raised**

- **`StepDetector.reset()` drops a step waiting out the merge window.**
  - **Resolution:** this is intended. A loss means the stance may have
    continued in the lost samples, and a stance cut by a loss was never
    counted.
  - The contract §8 addendum now says so (a86c952).
- **DESIGN-SPEC §13:** the S9 decisions were inserted inside the S8C list,
  so 18–19 were duplicated.
  - **Resolution:** moved after the S8D-2 list and renumbered 30–31
    (a86c952).
- **§11.9 did not cover a tap during a capture.**
  - **Resolution:** now stated (finding 1).
- **§11.9 does not say when the notification permission is asked for foot
  alerts.**
  - **Resolution:** left open as BACKLOG 73, because it needs a user
    decision (below).

## Leftovers and notes

- `firmware/simulator/README.md:125` still mentions the laptop fallback.
  It was left alone because this session only touched `firmware/simulator/`
  for the replay harness. Fix it with the next simulator edit.
- **BACKLOG 72:** foot alert notifications with the screen off. Measured in
  S9-2; the result goes into FLUTTER-PLAN §10 as a thesis limitation.
- **BACKLOG 73:** the notification permission is asked only by the foot
  check and the reminder.
- **BACKLOG 74:** the app's baseline is a separate 30 s recording, while
  training uses capture trial 00. Decide this before Model A is used.
- **BACKLOG 61:** `ic_stat_foot_alert` is in `AndroidResources` and
  keep.xml. The release check (`tool/check_release_resources.sh`) runs on
  the S9-2 release APK and must list it.
- **Test-log noise:** some widget tests print "reminder: sync failed" and
  "alerts: not stored" with no database or plugin present. This is harmless
  and existed before this session, but it hides real output.
- **Emulator driving:** driver taps on scrolled or lazy items time out, and
  overlapping taps cause the driver-side errors in check 6. adb input was
  used for those taps.

## Decisions needed

1. **BACKLOG 73:** should a first foot alert ask for the Android
   notification permission? Today a user who never opens "ตรวจเท้า" and
   never turns on the reminder gets no foot alert notifications.
   Recommended: ask once at the first connection of both insoles.
2. **BACKLOG 74:** which baseline should Model A use: the app's
   Researcher recording or capture trial 00? This is needed before Model A
   is trained or shipped.

## Next session: S9-2 (Note 10 checkpoint, waiting on user)

It requires this PR merged. Branch `work/flutter-integration-2`, report 040.

**Hardware:**

- Both simulator boards on 8 + 8:
  - the left board on the laptop, by-id CP2102 port only, for the `t`/`p`
    commands;
  - the right board on a USB charger.
- The Note 10 on USB, unlocked, with USB debugging allowed.
- The release APK must pass `tool/check_release_resources.sh` and is
  installed with `adb install -r` only.

**Checklist (waiting on user):**

1. 30-minute run with the fixed step detector (battery, smoothness).
2. My feet check with `p`/`t` on the 8-site Temperature tab.
3. DEVICE_LOST.
4. Auto-reconnect with the screen on and off (BACKLOG 45), and scanning
   cost (BACKLOG 52).
5. Reduce-motion.
6. Foot alert notifications with the screen on, off, and with the app in
   the background (BACKLOG 72).
7. A notification tap during a research capture navigates nowhere.
8. Record a baseline on the real boards; the Gait tab reason changes.
9. Connect both insoles unaided.

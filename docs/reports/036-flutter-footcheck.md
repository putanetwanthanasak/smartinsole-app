# 036 — S8C: Daily foot check

Branch `work/flutter-footcheck` · 2026-10-26 · DESIGN-SPEC §11 (with §4,
§7.1, §12, §13), the user's S8C decisions of 2026-10-26 and the approved
plan.

## Summary

- **The whole flow is built (§11):**
  - Start;
  - Capture: 4 views, automatic camera with "สลับกล้อง", a 3 s timer,
    skip, the cancel sheet and the camera panels;
  - Compare & answer, comparing with the newest earlier photo;
  - Something found;
  - Saved, plus the found-today tab;
  - photo history and its viewer.

  Several checks a day are allowed; the latest one is the day's result.
  Home's card shows only until today's check is saved.
- **Evening reminder (§11.8, new):**
  - a system notification for the next 14 days, at the set time in the
    phone's time zone;
  - silent when "เสียงแจ้งเตือน" is off;
  - dropped for today once today's check is saved;
  - restored after a reboot;
  - a tap opens the "ตรวจเท้า" tab.

  Android 13+ asks for the permission at the first open of the tab. While
  it is refused, Settings shows a line that asks again or opens the app's
  notification settings.
- **Photos never leave the app (rule 15):**
  - kept in its private folder;
  - cropped to the viewfinder, 1600 px, JPEG q85;
  - **no EXIF or other metadata** (tested);
  - the camera's temp file is deleted at once;
  - a start-up sweep removes unsaved photos and camera temp files.

  The saved photo is the **true view** whichever lens took it (decision 1).
- The emulator run found and fixed **three defects**:
  - a camera race when the permission dialog appears (the camera then
    failed to open);
  - front photos were saved mirrored;
  - Saved opened part-way down the tab.

  It also showed that the camera plugin mirrors the front preview on only
  one of its two rendering paths; the app now mirrors it on the other.
- `flutter analyze` is clean. `flutter test` passes **883** tests (786
  after S8B), with 24 new goldens.
- The spec review found 1 high, 3 medium and 5 low issues. The high one:
  a mock or driver run could have deleted the phone's real foot photos.
  All nine are fixed, the last after the user's screenshot review.
- The user's decisions after the review are applied (7357fca). The
  release APK is rebuilt from that commit.
- **Note 10 checkpoint: waiting on user** (checklist below). Run 1
  (2026-10-29) found that the reminder never worked in the release APK:
  the icon was stripped by resource shrinking (fixed, with a release-APK
  check), and Settings gave no warning while the phone blocked the app's
  notifications (fixed). Items 12, 13, 14 and 16 are re-run on 2026-10-30.

## What changed

Nine commits (`git log main..HEAD`); the last, 7357fca, applies the
user's decisions after the review (see "Decisions after the review"):

| Area | Files |
|---|---|
| Packages, Android | `pubspec.yaml`: `camera` 0.12.1, `flutter_local_notifications` 22.3.3, `flutter_timezone` 5.1.1, `timezone` 0.11.2, `image` 4.12.0. Manifest: CAMERA (feature not required), POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, the plugin's alarm and boot receivers. `build.gradle.kts`: core library desugaring. `res/drawable/ic_stat_foot_check.xml`. `MainActivity.kt`: channel `smartinsole/camera_preview` (which preview path the camera plugin uses). |
| Foot-check core | `lib/footcheck/` (new; see its README): `FootCamera` + `PluginFootCamera`, `photo_processor.dart`, `photo_session.dart`, `foot_check_flow.dart`, `footcheck_providers.dart`, `compare_source.dart`, `history.dart`, `orphan_sweep.dart`, `foot_views.dart`. `storage/foot_check_repository.dart`: `watchRange`, `latestPhotoBefore`, `watchWithPhotos`, `photoPaths`. |
| Reminder | `lib/notify/` (new; see its README): `reminder_plan.dart`, `time_zone.dart`, `reminder_notifier.dart`, `local_reminder_notifier.dart`, `reminder_providers.dart`. `settings_store.dart`: `notify.promptShown`. |
| Screens | `lib/ui/screens/foot_check/` (new): Start, Capture, Compare, Saved / found-today, history, viewer, guide, week card, photo tile, copy. `foot_check_screen.dart` (the tab), `foot_check_found_screen.dart` (rewritten to §11.4), `home_screen.dart` (card only until today's check), `settings_screen.dart` (permission line), `foot_check_host.dart` (new), `app.dart` (routes, `appNavigatorKey`), `routes.dart`, `motion.dart` (capture motions), `dimens.dart`, `segmented_tabs.dart` (`radio`, `small`), `back_link.dart` (`onTap`). |
| Tests | `test/footcheck/` (processor, files, compare and history, screens; `foot_check_rig.dart`), `test/notify/reminder_plan_test.dart`, `test/goldens/foot_check_golden_test.dart` (24 goldens), `test/helpers/` (`FakeFootCamera`, `FakeReminderNotifier`; `pumpApp` uses them by default). |
| Docs | DESIGN-SPEC §11 intro, §11.2, §11.3, §11.5, new §11.6–§11.8, §14 (decisions 12–18, defaults, not-designed list); READMEs of `lib/footcheck/` and `lib/notify/`; `mobile/CLAUDE.md` layout, keys, test helpers; BACKLOG 56–60. |

## Decisions and how they were applied

| # | Decision (user, 2026-10-26) | Applied |
|---|---|---|
| 1 | True sole view is the reference; front preview mirrored; guide matches the preview; saved photo un-mirrored | `guideOutlineOf(view, previewMirrored:)` picks the outline the preview shows (unit test, all four cases). The saved photo keeps the sensor's view: the EXIF rotation is applied and any EXIF mirror flag is undone (`photo_processor.dart`, tests for orientation 1, 2, 5, 6). The front preview is mirrored on both of the plugin's paths (see "Emulator" below). |
| 2 | Sound off → silent reminder | Two channels, `foot_check_reminder` and `foot_check_reminder_silent`; the sound switch picks one at scheduling. Emulator: with sound off the reminder came on the silent channel (`vibrate=null sound=null`). |
| 3 | Permission at first tab open and when the switch turns on; denied → Settings line, Saved hides the reminder line | `FootCheckHost` asks once (`notify.promptShown`); the switch asks; `settings-notify-denied` row; Saved's line hidden. Widget tests for all three. Emulator: prompt, deny, Settings line, ask again, allow (screenshots 02–06). |
| 4 | Found-tab design option 1 | `saved_view.dart` found-today card as specified (§11.6); golden `foot_check_found_today`. |
| 5 | `tz.local` = device zone, never UTC | `initLocalTimeZone` from `flutter_timezone`; unit test: 19:00 Asia/Bangkok is scheduled at 19:00 local (12:00 UTC). Emulator log: "local time zone Asia/Bangkok"; alarms at `2026-10-26 19:00` local (`origWhen 1793016000000` = 12:00 UTC). |
| 6 | No metadata in saved JPEGs | Encoder writes no APP1–APP15 or COM segment; test checks the markers, empty EXIF and no device model string. |
| 7 | "ยกเลิก" asks once a photo is taken | `showConfirmSheet` with the draft copy; widget test: no photo leaves at once; "ถ่ายต่อ" keeps the photo; "ยกเลิกการตรวจ" deletes it; golden `foot_check_capture_cancel_sheet`. |
| — | Plan defaults (reminders, compare source, processing, camera choice, back from Compare, repeat check, folders, sweeps, history, camera panel, latest check of the day) | As planned; see DESIGN-SPEC §11 and the READMEs. One change: the processor no longer flips front photos (see "Emulator"). |

## Independent review (spec vs implementation)

The `spec-reviewer` agent read `git diff main...HEAD` against DESIGN-SPEC
§11, §4, §7.1–§7.2, §12, §13, §14 and FLUTTER-PLAN §6 / §9. It found
1 high, 3 medium and 5 low issues. Eight are fixed in 353832a. Finding 9
was at first marked "no change needed"; the user showed it was real, and
it is fixed in 7357fca.

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | high | The start-up orphan sweep deletes every file in the real `foot_photos` folder that the database doesn't list. A mock-preset or driver run uses an in-memory database (no checks), so one such launch on a phone with saved checks would have deleted every saved foot photo. | **Fixed.** `AppDatabase.inMemory`; `footPhotoPath` gives an in-memory run its own cache folder `foot_photos_memory`, so the real folder is never listed or swept by those runs. Unit test. Nothing had been deleted: no debug, mock or driver build of this branch has run on the Note 10. |
| 2 | medium | A shot, skip or "สลับกล้อง" during the self-timer left the countdown running, so it could take the next view unasked. | **Fixed.** `_stopCountdown()` on shot, skip, switch and every view change. Widget test (skip, then switch, during a countdown: no shot). |
| 3 | medium | The camera panel's "ไม่ถ่ายรูป ตอบคำถามอย่างเดียว" opened Compare as a photo run (picker, 4 "ไม่ได้ถ่ายภาพนี้" frames). | **Fixed.** With no photo taken, the run becomes answer-only and replaces Capture, so back returns to the tab. If photos were already taken (camera failed mid-check), they are kept and Compare shows the rest as not taken: nothing is deleted without asking. Two widget tests. |
| 4 | medium | "อนุญาตให้ใช้กล้อง" always opened the app's settings, even when Android would still show its dialog. | **Fixed.** `CameraUnavailable.askAgain` (from `isPermanentlyDenied`). It asks again while Android shows the dialog, otherwise it opens settings. Widget test. |
| 5 | low | The thumbnail fade (§12.2: 150 ms from 380 ms) was cut off at 400 ms. | **Fixed.** The fly controller runs 530 ms; the move still takes 400 ms. |
| 6 | low | The switch icon was 24, but §11.2 says 26. | **Fixed.** `Dimens.switchCameraIcon` = 26; Capture goldens regenerated. |
| 7 | low | The 7-day row was not announced as a list (§11.5, §13). | **Fixed.** `SemanticsRole.list` with `listItem` per day. |
| 8 | low | The time-zone fallback used UTC for offsets that are not whole hours. | **Fixed.** The fallback is a fixed-offset zone for any offset (`Fixed+0530`). Unit test. |
| 9 | low | The quoted "มี / ไม่แน่ใจ" in the Compare note could break across lines. | **Fixed in 7357fca.** At first I marked this "no change needed": the no-break spaces around "/" looked enough. That was wrong. Screenshot `15` shows "มี / ไม่" \| "แน่ใจ", because Thai word breaking still splits "ไม่แน่ใจ". Word joiners (U+2060) now keep the phrase together. `thai_line_break_test` lays the note out at every width from 180 to 400 px and at scales 1.0, 1.3 and 1.88. Goldens `compare_note_100` / `_130` are at the Pixel 7's 412 px. |

Spec gaps the reviewer raised:
- **Is a foot-check alert read when Something found opens right after
  "บันทึก", or from "ดูสิ่งที่ควรทำ"?** The code marked it read only from
  the Alerts list, which differed from §7.2 decision 7. Fixed in 7357fca
  (user decision below).
- **§11 intro wording.** It said Home's card "hides at midnight". That
  was wrong: the card comes back on a new day. Fixed in the spec text.
  The code was already right (widget test "midnight rollover").
- **Something found has no back link (§11.4).** The Android back gesture
  still works and returns to the tab. The spec doesn't say to block it,
  and blocking system back would trap the user. Left as is.
- **Controls during the self-timer.** They stay enabled, and any of them
  stops the timer (finding 2).

## Verify

### Static checks and tests

- `flutter analyze`: no issues. `dart format`: clean.
- `flutter test`: **883 passed** (after the review fixes and the user's
  decisions).
- `flutter build apk --release`: builds, 92.8 MB (87.9 MB after S8B, +4.9 MB:
  camera, notifications, `image`).
- New tests:
  - processor: crop and size; q85; no metadata; EXIF rotation; EXIF mirror
    undone; not-a-JPEG refused;
  - photo files: session, discard, the two sweeps;
  - compare source and history;
  - reminder plan: 14 days; today skipped once checked; switch off; time
    change; ids; Asia/Bangkok;
  - 31 foot-check widget tests: tab states; Home card; latest check of
    the day; 7-day row; answer-only; "บันทึก" enabled after 3 answers;
    finding → Something found + alert (rule 14); radio semantics; camera
    choice and switch; 4 photos stored; cancel sheet; timer; camera
    refused; the permission-dialog race; compare captions; history and
    viewer; reminder scheduling, silence, time change, launch and tap;
    the one-time prompt; the denied Settings line; Saved hiding the
    reminder line; midnight rollover; Saved opening at the top.
- Goldens (24, `test/goldens/screens/foot_check_*.png`):
  - Start at 100 % and 130 %, and Start as a repeat check;
  - Saved, Saved with yesterday's finding, Saved with the reminder off;
  - the found-today tab and Something found;
  - Capture: first view, second view, top view on the back camera,
    countdown, cancel sheet, camera refused, camera failed;
  - Compare: yesterday, earlier, none + answered, skipped, answer-only;
  - history, empty history, viewer;
  - Settings with the denied line.

  The `foot_check` tab golden changed from the S6A placeholder to Start.
  Two defects were found in the goldens and fixed: the camera panel's
  outlined button had white text on white, and the viewer showed the
  photo at its intrinsic size.

### Rules (FLUTTER-PLAN §6)

| Rule | Check |
|---|---|
| 12 | No thresholds involved; no numeric clinical literals added. |
| 14 | The result comes only from the answers, in `FootCheckRepository.save` (unchanged); "มี / ไม่แน่ใจ" → found. Nothing says a foot is normal: Saved says "บันทึกแล้ว", and the 7-day and history tags use the saved colours, never green. The Compare note says the app does not check photos. |
| 15 | No share, MediaStore or gallery API (`grep`). Photos only under the app's private `foot_photos/`; camera temp files deleted at once and swept at start. |
| 16 | Every capture motion goes through `Motion.duration` / `Motion.reduced`; under reduce motion the countdown digits change without animation, and there is no thumbnail fly or fade (widget tests run both). |
| Theme | No `Color(0x…)`, `fontSize:`, `Duration(` or `Curves.` in the new screens (`grep`). Icon-only buttons ("สลับกล้อง", the shutter, the timer, skip) have Thai labels. |

### Emulator (Pixel 7 AVD, Android 16 / API 37, time zone Asia/Bangkok)

Run with `flutter run -t test_driver/main_mcp.dart --dart-define=BLE_FAKE=true`
(in-memory database) and the Dart MCP driver. Back camera = virtual scene,
front = emulated. Screenshots in `docs/reports/036-flutter-footcheck/`.

| # | Check | Result | Evidence |
|---|---|---|---|
| E1 | Home card before the check | **pass.** "วันนี้ยังไม่ได้ดูเท้า" shown. | `01` |
| E2 | Notification prompt at the first open of the tab (API 33+) | **pass.** System dialog "Allow smartinsole to send you notifications?" when "ตรวจเท้า" first opened. | `02` |
| E3 | Deny → Settings line | **pass.** "Don't allow" → `POST_NOTIFICATIONS: granted=false, USER_SET`; Settings shows "ต้องอนุญาตการแจ้งเตือนในโทรศัพท์ / ตอนนี้แอปเตือนให้ดูเท้าไม่ได้ แตะเพื่อเปิด". | `03`, `04` |
| E4 | Turn on from Settings | **pass.** Tapping the line showed the system dialog again; "Allow" → `granted=true`, the line disappeared, and 14 reminders were scheduled. | `05`, `06` |
| E5 | Time zone | **pass.** Log: "reminder: local time zone Asia/Bangkok". Alarms at 19:00 local for 26 Oct – 8 Nov. | log, `dumpsys alarm` |
| E6 | Reminder fires at the set time | **pass (inexact).** Set to 14:00 at 13:56. Posted at 14:01:31 (Android's window for that alarm was +2 min 52 s), id `20261026`, channel `foot_check_reminder_silent` (sound off), text "ถึงเวลาดูเท้าประจำวัน / ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที". | `07` |
| E7 | Tap opens the tab | **pass.** With Settings open on top, the tap returned to the "ตรวจเท้า" tab. | `08` |
| E8 | Camera permission + first camera open | **failed, then fixed.** First run: the camera did not open ("เปิดกล้องไม่ได้"); CameraX "No supported surface combination … too many use cases" and an unhandled null check in the plugin. Cause: the permission dialog made the app inactive while the open was in progress, so a close and a second open overlapped the first inside the plugin. Fix (453dc57): `PluginFootCamera` runs its calls one at a time; Capture ignores an open that a release or newer open overtook; the plugin's non-`CameraException` errors are caught. Re-run after revoking the permission: dialog → "While using the app" → preview at once, no errors. Widget test added. | `09`, `10` |
| E9 | Automatic camera | **pass.** Soles on the front camera, tops on the back camera (virtual scene). | `10`, `12` |
| E10 | Front photo orientation (decision 1) | **failed, then fixed.** See "Front camera orientation" below. | `13` |
| E11 | Back from Compare | **pass.** Back to view 1 with the 4 photos kept. | `14` |
| E12 | Compare, answers, save | **pass.** "ยังไม่มีรูปก่อนหน้า" over "ครั้งก่อน" (first check, empty database); answers selected as specified; "บันทึก" enabled after 3; Saved "วันนี้ดูเท้าแล้ว เวลา 14:18 / พรุ่งนี้แอปจะเตือนตอน 14:00", 7-day row with today saved. | `13`, `15`, `16` |
| E13 | Saved scroll position | **failed, then fixed.** Saved opened at Start's scroll offset (title cut off). Fix: the tab's scroll view is keyed by the view. A widget test at 130 % text fails without the fix (offset 95) and passes with it. | `16` (after the fix) |
| E14 | Home card after the check | **pass.** Gone. Settings: "ลบรูปถ่ายเท้าทั้งหมด / ตอนนี้มี 4 รูป". | `17` |
| E15 | Today's reminder dropped once checked | **pass.** Time set to 15:00 (after the 14:18 check): reminders 27 Oct – 8 Nov, none today. | `dumpsys alarm` |
| E16 | Photo history and viewer | **pass.** One card "เวลา 14:18 · บันทึกแล้ว" with the 4 photos; the viewer shows the back photo full screen with "ปิด" and "หลังเท้าซ้าย · จันทร์ 26 ต.ค. 14:18". | `18`, `19` |
| E17 | Survives a reboot | **pass.** App started normally and left with Home (`stopped=false`), 14 reminders; `adb reboot`; after boot, without opening the app, the 14 reminders were back (boot receiver). A first attempt after killing `flutter run` showed none: that left the app force-stopped (`stopped=true`), and Android sends no boot broadcast to a stopped app. A patient closing the app normally does not force-stop it. | `dumpsys alarm`, `dumpsys package` |
| E18 | After the reboot, the reminder fires and a tap launches the app | **pass.** The reminder set for 15:00 was posted at 15:01:21 (inexact), on `foot_check_reminder_silent` (sound off). The app had not been opened since the reboot: the alarm receiver started its process, with no activity. A tap at 15:05 started `MainActivity` on the "ตรวจเท้า" tab (Start: the driver build's in-memory database was empty). | `20` |
| E19 | Timing | **101 s** from "เริ่มถ่ายรูป" to Saved, driven by the MCP driver: the emulator's first capture after each camera opens takes several seconds, and two taps landed while a shot was still saving. Not a measure of a person; the Note 10 checklist times a real check. | — |

Screenshots `11`, `12` and `14` are from the first camera run, before the
processor fix; their sole thumbnails are the old (mirrored) processing.

#### Front camera orientation

- **What happened.** In the first run, the saved left-sole photo had the
  same handedness as the live front preview. The preview is mirrored, so
  the saved photo was mirrored too: the opposite of decision 1.
- **What the emulator showed.**
  - A temporary log printed the camera JPEG's EXIF orientation: **8**, a
    rotation with no mirror flag. CameraX (via this plugin) saves the
    front photo as the sensor sees it, the true view.
  - The processor's planned "un-mirror front photos" step was therefore
    *adding* a mirror.
  - The `image` package's JPEG decoder already applies the full EXIF
    orientation, so the separate `bakeOrientation` call did nothing.
- **Fix (453dc57).**
  - The processor never flips by camera. It undoes only an EXIF mirror
    flag (orientations 2, 4, 5, 7), which is the only way CameraX mirrors
    a saved photo.
  - Result: the true view on any phone, whether or not its camera stack
    sets the flag.
  - Unit tests cover orientations 1, 2, 5 and 6.
- **Re-run.** The saved left sole is now the mirror image of the live
  preview, as it should be (`13`).
- **Preview.** The plugin mirrors the front preview only on its ImageReader
  path. On the SurfaceTexture path ("surface producer handles crop and
  rotation") it shows the unmirrored image.
  - The app now asks the engine the same question through `MainActivity`
    and mirrors the preview itself on that path.
  - The emulator reports `false` (ImageReader; the plugin mirrors), so the
    app's own mirror is not exercised there. The Note 10 run logs which
    path it takes (`foot camera: surface producer handles crop and
    rotation: …`).

## Note 10 checkpoint — **waiting on user**

Before the run: "Plug the Note 10 into the laptop by USB, unlock it, allow
USB debugging." Then confirm it with `adb devices -l` (serial
`RF8M83P4STZ`). Install the release build with `adb install -r` only. No
uninstall, no `pm clear`: the phone holds study data.

The Note 10 runs Android 12 (API 31). It never shows the notification
permission dialog, so items 3 and 4 of the plan's permission test were
covered on the emulator (E2–E4).

| # | Check | How | Pass when |
|---|---|---|---|
| 1 | Install | From `mobile/`: `adb install -r build/app/outputs/flutter-apk/app-release.apk` (built from 7357fca); open the app | Existing alerts and settings are still there |
| 2 | Camera permission | "ตรวจเท้า" → "เริ่มถ่ายรูป" → allow | The preview appears at once; no "เปิดกล้องไม่ได้" |
| 3 | Preview path | `adb logcat -s flutter | grep "foot camera"` | Note the logged "surface producer handles crop and rotation: true/false" |
| 4 | Front preview mirrored | Left sole view, front camera: raise your right hand in view | The hand appears on the right of the screen, like a mirror |
| 5 | Guide | Left sole view | The dashed outline matches a left sole as seen in the (mirrored) preview: big toe toward the screen's centre line as the foot lies |
| 6 | **Front vs back orientation (decision 1)** | Check A: left sole with the front camera (phone on the floor, timer). Check B (another check, "ตรวจอีกครั้ง"): left sole with the back camera ("สลับกล้อง"), someone else holding the phone | In Compare (B vs A) and in "ดูรูปที่บันทึกไว้", both left-sole photos have the same orientation: the big toe on the same side |
| 7 | Tops | Back camera on the top of each foot | Saved photos look like what was in front of the lens (not mirrored) |
| 8 | Photo quality | Open a photo in the viewer, pinch to zoom | Sharp enough to see skin detail; no rotation error |
| 9 | Timing | A full check by the user, start to Saved, the normal way | About 1 minute (note the time) |
| 10 | Not in the gallery | Before and after: `adb shell content query --uri content://media/external/images/media --projection _id | wc -l`, and `adb shell ls /sdcard/DCIM /sdcard/Pictures`; open Gallery | Count and folders unchanged; no foot photo in Gallery |
| 11 | No metadata | Nothing to do on the phone (`run-as` is blocked); covered by the processor unit test | — |
| 12 | Reminder fires | Settings → "เวลาเตือน" a few minutes ahead (no check saved today yet), sound on; lock the phone | A notification "ถึงเวลาดูเท้าประจำวัน" with sound, within a few minutes of the set time (inexact) |
| 13 | Tap opens the tab | Tap it | The app opens on "ตรวจเท้า" |
| 14 | Silent | Sound off; set another time a few minutes ahead | Shown, no sound or vibration |
| 15 | None once done | Save a check, then set a time later today | No notification today |
| 16 | After a reboot | Leave the app with Home (no force stop), restart the phone, don't open the app; set-up as in 12 beforehand | The reminder still comes |
| 17 | Found path | A check with "มี / ไม่แน่ใจ" | Something found; the alert is in "แจ้งเตือน" and already read (no "ใหม่" chip, badge not raised by it); the tab shows the found-today card; "ดูสิ่งที่ควรทำ" opens Something found |
| 18 | Cancel | Take one photo, "ยกเลิก" | The sheet asks; "ยกเลิกการตรวจ" removes the photo (Settings count unchanged) |
| 19 | Line breaks and chip | On Capture and Compare, at phone font scale 1.3 (the phone's usual) | "ตั้งเวลา" and the quoted "มี / ไม่แน่ใจ" are never split; the hint chip shows on the two sole views only; answer-only is titled "ตอบคำถาม" |

### Note 10 run 1 (2026-10-29): in progress

The laptop side was run by Claude; the phone steps by the user. The results
below are only what was measured on the laptop or reported by the user so
far. The user re-runs items 12, 13, 14 and 16 on 2026-10-30, before saving
a check.

| # | Result |
|---|---|
| 1 | `adb install -r` of the APK built from 7357fca (nothing under `mobile/` changed after it). `firstInstallTime` stayed 2026-10-18, so the study data was kept. |
| 3 | `foot camera: surface producer handles crop and rotation: false` (logged at 12:06:19, 12:09:40 and 12:12:24). The Note 10 takes the plugin's SurfaceTexture path, where the app mirrors the front preview itself (BACKLOG 57); item 4 checks it. |
| 10 | BEFORE (11:57): MediaStore 10,310 images, highest `_id` 80754; `/sdcard/DCIM` 5,093 files, `/sdcard/Pictures` 14,785 (19,878). AFTER: to be taken when the user finishes the run. |
| 12 | **Failed.** No reminder came. Three defects and one phone setting, N1–N4 below. Fixed in 0c0ae61 and 5756720; re-run on 2026-10-30. |
| other items | Results not yet reported by the user. |

Findings:

| # | Severity | Finding | Status |
|---|---|---|---|
| N1 | high | **The release APK lacked the reminder's small icon.** The release build shrinks resources and removes any that no code references by R id. `flutter_local_notifications` looks `ic_stat_foot_check` up by name, so it was removed. Reminder setup failed at every start with `PlatformException(invalid_icon, The resource ic_stat_foot_check could not be found…)`, so no reminder was ever scheduled: `dumpsys alarm` listed 0 alarms for the app. **Why the emulator missed it:** E15, E17 and E18 ran the MCP driver build (`flutter run -t test_driver/main_mcp.dart`), a debug build, and debug builds do not shrink resources. | **Fixed in 0c0ae61.** `res/raw/keep.xml` keeps it. Names looked up at runtime are constants in `android_resources.dart`. `android_resources_test` fails if a name is not kept or if lib/ passes one as text. `tool/check_release_resources.sh` fails if a release APK lacks a kept resource; it is now part of the release build command (`mobile/CLAUDE.md`). Both checks were shown to fail with keep.xml removed. BACKLOG 61 covers S9's alert notifications. After installing 0c0ae61 (12:36): no `invalid_icon`; 13 alarms, 30 Oct to 11 Nov at the set time (12:40), today skipped because a check was already saved. |
| N2 | phone setting | **The app's notifications were blocked at system level, by the app-op alone.** `appops`: `POST_NOTIFICATION: ignore`, while `areNotificationsEnabled()` was true. Android 12 has no runtime prompt, so this was set outside the app's own flow; when and how is not known. Even with N1 fixed, no reminder would have shown. (Samsung's `allowNoti=false` in `dumpsys notification` is not this flag: it stayed false after the fix and shows for system apps that post normally.) | **Turned on by the user from the app's Settings row (5756720), 12:56.** The row opened the app's notification settings; on return the log showed `appOp=allowed` and `appops` showed no `POST_NOTIFICATION` override (default allow). |
| N3 | high | **Settings showed no warning while notifications were blocked** (the reminder switch was on). The row "ต้องอนุญาตการแจ้งเตือนในโทรศัพท์" did not show on either 7357fca or 0c0ae61. The app decided from `areNotificationsEnabled()` only, and treated an unknown answer as allowed in Settings but as blocked in Saved. **Why the emulator missed it:** the emulator (API 37) was blocked through the runtime permission, which `areNotificationsEnabled()` follows; the Android 12 app-op state was never tested. | **Fixed in 5756720.** "Blocked" now means the phone would not show the reminder, on every API level: the app switch, the Android 13+ permission or the `POST_NOTIFICATION` app-op (MainActivity's `smartinsole/notifications` channel; the decision is the pure `NotificationAccess`). The row opens the app's notification settings directly (below 13 there is no prompt). It is re-checked on resume. Settings, Saved and the reminder service read one state; unknown neither warns nor promises. Reminders stay scheduled while blocked, so they come as soon as notifications are allowed. Tests: API 31 enabled, blocked by the switch, blocked by the app-op alone; API 33+ granted, denied then granted, denied, granted with the switch off; Settings row gone and Saved line back on resume; scheduled while blocked. **Confirmed on the phone (12:55):** `reminder: notifications blocked (sdk=31 enabled=true permission=true appOp=ignored)`: `areNotificationsEnabled()` was true while the app-op blocked the app, which is why the old build showed no row. After turning notifications on from the row (12:56): `notifications allowed (… appOp=allowed)`. |
| N4 | low | **The two channels did not exist before the first reminder.** The plugin creates a channel only when it first posts to it, so the phone's notification settings listed none. | **Fixed in 5756720.** Both are created in `init()`. On the phone after install: `foot_check_reminder` (importance 4, default sound, vibration) and `foot_check_reminder_silent` (importance 3, no sound, no vibration), before any reminder fired. |
| N5 | note | **Delivery window.** `dumpsys alarm` shows each reminder with `window=+1h0m0s0ms`: Android lets an inexact alarm set a day or more ahead come up to 1 hour late, so 19:00 may arrive as late as 20:00. | Accepted for now; recorded in DESIGN-SPEC §11.8; BACKLOG 62 (revisit in S10). |

Other diagnostics from the failed item 12 (12:20, before any fix): device
idle `ACTIVE` (screen on, charging); standby bucket 10 (active); Samsung
freezer `isFrozen=false`; the app was not on the battery-optimisation
exemption list. None of these was the cause.

## Leftovers and notes for the next sessions

- **BACKLOG 56 (S10):** the notification header shows "smartinsole" and
  the default Flutter launcher icon.
- **BACKLOG 57 (Note 10):** the app's own front-preview mirror (the
  plugin's SurfaceTexture path) is not exercised on the emulator.
- **BACKLOG 58:** the driver build's database is in memory, so cross-day
  views were checked only in widget tests and goldens.
- **BACKLOG 59:** the Saved reminder for a finding older than yesterday
  is still not designed.
- **Reminders are inexact.** Android may deliver one a few minutes late
  (+1 min 31 s on the emulator, inside a 2 min 52 s window). This avoids
  the exact-alarm permission; it is stated in §11.8.
- **Reboot needs the app not force-stopped.** Android sends no boot
  broadcast to a force-stopped app, so its reminders come back only after
  the app is next opened. Normal use doesn't force-stop the app. Settings ›
  Apps › Force stop does, as does killing `flutter run`.
- **Thai line breaks.** Three phrases were split by Thai word breaking:
  "แพทย์" | "ดู" in the found-today title (golden), "มี / ไม่" | "แน่ใจ"
  in the Compare note (screenshot `15`), and "ตั้ง" | "เวลา" in the hint
  chip. Each is kept together with word joiners (U+2060), checked by
  `thai_line_break_test`. That test also has a control showing the plain
  text does split, so it can fail. Other running text may have more such
  splits; S10's text pass should look for them (BACKLOG 60).
- Health copy (Something found, the reminder text, the camera panels, the
  history note) is draft, as listed in DESIGN-SPEC §14 and Appendix A.

## Decisions after the review (user, 2026-10-26)

Applied in 7357fca. DESIGN-SPEC §14 has them as decisions 19–22.

| # | Decision | Applied |
|---|---|---|
| 1 | Answer-only is titled "ตอบคำถาม" | `FootCheckCopy.answerOnlyTitle`; golden `compare_answer_only` |
| 2 | The hint chip shows on the two sole views only | `capture_screen.dart` (`view.isSole`); golden `capture_top_back_camera` has no chip |
| 3 | A finding is read whenever Something found opens for that check: right after "บันทึก", from "ดูสิ่งที่ควรทำ", or from Alerts (§7.2 decision 7) | `AlertRepository.markFootCheckRead` called when Something found opens. Widget tests: right after saving, the alert is read; on the found-today tab, unread is 1 before "ดูสิ่งที่ควรทำ" and 0 after |
| 4 | Keep "มี / ไม่แน่ใจ" on one line in running text (review finding 9 was real) | Word joiners in `FootCheckCopy.note`, the only running text that quotes it. Line-break test plus goldens `compare_note_100` / `compare_note_130` (412 px wide) |
| 5 | Keep "ตั้งเวลา" together in the hint chip | Word joiners in the chip and in the Start tip ("ใช้ปุ่มตั้งเวลา"). Line-break test; Start and tab goldens regenerated |

Release APK for the Note 10 rebuilt from 5756720 (includes 0c0ae61):
`mobile/build/app/outputs/flutter-apk/app-release.apk`, 92.8 MB, passes
`tool/check_release_resources.sh`; SHA-256 begins `ba4edc419b1c02f1`.

## Decisions needed

None open. The Note 10 checkpoint is waiting on the user.

## Next session

The Note 10 checkpoint above, then S9 as planned in `docs/SESSIONS.md`.

# 041 — S10: wrap-up before SR

Branch `work/flutter-wrapup` · 2026-11-02 · from main 3511936 (PR #36,
S9-2). Plan approved 2026-11-02 with the user's decisions (app name
"SmartInsole"; adaptive icon, white Lucide footprints on `primary`; the
BACKLOG 76 quiet window counts from the last *sounded* notification) and
four changes at approval (header icon = notification small icon; joiners
render-layer only; order 76 → 56 → 54 → docs → joiners; an S10b row).
Plan file: `~/.claude/plans/s10-s10-wrap-up-before-rippling-moon.md`.

## Summary

- **Group A done (volunteer sees or hears it, or it affects alerts or the
  study day):**
  - **BACKLOG 76:** a second foot notification for the same foot within
    `alerts.quietNotifyMin` (2 min) of the last *sounded* one goes on the
    silent channel. It still shows in the tray.
  - **BACKLOG 56:** app name "SmartInsole"; adaptive launcher icon; the
    foot alert small icon is now Lucide footprints; notifications are
    tinted `primary`.
  - **BACKLOG 54 (Home foot tiles):** the tiles stack above text scale 1.3.
  - **BACKLOG 46, 60, 69 (Thai line breaks):** word joiners keep site names
    and short phrases whole on Home, Alerts (list and detail), My feet and
    in notifications. Display only.
  - **BACKLOG 62:** closed, accepted (inexact reminders stay).
  - **BACKLOG 75 and the STUDY-CAPTURE study-day kit:** already done in S9-2.
- **Every other open BACKLOG item is sorted:**
  - "after study (S10 sort)";
  - "SR (S10 sort)", collected in the new SR checklist in `docs/SESSIONS.md`;
  - or "user action" (43, 67).
- **Docs:** PROGRESS, mobile/CLAUDE.md, SESSIONS (status rows, schedule,
  S10b row and entry, SR checklist), DESIGN-SPEC §6, §11.9, decisions 22
  and 32, DATA-CONTRACT addendum.
- **Follow-up 2026-11-04 (3789261):** short words in titles kept whole
  too. The first screenshots showed "รับน้ำ / หนักมาก" in the PTI title;
  they predated 537f591, and a retake on 4885b9b showed it fixed. Listing
  every title line break found other splits ("อุ่น / กว่า", "ปลาย /
  เท้า", "เกิน / ไป", "เชื่อม / ต่อ", "ค่อน / ข้าง", "เหลือ / น้อย"),
  now joined. The guard covers every title style.
- **Release 1.0.0+6** rebuilt from 3789261. It passed
  `check_release_resources.sh` and the model slot is empty.
- **Note 10 smoke check: waiting on user.** Ask before plugging in (below).

## What changed

| Commit | Content |
|---|---|
| 767c1dc | BACKLOG 76: `alerts.quietNotifyMin: 2` in both `thresholds.json` (byte-identical); `Thresholds.quietNotifyMin`; `lib/notify/quiet_window.dart` (`NotificationQuietWindow.claimSound(side, atMs)`: silent when within the window of the last sounded one for that foot; only sounded ones are recorded); `AlertNotificationService` decides before any `await`; 6 tests; DESIGN-SPEC §11.9 "One sound per cause" + decision 32; DATA-CONTRACT JSON block + addendum row |
| 22e5b08 | BACKLOG 56: `android:label="SmartInsole"`; `ic_stat_foot_alert` = Lucide footprints (white, transparent, like `ic_stat_foot_check`); `ic_launcher_foreground.xml`, `mipmap-anydpi-v26/ic_launcher.xml` (adaptive + monochrome), `values/colors.xml` (#155E75); `color: AppColors.primary` on alerts and the reminder. No notification or plugin init used `@mipmap/ic_launcher` (checked) |
| 62d16af | BACKLOG 54: `_FootChips` stacks above text scale 1.3 (`_SmallCards._stackAboveScale`); goldens 130xl and 200 |
| 40ca4e3 | Docs: BACKLOG sort and statuses; SESSIONS status, schedule, S10/S10b entries, SR checklist; PROGRESS Flutter section; mobile/CLAUDE.md and `lib/notify/README.md` |
| f2d3963 | BACKLOG 46/60/69: `lib/text/thai_break.dart`; joined names in alert copy, alert detail, Home and My feet running text; no-break space before "·" and in Home's date; `test/helpers/plain_text.dart`; `test/text/thai_break_test.dart`; `thai_line_break_test.dart` extended; goldens updated, new 130 % goldens (Home, Alerts, My feet) |
| 5ad511b | Docs for the joiner pass (BACKLOG 46/60/69 resolved, DESIGN-SPEC decision 22, mobile/CLAUDE.md "Thai line breaks", how to reapply in S10b) |
| f1736bf | Version 1.0.0+6 |
| 1858d17, 537f591 | Found on the emulator: "ต่อ / เนื่อง", "รับน้ำ / หนัก" and "จุด / เดียว" joined in the pressure alert copy and Home lines; goldens |
| e53ddde | Docs wording for those |
| 4885b9b | Spec review fixes 1–3 (below); DESIGN-SPEC §11.9 one sentence |
| 3789261 | Titles (follow-up, below): `keepTogetherInTitle` + `titleParts`, `FootZone/FootRegion.titleTh`; "อุ่นกว่า", "เกินไป", "ค่อนข้าง", "เชื่อมต่อ", "เหลือน้อย" joined (also "อุ่นกว่า"/"เกินไป" in the same alerts' detail and Home lines, and the My feet banners); the guard covers every title style and fails a break inside a short table phrase; goldens (25 + 13) |

## Thai line breaks: how and what was learned

- `keepTogether(phrase)` puts U+2060 WORD JOINER **between the words** of a
  phrase. The words are listed in a table, `thaiWords`, as Flutter's
  dictionary splits them. A test checks every entry against
  `TextPainter.getWordBoundary`.
- **Finding:** the first version put a joiner between every letter, and
  that broke plain words nearby. Example: the PEAK detail "…รับแรงกดสู /
  งมากตอนเดิน". A joiner inside a word cuts the Thai around it into pieces
  the dictionary cannot read, so Flutter falls back to breaking by
  character. A joined phrase wider than the line does the same.
  - So a long name joined whole cannot go in a title (see "Titles"
    below).
  - Names that are a whole `Text` on their own stay plain: rows, table
    cells, chart labels, TalkBack labels.
- **Guard test:** `copy only breaks lines between words`.
  - It runs every alert copy (8 codes × 2 feet × 8 sites) at widths
    260–400 px and scales 1.0, 1.3 and 1.88.
  - It checks that every line break falls on a word boundary of the plain
    text.
  - A control case (the per-letter version) proves the check can fail.
- **Joined phrases:**
  - site and region names;
  - "เท้าซ้าย/ขวา", "ตอนเดิน", "หรือไม่" (BACKLOG 46);
  - "ต่อเนื่อง", "น้ำหนัก", "จุดเดียว" (found on the emulator);
  - a no-break space before each "·" in the TEMP_DELTA sites line
    (BACKLOG 69) and between day and month in Home's date.
- **Visible copy is unchanged** (joiners are invisible). Tests compare
  plain text through `test/helpers/plain_text.dart`.
- **Side effect:** a line holding a joiner sits about 2 px lower in the
  goldens. U+2060 is not in Noto Sans Thai Looped, so a fallback font's
  line metrics count. Cosmetic. The Note 10 check looks at it in the
  Samsung font.
- **Display only, confirmed:**
  - `test/text/thai_break_test.dart` statically checks that `lib/storage`,
    `lib/capture`, `lib/ble`, `lib/device` and `lib/gait` never reference
    `thai_break.dart`, `alert_copy.dart`, `displayTh`, `keepTogether`,
    `wordJoiner` or U+2060. So the database, `alerts.csv`, exports and
    capture files never carry a joiner.
  - `git grep` agrees. Joined text is used only in `lib/rules/alert_copy.dart`
    (copy, composed at display time), `lib/notify/alert_notification_service.dart`
    (notification title and body), `lib/ui/screens/{alerts,home,my_feet}`
    and `lib/config/foot_layout.dart` (`displayTh` getters; `nameTh` and
    the layout test are unchanged).
  - Alert rows store codes, zones and numbers, not copy.
- **Reapplying in S10b:** see mobile/CLAUDE.md "Thai line breaks". Add the
  phrase to `thaiWords`, wrap it where the copy is composed, and add it to
  `thai_line_break_test.dart`.

### Titles (follow-up 2026-11-04, 3789261)

- **Cause of the user's finding:** `emu-alert-detail-pti.png` showed
  "ปลายเท้าซ้ายรับน้ำ / หนักมาก…". It was taken at 22:12 on 2 Nov, before
  537f591 (22:19) joined "น้ำหนัก". Retaken on 4885b9b: "ปลายเท้าซ้ายรับ /
  น้ำหนักมากต่อเนื่อง / นานเกินไป". The word-boundary guard could not have
  caught it: "น้ำ|หนัก" is two words to the dictionary.
- **Every title line break listed** (each alert code × foot × site, in
  `pageTitle`, `bodyStrong` and `button`, 260–400 px, scales 1.0/1.3/1.88).
  Splits inside a short word found and joined: "อุ่น / กว่า" (TEMP_DELTA),
  "ปลาย / เท้า" and "ส้น / เท้า" (region names, plain in titles until
  now), "เกิน / ไป" (PTI, LOAD_CONCENTRATION), "ค่อน / ข้าง"
  (PRESSURE_WATCH), "เชื่อม / ต่อ" (DEVICE_LOST), "เหลือ / น้อย"
  (BATTERY_LOW), "ด้าน / นอก"; in My feet, "เท้า / ซ้าย" in
  "ยังไม่ได้รับข้อมูลเท้าซ้าย".
- **Long names in titles:** joined whole they are wider than the line at
  1.88× (Flutter then breaks them by letter: "โคนนิ้วหัวแม่เ / ท้า",
  "แผ่นรองเท้ / า", found by the guard). `keepTogetherInTitle` joins their
  parts instead, so they break only at "โคน / นิ้วหัวแม่เท้า", "ขอบเท้า /
  ด้านนอก", "ส้นเท้า / ด้านนอก". "แผ่นรองเท้า" stays plain: "รองเท้า" is
  one word, so it can only break as "แผ่น / รองเท้า". A side stays a
  separate word ("ปลายเท้า / ซ้าย"): "ปลายเท้าซ้าย" joined is wider than
  260 px at 1.88×.
- **Guard extended** (`copy only breaks lines between words`):
  - every alert title in the alert detail (`pageTitle` 28), Alerts list
    (`bodyStrong` 18) and My feet banner (`button` 18, 216–340 px: the
    banner text is the screen less 144 dp, 216 on a 360 dp phone, 267 on
    the Note 10); Home's status titles (`statusTitle` 32) and the My feet
    banner titles, including the Temperature one for every site;
  - titles must also never break inside a short (≤ 3-word) `thaiWords`
    phrase, read word by word, longest first; a control (the PTI title
    without joiners) proves it catches "รับน้ำ / หนัก".
- **Same-alert body lines:** "อุ่นกว่า" and "เกินไป" are joined in the
  TEMP_DELTA detail and the PTI / LOAD_CONCENTRATION Home lines too, as
  "น้ำหนัก" is. Other body copy is unchanged (S10b).
- Visible copy unchanged (joiners are invisible). Goldens: 25 changed at
  the title step, 13 at the body step. Reviewed side by side: the fixed
  breaks (e.g. TEMP_DELTA at 200 %: "เท้าขวา / อุ่นกว่า / เท้าซ้าย") and
  the ~2 px joiner shift; nothing else.

## Checks

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | **1107 passed** (166 goldens), again at 3789261 |
| Goldens reviewed | Changed: alert details (all), alerts list, Home (100 / 130xl / 200), My feet watch / temp_rest. Text and line breaks reviewed side by side against main; the only change besides the fixed breaks is the ~2 px line shift above. New: 22 goldens at 130 % |
| `thresholds.json` copies | Byte-identical (`cmp`) |
| FLUTTER-PLAN §6 rule 12 | `quietNotifyMin` read from thresholds; no literal |
| Rule 13 | Every alert still carries plain-Thai advice (copy unchanged in content) |
| Rules 5, 16 | Not touched by this diff |
| Release resources | `check_release_resources.sh`: `ic_stat_foot_check`, `ic_stat_foot_alert` ok |
| aapt badging (release) | label `SmartInsole`, versionCode 6, adaptive icon |
| Model slot | `assets/models/` holds only README.md |
| Emulator, quiet window (`MOCK=watch`, sound on) | `pressurePeak #5 (sound)`, then `pressurePti #9 (silent)`, `#10 (silent)` for the same foot within 2 min. Tray shows all three |
| Emulator, notification | Header "SmartInsole", colour `0xff155e75`; status-bar icons are footprints; launcher icon is the new footprints icon. The shade's round header icon still showed the Flutter logo: SystemUI's cached icon from the earlier install (the debug APK's `application-icon-*` all resolve to `mipmap-anydpi-v26/ic_launcher.xml`). The Note 10 check confirms it on a clean install-over |
| Emulator, screens | Home at "ใหญ่", Alerts list, PTI alert detail, My feet Pressure: site names whole, no split words in the joined phrases (screenshots below). Alerts list and PTI detail retaken at 3789261 (2026-11-04): title "ปลายเท้าซ้ายรับ / น้ำหนักมากต่อเนื่อง / นานเกินไป" |

Note on the emulator: its saved Settings had **sound off** from an earlier
session, so the first run's notifications were all silent. That is
correct behaviour. Turned on for the check.

Screenshots (`docs/reports/041-flutter-wrapup/`): `emu-home-large.png`,
`emu-alerts-list.png`, `emu-alert-detail-pti.png`,
`emu-my-feet-pressure.png`, `emu-notification-shade.png`,
`emu-launcher-icon.png`. The TEMP_DELTA detail with several sites is
covered by goldens `alert_detail_temp_delta_100/130/200` (Flutter Driver
taps timed out on this build, so it was not opened on the emulator).

## Release APK

| Build | Version | SHA-256 | Size | Built from |
|---|---|---|---|---|
| **+6 (for the smoke check and SR)** | 1.0.0+6 (versionCode 6) | `5d9e3b134f90751eb48254c28996acbea45174beeb874213b28b15ac6e4bcfbc` | 93,804,889 B | 3789261, 2026-11-04 |

- Three earlier +6 builds were never installed anywhere and are replaced
  by the build above: from f1736bf (`5a5bb361…3e4f`), before the emulator
  copy fixes; from e53ddde (`d8fb5ed2…4259`), before the spec-review
  fixes; and from 4885b9b (`76b18d3f…3552`), before the title follow-up.
- aapt badging: label `SmartInsole`, versionCode 6, versionName 1.0.0.
- `tool/check_release_resources.sh` passed (`ic_stat_foot_check`,
  `ic_stat_foot_alert`). `assets/models/` holds only its README.
- **Not installed yet:** waiting on the smoke check.

## Spec review

`spec-reviewer` on `git diff main...HEAD` at e53ddde (DESIGN-SPEC §6, §11.9,
decisions 22 and 32, Appendix A; DATA-CONTRACT §8; FLUTTER-PLAN §6 rules 5,
12, 13, 16). Findings as returned, with resolution:

| # | Severity | File:line | Spec | Mismatch | Resolution |
|---|---|---|---|---|---|
| 1 | minor | `mobile/lib/ui/screens/alerts/alert_view.dart:234`, `:251`, `:297` | BACKLOG 60 S10 resolution ("names standing alone (rows, table cells, chart labels, TalkBack labels), stay plain"); mobile/CLAUDE.md "Thai line breaks" | `names` / `zone` now come from `displayTh` (joined) and feed TalkBack labels: the TEMP_DELTA map label (`joinTh(names)`) and the pressure map's `triggerLabel` carry U+2060. Likely inaudible, but against the session's own rule | **Fixed** in 4885b9b: both labels use `nameTh`; the visible captions keep the joined names |
| 2 | minor | `alert_view.dart:496`; `my_feet_copy.dart:483`, `:491` | DESIGN-SPEC decision 22 ("a no-break space before "·" in lists") | Three lists with joined site names still `.join(' · ')`, so a line can start with "·" | **Fixed** in 4885b9b: `join('$nbsp· ')`; test expectations updated |
| 3 | minor | `mobile/lib/notify/alert_notification_service.dart:139` | DESIGN-SPEC §11.9 "of the last one that **sounded**" | `claimSound` records the alert as sounded before `show()`; if posting throws, a later alert within 2 min for that foot is silent though nothing sounded | **Fixed** in 4885b9b: `NotificationQuietWindow.release` undoes the claim on failure; test "a failed post does not silence the next alert"; §11.9 says so. Alerts raised together with the failed one are already judged (decided before any await, by design) |

Spec gaps the reviewer noted (no code change):
- DESIGN-SPEC does not say whether TalkBack labels may hold U+2060. The
  labels the app writes itself are plain; mobile/CLAUDE.md states the
  rule. Correction (2026-11-04, seen in the emulator's accessibility
  tree): labels that merge the visible text, such as Home's status card
  and the Alerts list cards, do carry the joiners. U+2060 is a format
  character, so TalkBack is expected to skip it; not heard yet (Leftovers).
- The adaptive icon is API 26+ only; Android 7 keeps Flutter's PNG
  (Leftovers).
- What counts as "sounded" when the user mutes the sound channel in
  Android settings: the app cannot see that; the window still counts the
  post as sounded. Harmless (the user chose silence).

## Note 10 smoke check — **waiting on user**

Group A changed the phone (notifications, icon, name, text). **I ask
before you plug it in.** `adb install -r` only; no uninstall, no `pm
clear`.

1. Install 1.0.0+6 with `adb install -r`. The app opens with its data.
   The launcher shows "SmartInsole" and the footprints icon (a launcher
   refresh may be needed).
2. Both feet connect (auto-reconnect).
3. Press `t` on a board: one TEMP_DELTA alert is **heard**.
   - The notification header reads "SmartInsole" with the footprints
     small icon. No white blob, no Flutter logo.
   - Pull the shade down and look at the **round header icon** next to
     the app name too, not only the status bar. If it still shows the
     Flutter logo after a launcher refresh, report it (the emulator kept
     SystemUI's cached icon from the earlier install).
   - A second alert for the same foot within 2 min (e.g. `p` right after)
     is in the tray, **silent**.
4. Open the TEMP_DELTA detail and check the Samsung font: site names whole,
   no boxes or missing glyphs, the title not split inside a word ("อุ่น /
   กว่า"), and the sites line breaks only after "· ". Look at Home and My
   feet the same way.
5. Researcher › start a TEST- capture. Trial 00 starts and saves.

## Leftovers

- **Android 7 launcher icon:** legacy PNG mipmaps are still Flutter's (no
  image tools on the laptop). Android 8+ uses the adaptive icon. The Note
  10 runs Android 12. After study.
- **Other dictionary splits that read oddly** (e.g. "ท่า / เดิน" in a PTI
  step, "ใช้ / เวลา"). Left for S10b's copy review, which reapplies the
  helper.
- **Joiner line-height shift:** about 2 px per joined line (fallback font
  metrics). Cosmetic; check on the Note 10.
- **TalkBack with joined text:** merged labels (Home status card, Alerts
  list cards) hold U+2060. Expected silent, not listened to. After study
  unless SR turns TalkBack on.
- **BACKLOG 54 tab-bar labels, 47, 50:** after study (no small safe fix;
  volunteers are 21–30, so large text is unlikely on study days).
- **Duplicate PTI notifications:** one PTI per zone, so two zones in the
  same region give two notifications with the same title (seen on the
  emulator, S9 behaviour). With BACKLOG 76 the second is silent. Not
  changed; noted for after study.

## Decisions needed

None.

## Next

- **S10b (6–7 Nov):** expert text fixes (feedback due 5 Nov) + build
  1.0.0+7, before SR. Reapply the joiner helper to edited copy.
- **SR (8–11 Nov):** the SR checklist in `docs/SESSIONS.md`.
- **Study:** starts 12 Nov.

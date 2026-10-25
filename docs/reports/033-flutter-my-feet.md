# 033 — S6B part 2: My feet shell, Pressure and Temperature tabs

Branch `work/flutter-temp-alerts-part2` (from `main` at `f47cea2`, the
PR #28 merge) · 2026-10-25 · Session S6B part 2 (`docs/SESSIONS.md` §3)
Spec: DESIGN-SPEC §5, §8, §8.1, §8.2, §12, §13, §14 and Appendix A.
Plan approved 2026-10-25 with all defaults, plus the user's decisions on
the one-foot-missing pressure banner, the detail figures, the seed day
and the Be-careful banner copy.

**Status: waiting for the user's comparison of the Note 10 screenshots
with the boards.** Everything automated passes. I ran the phone steps
myself (section "Note 10 checkpoint"); the release build is installed.

## Summary

- **My feet shell (§8):**
  - title with "อัปเดตเมื่อสักครู่", or "ยังไม่มีข้อมูล" when no foot streams;
  - segmented control "แรงกด / อุณหภูมิ / การเดิน" with a sliding indicator, as a screen-reader tab list "เรื่องที่ดู";
  - panel cross-fade.
  - Gait stays a placeholder until S8A.
  - Home's "ดูเพิ่ม" and the alert actions still open the right sub-tab (`openMyFeet`).
- **Pressure (§8.1):**
  - banner from the engine's level-3 pressure rules, using the alert's own copy;
  - both feet at 108×241 (dashed outline when there's no data);
  - legend and top-3 zones;
  - details: a kPa table, then peak while walking (5 min), PTI (display only), single point, and thresholds from `thresholds.json`.
  - With one foot missing, the banner names it and offers the connect button.
- **Temperature (§8.2):**
  - banner: Close, Rest only while TEMP_DELTA holds, one foot missing, or no data;
  - two site cards with the foot icon;
  - today's chart from `temperature_readings`: alert band, dashed line at `deltaC`, connection gaps ("ขาดข้อมูล / ตั้งแต่ HH:mm", no line after an open gap), end dots, draw-in motion, a generated TalkBack summary;
  - a note with `consecutiveReadings`;
  - details with the source "(Lavery et al., 2004)" and the signal quality.
- **"ดูสิ่งที่ควรทำ"** opens the newest stored alert with the banner's code, foot and zone or site. It is hidden until that row exists.
- **Engine figures:** `AlertEngine.pressureFigures(side)` uses the engine's own walking gate and step detector, so the details show the same numbers the rules compare.
- **Debug "Seed sample day":**
  - only in a mock-preset run, which uses the in-memory database;
  - writes today's readings from 08:00, both feet every 30 s, with one period above ΔT and one right-foot gap, shaped by the preset to match FeetDTemp, FeetDTempRest and FeetDTempMissing.
- **Fix outside My feet:** Home's `StatusCard` asserted under reduce motion when its size changed (`AnimatedSize` with a zero duration finishes inside its own layout). My feet's reduce-motion test exposed it. It now skips `AnimatedSize` when motion is reduced.

## What changed

Commits on the branch, oldest first:

| Commit | What |
|---|---|
| `31fa722` | Engine: `PressureFigures`, `pressureFigures(side)`, `RulesView.top(codes)`, public `ranksAbove`; `RollingPeaks` read window (`asOfMs`), `walkingPeakWindowMs`. Rules tests for each figure |
| `e2b068c` | My feet shell, Pressure and Temperature tabs, `SummaryBanner`, `SegmentedTabs`, `TempDeltaChart`, chart model, view model, copy, seed day, Settings button |
| `4c49254` | Tests and goldens; chart: its own semantics node, x labels drop rather than overlap, the band label avoids gap lines, gap-label backdrop; header stacks above 1.3; StatusCard reduce-motion fix |
| `ff058b7` | Docs: DESIGN-SPEC §8.4 and Appendix A, the S9 My feet check, BACKLOG 47, `mobile/CLAUDE.md` |
| `4c6f1eb` | Spec-review fixes: the link matches foot and zone or site; the quality row is never "good" without data |
| (this commit) | This report and the emulator and phone screenshots |

New files:
- `lib/ui/screens/my_feet/` (`my_feet_model.dart`, `my_feet_copy.dart`, `temp_chart_model.dart`, `pressure_tab.dart`, `temperature_tab.dart`, `my_feet_widgets.dart`);
- `lib/ui/widgets/` (`summary_banner.dart`, `segmented_tabs.dart`, `temp_delta_chart.dart`);
- `lib/storage/sample_day.dart`.
- Tests: `test/my_feet/` and `test/storage/sample_day_test.dart`; goldens `test/goldens/my_feet_golden_test.dart`.

No schema change. No capture, export or BLE change. The web app, the firmware and `shared/thresholds.json` are untouched.

## Decisions and how they were applied

All are written into DESIGN-SPEC §8.4.

1. **Pressure, one foot missing (user):**
   - No-data banner "ยังไม่ได้รับข้อมูลเท้า{ข้าง}" / "ต้องเชื่อมต่อแผ่นรองเท้า{ข้าง}ก่อน" + "เชื่อมต่อแผ่นรองเท้า";
   - a level-3 rule on the connected foot wins;
   - the connected foot keeps its map, rows and numbers.
   - Draft copy, in Appendix A.
2. **Detail figures (user):**
   - Peak: the highest zone kPa while walking in the last 5 min.
   - PTI: the highest zone's mean per-step PTI over `ptiWindowMin`.
   - Single point: the highest per-step top-zone share in the last 5 min.
   - Each is "—" until the foot has one.
3. **Seed day follows the preset (user):**
   - `safe` and the others: a heel period above ΔT that has ended, and a right gap that ended;
   - `rest`: the forefoot above ΔT up to now, joining the live mock's 2.6 °C;
   - `oneFootMissing`: the right foot stops for good.
4. **Be-careful banner = alert copy (user):** the `watch` preset reads "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" (PTI), which is also Home's wording, not the board's PEAK text. I checked on the emulator that Home and My feet name the same rule: both moved from PEAK to PTI once PTI started to hold.
5. **Defaults (approved with the plan):**
   - per-tab banners;
   - the link is hidden until its row exists;
   - header text;
   - the kPa table from the 2 s peaks;
   - top-3 ranking;
   - the "ตั้งแต่" source;
   - site notes as Home;
   - chart pairing, line breaks, gaps, newest label only, Y 0–3.5, end dots;
   - TalkBack summary;
   - "ดีทั้ง 4 จุด";
   - citation format.
6. **Added during implementation:**
   - **Header stacking:** above 1.3 text scale the header stacks, as the two-column cards do.
   - **Chart at large text:** the middle time label drops (then the start one) rather than overlap.
   - **Band label:** "ระดับที่ควรระวัง" moves right when a gap line would cross it.
   - **Gap label:** sits on an 85 % white backdrop over any line (new token `TempChartColors.gapLabelBackdrop`).
   - **Link target:** matches the alert's foot and zone or site (spec-review gap 1).

## Independent review (spec vs implementation)

`spec-reviewer` on `git diff main...HEAD`. Its findings are copied as returned, with how each was resolved:

| # | Severity | File:line | Finding | Resolution |
|---|---|---|---|---|
| 1 | minor | `my_feet_copy.dart:377-381, 400-405` | The spec says to show "ดีทั้ง 4 จุด", or name each foot whose last reading was not `normal`. The code only names feet whose `quality` is set and not normal. A foot that streams but has no reading yet (`quality == null`), or a site with a null value, counts as good. So the row can say "ดีทั้ง 4 จุด" while the rows above show "—", which presents no data as a good result. | **Fixed** (`4c6f1eb`). Such a foot now reads "เท้า{ข้าง} ยังวัดไม่ได้". Unit test added; §8.4 and Appendix A updated. |
| 2 | minor | `temp_chart_model.dart:244, 269` | Appendix A's My feet row points to §8.4 for the chart summary strings. Two strings the code speaks are missing there: "กราฟความต่างของความอุ่นวันนี้ ยังไม่มีข้อมูล" and "{จุด}ยังไม่มีข้อมูล". | **Fixed**: both strings added to §8.4. |
| gap | — | `my_feet_widgets.dart` | The link opens the newest alert of the code. Repeat suppression is keyed by code + side + zone/site, so that alert can be about a different foot, zone or site. | **Fixed**: the link matches code, foot and zone or site (the suppression key). Fields tested. |
| gap | — | §8.4 | The Close banner can show while a site card says "{ข้าง}อุ่นกว่า" (one reading above, TEMP_DELTA not yet holding). | **Documented** in §8.4. It lasts one reading (30 s). The banner follows rule 6, and the card follows Home's note. |
| gap | — | `temp_chart_model.dart:197` | A gap also opens for a connected foot that has stored nothing for more than 3 × `notifyPeriod`. | **Documented** in §8.4 (intended: a silent board is a gap even before staleness flips). |
| gap | — | §8.4 | "ทั้งสองข้าง" is also used for zones at "น้อย". | **Documented** ("น้อย" included). |
| gap | — | `pressure_tab.dart:163` | "Level radius × 0.8": SVG units or px? | **Kept** px, as the legend dots. Matches the boards at 100 %. |

The reviewer also confirmed:
- the decisions listed above;
- no threshold literals;
- rule 4 at every two-foot value;
- rule 5;
- reduce motion for every animation;
- the TalkBack roles;
- that the seed day can't reach the phone's file.

## Verify

| Check | Result |
|---|---|
| `flutter analyze` | Pass, no issues |
| `dart format lib test test_driver` | Clean |
| `flutter test` | **Pass, 618** (548 on `main`: rules figures, chart model, copy, sample day, My feet widget tests and 16 goldens) |
| Goldens | 16 new: `my_feet_{safe, orange_dot, watch, no_data, one_foot, temp, temp_rest, temp_missing}_{100,200}`. 2 updated: `my_feet` (the old placeholder) and `settings_mock` (new button). Home goldens are unchanged by the StatusCard fix. I reviewed every image. |
| `pio test -e native` (simulator) | Pass, 40/40 |
| `load_capture.py --selftest` | Pass |
| Emulator + Dart MCP, every preset with the seed day | Pass. Screenshots in `033-flutter-my-feet/emulator/`; no runtime errors or overflows in any run log |
| Rule 2 (read-time) | The chart's gaps and end come from stored rows and the snapshot's minute, not a timer |
| Rule 4 (two-foot) | ΔT, site cards and chart points are "—" or absent unless both feet are usable; checked in the model and at the render sites (tests `rule 4: …`) |
| Rule 5 (no data ≠ safe) | No-data banners and dots use `noData`; the quality row is never "ดี" without data (test) |
| Rule 10 (50 Hz / 10 Hz) | The 2 s peaks come from `batches`; the view is rebuilt from the 10 Hz snapshot and rounded to what is visible |
| Rule 12 (thresholds) | `deltaC`, `consecutiveReadings`, kPa levels, PTI and concentration come from `thresholds.json`; display windows are named constants outside `lib/rules` |
| Rule 13 (advice) | The Be-careful and Rest banners link to the alert detail and its advice |
| Rule 16 (reduce motion) | Indicator, label fade, panel fade and chart draw-in are instant (widget test `reduce motion: the chart is drawn at once`) |
| Draw-in | Runs once per tab entry. A minute of 10 Hz snapshots and two new readings never restart it; reopening the bottom-bar tab does (widget test) |

### Emulator screenshots (`docs/reports/033-flutter-my-feet/emulator/`)

| Preset | Files | Board | Notes |
|---|---|---|---|
| `safe` | `safe-pressure*.png`, `safe-temperature*.png` | FeetD, FeetDTemp | Safe banners; heel period above ΔT ended; right gap 11:25 closed |
| `safeOrangeDot` | `safeOrangeDot-*.png` | — | Level 2: Safe banner, orange dot, "ปานกลาง" row |
| `watch` | `watch-pressure*.png`, `watch-pressure-details*.png` | FeetDPressureWatch | Be careful with the PTI copy (decision 4); "มาก" row with warning icon; numbers open |
| `noData` | `noData-*.png` | FeetDNoData | Dashed outlines, no zone list, no details; Temperature "—" |
| `oneFootMissing` | `oneFootMissing-*.png` | FeetDTempMissing | Pressure banner names the right foot; "เทียบความอุ่นไม่ได้ / เท้าขวาหลุดการเชื่อมต่อตั้งแต่ 11:56"; open gap, no line after it |
| `rest` | `rest-temperature*.png`, `rest-temperature-details*.png`, `rest-banner-link.png` | FeetDTempRest | Rest banner; forefoot card in the Rest colour; red end dot; "หน้าเท้า 3 ครั้ง (เกณฑ์ 2 ครั้ง)"; the link opens the TEMP_DELTA detail |

## Note 10 checkpoint (run 2026-10-25, 14:10–14:24)

No ESP32 needed. Samsung SM-N975F `RF8M83P4STZ`.

What I did:
1. **Before:** font scale 1.3; release build of 24 Oct installed (`pkgFlags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]`).
2. **Font scale set to 1.0.**
3. **Debug mock builds**, one per preset (`--dart-define=MOCK=<preset>`), each installed with `adb install -r` only. The mock runs on the in-memory database, so the phone's stored data and capture folders were not touched.
4. **For each preset:** Settings › "Seed sample day (debug)", back, My feet › แรงกด and › อุณหภูมิ, two screens each. For `rest` I also waited a minute for Rest, opened "ดูสิ่งที่ควรทำ", and opened the Temperature numbers.
5. **Font scale restored to 1.3** (checked).
6. **Release build** (`flutter build apk --release`, 64.6 MB) installed with `adb install -r` at 14:23:59. `pkgFlags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]` (no DEBUGGABLE). It starts in real BLE mode on the no-data Home (`phone/release-home.png`, at 1.3).

One interruption: Samsung's USB file-access popup came up during the `rest` install. I closed it with Back (no access granted) and went on.

Screenshots in `033-flutter-my-feet/phone/` (1440×3040):

| # | Board | Files | What I saw | Result |
|---|---|---|---|---|
| 1 | FeetD | `safe-pressure*.png` | Safe banner, both maps grey, top 3 "ทั้งสองข้าง · น้อย" | **waiting on user** |
| 2 | — (level 2) | `safeOrangeDot-pressure*.png` | Safe banner, left meta1 orange, "โคนนิ้วหัวแม่เท้า · เท้าซ้าย · ปานกลาง" first | **waiting on user** |
| 3 | FeetDPressureWatch | `watch-pressure*.png` | Be careful, PTI copy (decision 4), "ดูสิ่งที่ควรทำ"; red and orange dots | **waiting on user** |
| 4 | FeetDNoData | `noData-*.png` | "ยังไม่มีข้อมูล" header, No-data banner + button, dashed feet; Temperature "—", "ต้องเชื่อมต่อทั้งสองข้าง". The chart shows the seeded morning because I seeded it; with no stored readings it reads "ยังไม่มีข้อมูลวันนี้" (widget test) | **waiting on user** |
| 5 | FeetDTemp | `safe-temperature*.png` | Close banner, 0.3° / 0.0°, chart: heel period above the band ended, gap "ตั้งแต่ 11:50" closed, end dots | **waiting on user** |
| 6 | FeetDTempRest | `rest-temperature*.png`, `rest-temperature-late.png`, `rest-temperature-details.png` | First Close with "ขวาอุ่นกว่า" on the forefoot card (one reading, §8.4), then Rest "หน้าเท้าขวาอุ่นกว่าซ้าย 2.6 องศา" within about 60 s, red 2.6° card and end dot; numbers "หน้าเท้า 5 ครั้ง (เกณฑ์ 2 ครั้ง)", "(Lavery et al., 2004)", "ดีทั้ง 4 จุด" | **waiting on user** |
| 7 | — (link) | `rest-banner-link.png` | "ดูสิ่งที่ควรทำ" opened the TEMP_DELTA detail, right forefoot | **waiting on user** |
| 8 | FeetDTempMissing | `oneFootMissing-temperature*.png` | "เทียบความอุ่นไม่ได้ / เท้าขวาหลุดการเชื่อมต่อตั้งแต่ 12:24", cards "—", open gap with no line after it | **waiting on user** |
| 9 | — (pressure, one foot) | `oneFootMissing-pressure*.png` | "ยังไม่ได้รับข้อมูลเท้าขวา" + button, left map and rows, right dashed | **waiting on user** |

No layout overflow, clipped text or wrong colour seen at 100 %. Phone and emulator agree.

**Please compare 1–9 with the boards** and tell me what differs.

## Leftovers and notes for the next sessions

- **BACKLOG 47 (new, S10):** at 200 % text the sub-tab labels wrap inside words. The goldens show it.
- **Pressure banner wording:** the board's Be-careful text is PEAK wording, while the `watch` mock fires PTI too. By decision 4 the banner shows whichever rule ranks first. S9 checks this on real boards.
- **TEMP_DELTA on the emulator took longer than 60 s once.** It was the first `rest` run after a live preset switch: still Safe after about 2 min, Rest by 18 min, cause not found. A clean `rest` launch reached Rest in about 60 s, as the tests do. Watch this in the S9 My feet check (added to SESSIONS §3 S9).
- **Thai breaks in the test renderer:** the chart note breaks inside "ติดกัน" in the goldens, but not on the emulator (BACKLOG 46/47).
- **S8A:** the Gait tab replaces `PlaceholderBody(key: my-feet-target-gait)`. `MyFeetBanner` and `TwoColumns` are ready for its states.

## Decisions needed

None blocking. Please compare the Note 10 screenshots with the boards (checklist above).

## Next session

**S8A** (Gait tab) and **S8B** (Connection, Settings), per the SESSIONS schedule for Sun 25 Oct.

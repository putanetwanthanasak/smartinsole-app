# 034 — S8A: Gait tab, GaitClassifier and the Model A slot, simulator walk

Branch `work/flutter-gait` (from `main` at `a0ead89`) · 2026-10-25 ·
Session S8A (`docs/SESSIONS.md` §3)
Spec: DESIGN-SPEC §8.3, §12, §13, §14 and Appendix A; DATA-CONTRACT §7,
§8.2, §8.3.1, §8.3.2. Plan approved 2026-10-25, with the user's
decisions on the TFLite package, the dev-only dummy model, the gait-note
source and PTI asymmetry. The user also added two items: the drop-in
release proof on the Note 10, and an SR confusion table for the
rule-based classes.

**Status: accepted by the user on 2026-10-25.** The user compared the
Note 10 screenshots with FeetDGait, FeetDGaitToe and FeetDGaitIdle and
found they match. Everything automated passes. The phone check found one
simulator defect (rules read the normal walk as antalgic), fixed in
`2e2a326`. The user's four decisions on the review gaps are applied
(`e94d55c`).

## Summary

- **Gait tab (§8.3), replacing the placeholder:**
  - "ตอนนี้" (กำลังเดิน / ยืนหรือนั่งอยู่ / —) and "ก้าววันนี้";
  - the estimate card with the "ค่าประมาณ ไม่ใช่การวินิจฉัย" chip, the class
    and its description, 3 confidence segments (model only), the
    rule-based line, and the not-walking state with "ผลล่าสุด";
  - the balance card, with the ASYMMETRY_PEAK warning styled as on Home;
  - details: PAI, PTI asymmetry, confidence, source, window, class
    probabilities and CoP.
  - New widgets: `estimate_chip`, `confidence_segments`, `balance_bar`
    and `cop_foot`.
- **GaitClassifier (`mobile/lib/gait/`):**
  - A rule-based classifier (contract §7.5, provisional `gait.*` keys).
    It never says `rotated_foot`.
  - A TFLite classifier: `tflite_flutter` 0.12.1 (Apache-2.0) in its own
    long-lived isolate.
  - Input `[1,100,24]` per `shared/model_input.json`, z-scored with the
    model's `normalization.json`. Outputs are found by shape.
  - A 1 s stride over a 2 s window, in sample time.
  - The model is used when it is ready and its confidence is at or above
    `minConfidence`; otherwise the rules are used, with the reason.
- **The model slot:**
  - `mobile/assets/models/` holds only a README. Release builds use the
    rules ("โมเดล AI ยังไม่พร้อม").
  - The untrained dummy (`tools/model/make_dummy_model.py`) lives in
    `assets/models_dummy/`. It loads only in debug or profile builds run
    with `--dart-define=GAIT_MODEL=dummy`.
  - After data collection (late Nov), the real model needs only the two
    files in `assets/models/`. Proved on the Note 10 with a release build
    (item 4 below).
- **The gait-note hook** now receives real estimates: only fresh Model A
  results with confidence ≥ `minConfidence`. Rule-based results add no
  note. Nothing in the gait path can change a level (rule 11, tested).
- **"ก้าววันนี้":** both feet's walking steps from the engine's step
  detector. Stored in `daily_summary.steps` and carried over a restart.
- **Simulator (BACKLOG 42):** the normal walk now keeps the walking gate
  on through the whole stride. Lowest window / mean of the contract
  statistic: left 0.167 / 0.335 g, right 0.174 / 0.345 g (the lowest was
  0.069 / 0.071 g before). `t` / `p` / `n` still pass.
- **BLE debug "Gait model" card:** slot state, inference timing (last,
  median, max) and the `check.json` result. This is where the Note 10
  timing is read.

## What changed

| Commit | What |
|---|---|
| `85ea4a2` | Spike: `tflite_flutter` 0.12.1; JVM 11 fix in `android/build.gradle.kts`; asset slot; `tools/model/make_dummy_model.py` and its three outputs |
| `463d0cc` | `lib/gait/` core: classes, rules, model spec and window, model classifier, own-isolate TFLite runner, `demo-toe` runner, estimator, step counter, CoP, PTI asymmetry, providers. Engine `steps` stream, `walkingNow`, `latestPaiPct`. `GaitEstimateHook`. New `thresholds.json` keys. Tests in `test/gait/` |
| `f94199d` | Gait tab UI, copy, view model and widgets; mock presets `standing` and `toeWalk`; widget tests; 14 goldens |
| `86e410a` | BLE debug `_GaitModelCard`; `ble_debug_permission` golden updated |
| `a623706` | Simulator: `kWalkMotionScale` 3.0; `p` no longer scales the motion again; native tests use the contract statistic |
| `23b296e` | `model_input.json` added to `pubspec.yaml` assets (found on the emulator); DESIGN-SPEC §8.5, §14, Appendix A |
| `ab5d426`, `4d6026f`, `4cbcd6f` | DATA-CONTRACT §8 S8A addendum; SESSIONS (SR gait table, S8A result); BACKLOG 41, 42, 48–50; `mobile/CLAUDE.md`; `shared/README.md`; emulator screenshots |
| `73e6ca1`, `9324a4c` | Spec-review fix: the rules take over when a loaded model gives no answer; docs describe "walking" as the code does; format |
| `b268609` | This report (first version) |
| `e94d55c` | User decisions: no "ผลล่าสุด" in the no-data card; PAI detail by activity; `normalization.json` `version` checked against `model_input.json`; "December" → "after data collection (late Nov)" |
| `2e2a326` | Simulator: midfoot load so each stance is one step (Note 10 found the rules reading the normal walk as antalgic); native test |
| (this commit) | Report: Note 10 results, screenshots and serial logs |

## Decisions and how they were applied

1. **TFLite package: `tflite_flutter` 0.12.1** (Apache-2.0, tensorflow.org).
   - It builds with Flutter 3.47.7 / Dart 3.13.5 / AGP 9.1, after setting
     the plugin's Kotlin JVM target to 11 from the app's
     `android/build.gradle.kts`.
   - LiteRT's `.so` LOAD segments are 16 KB-aligned, and `zipalign -P 16`
     passes.
   - `IsolateInterpreter` crashed in the spike (SIGSEGV in
     `TfLiteTensorNumDims`): it calls `allocateTensors` on every run, and
     it silently skips a run when busy. `tflite_classifier.dart`
     therefore owns one interpreter in its own long-lived isolate.
2. **The dummy is dev-only.** `gaitModelChoiceFor` returns the release
   slot whenever `kReleaseMode` is set, so the define cannot reach a
   release build. The dummy files are still bundled in release (266 KB;
   BACKLOG 48).
3. **The gait note uses model results only.** `modelEstimateFor` gives a
   result only if it is from the model, fresh (within window + stride of
   sample time) and at or above `minConfidence`.
4. **PTI asymmetry is display only.**
   - The PAI formula on each foot's mean whole-foot PTI per walking step,
     over the last 5 minutes.
   - The detail reads "{n}% (ค่าอ้างอิง 20% · ยังไม่ใช้แจ้งเตือน)".
   - It is defined in the DATA-CONTRACT §8 S8A addendum.
5. **User addition: SR confusion table.** Added to SESSIONS SR. For each
   of the 5 gait trials, record the class shown against the instructed
   gait, then tune `gait.*` before 2026-11-10 (BACKLOG 49).
6. **User addition: drop-in proof.** Planned as Note 10 item 4 below.

The defaults applied are listed in DESIGN-SPEC §8.5. Drafts not on the
boards are in Appendix A:
- descriptions for เดินกะเผลก, เดินลงส้นเท้า and เดินบิดปลายเท้า;
- the low-confidence line and its detail;
- the no-data texts;
- the PTI asymmetry detail.

## Independent review (spec vs implementation)

The spec-reviewer agent ran on `git diff main...HEAD`.

- **Major, fixed (`73e6ca1`):** with a model loaded, a stride with no
  gap-free window, or a failed inference, showed "ยังไม่มีผลตอนนี้"
  instead of the rules' class. Contract §7.5 says the rules take over
  whenever no confident model result exists.
  - Both cases now show the rules, with "ยังไม่พร้อม".
  - A stride counter drops a model answer for an older stride, so a late
    result can't replace a newer one or come back after walking stops.
  - A new test covers a failing runner and a 320 ms packet loss.
- **Minor, docs fixed:** DESIGN-SPEC §8.5 and the contract addendum said
  "walking gate". The code (as in the approved plan) uses the engine's
  `walkingRecently`: a walking step ended within `steps.maxStanceMs`. The
  docs now say that. "กำลังเดิน" therefore starts at the first walking
  step and lasts up to 2.5 s after the last one.
- **Also fixed:** SESSIONS SR said rule-based classes feed the gait note.
  They don't.
- **Checks the reviewer passed:**
  - rule 11, rules 4/5 and rule 12;
  - both JSON copies are byte-identical;
  - release never loads the dummy;
  - gait-note source;
  - copy word for word;
  - simulator `t`/`p`/`n`;
  - research capture untouched.
- **Spec gaps it listed, and the user's decisions (applied in
  `e94d55c`):**
  1. "ผลล่าสุด" also showed in the no-data card. → Hidden: no data shows
     no data. `gaitViewOf` keeps the last result only while both feet are
     usable, which also hides the "ผลประเมินล่าสุด" detail row. Test added.
  2. The CoP's "เท้าซ้าย/ขวา เส้นทางของแรงกด" is a TalkBack label; the
     visible text is "ซ้าย"/"ขวา". → Kept as built.
  3. The PAI detail had no freshness limit. → The step-pair PAI shows
     only while walking (`walkingRecently`); otherwise the standing PAI
     with its standing label; "—" when a foot is not usable (rule 4).
     Test added.
  4. `normalization.json` `"version"` was not checked. → It must equal
     `model_input.json`'s `version`; a mismatch makes the slot "not
     ready", and BLE debug › "Gait model" shows the reason. Tests for the
     parse (version +1, null, `"1"`) and for the slot's reason.
- Appendix A drafts stay marked draft; they go to the medical expert with
  the alert copy (user).
- Model A is trained during November, after data collection; the docs no
  longer say "December".

## Verify

- `flutter analyze`: no issues. `flutter test`: **700 passed**, goldens
  included (696 before the user-decision tests).
- **Goldens:** 7 Gait states × 100 % and 200 % text in
  `mobile/test/goldens/screens/gait_*.png`:
  - walk_rules (FeetDGait), toe_model (FeetDGaitToe), idle (FeetDGaitIdle);
  - below_min, balance_warning, one_foot, no_data.
  - Reduce motion is covered by widget tests (bar, steps and segments are
    instant).
- **Channel order and normalisation:** a Dart test builds the window from
  `shared/capture_fixture` and matches `check.json`'s normalised window
  to 1e-6.
- **Fallback:** a test for each path: model missing, invalid shape or
  normalisation, below `minConfidence`, exactly at the boundary, no
  window, failed run.
- **Rule 11:** the same stored level and the same status with no model,
  a toe-walking model and a `rotated_foot` model.
  - BACKLOG 41: a `rotated_foot` result stores its class and 0.9
    confidence and adds no note.
- **No numeric literals:** the test now scans `lib/gait` too.
- **Simulator:** `pio test -e native` 41/41 (40 before the stance fix),
  `pio run` left and right both succeed. Normal-walk gate figures are in the Summary; a ×4 sweep
  gave a mean of 0.479 g.
- **Emulator (Dart MCP, sdk_gphone16k, 1080×2400 at 420 dpi = 411 dp wide):** screenshots in
  `docs/reports/034-flutter-gait/`:
  - `emulator-gait-dummy-model.png`: `MOCK=safe` with the dummy model.
    Rules line "ยังไม่มั่นใจพอ", because the untrained dummy answers at
    about 0.28.
  - `emulator-ble-debug-gait-model.png`: "ready (assets/models_dummy)",
    check **PASSED** (window 0, probs 3e-8, embedding 1.3e-7). Inference
    on the emulator: median 1.59 ms, max 52 ms over 42 runs.
  - `emulator-gait-demo-toe.png`: `MOCK=toeWalk GAIT_MODEL=demo-toe`,
    "เดินเขย่งปลายเท้า", 2 segments "ปานกลาง".
  - `emulator-gait-standing.png`: `MOCK=standing`, "ยืนหรือนั่งอยู่",
    "ยังไม่มีผลตอนนี้", 47 : 53.
  - **Found and fixed:** the app could not start on a device, because
    `assets/config/model_input.json` was not in `pubspec.yaml` (tests
    read it from disk). A test now checks the entry.

## Note 10 checkpoint — accepted by the user (2026-10-25)

I ran everything over adb on the Note 10 (SM-N975F), using `adb install -r`
only. Both boards were reflashed with the S8A simulator. Serial logs were
started before the phone connected and are saved in
`docs/reports/034-flutter-gait/serial/`. The user compared the screenshots
with the boards and accepted all five items. Font scale was set to 1.0 for the
mock screenshots and then **restored to 1.3** (I read the setting back).
Screenshots are in `docs/reports/034-flutter-gait/phone/`. The comparison
and acceptance are the user's.

1. **Timing.** Profile build with `GAIT_MODEL=dummy` (108 MB APK), on real
   BLE.
   - BLE debug › "Gait model": "ready (assets/models_dummy)".
   - Check **PASSED**: window 0.0e+0, probs 3.0e-8, embedding 1.2e-7.
   - Inference: last 2.76, **median 3.14 ms, max 20.85 ms** over 111 runs.
     Both are well under the 100 ms limit (contract §7.5).
   - Timing check: L/R lost 0, step 19.75–20.25 ms.
   - Screenshot: `phone-ble-debug-gait-model-dummy.png`.
2. **Real BLE, about 2 minutes** (same profile build; the dummy is below
   `minConfidence`, so the rules were shown).
   - **Found:** before the fix, the normal walk read **antalgic**
     ("now: antalgic · rules · lowConfidence").
     - Cause: between heel and forefoot, the summed kPa dipped below
       `steps.contactKpa`. Each stance therefore split into a ~150 ms blip
       and a ~420 ms step.
     - The boards' different TARE offsets (left 18–19, right 12) made the
       mean stances 420 ms on the left and 491 ms on the right. That is a
       stance PAI of 15.6 %, above the 15 % rule.
     - Fixed in the simulator only (`2e2a326`): the midfoot load keeps
       each stance one step. The new native test
       `test_normal_walk_one_step_per_stance` checks offsets 12 and 19:
       600 vs 600 ms, 0.0 %. Both boards were reflashed.
     - The app's step detector has no hysteresis. The user raised this
       to a pre-SR item: BACKLOG 51, scheduled as S9's first item. SR's
       manual step count stays.
   - After the fix:
     - "ตอนนี้ กำลังเดิน", **เดินปกติ** with "ยังไม่มั่นใจพอ".
     - Steps went from 628 at 19:32:46 to 865 at 19:34:56: **109.4 a
       minute** (expected 109.1 for two feet at an 1100 ms stride).
     - Screenshots: `phone-real-ble-steps-t0.png` and `-t1.png`.
   - **`p` on the left board** (19:35:12):
     - Two alerts were raised (badge 2), and steps kept counting (942).
     - The rules then read **เดินเขย่งปลายเท้า**. This is expected from
       the scenario, not a defect: the 250 kPa meta1 plateau drops the
       heel's share of PTI below `gait.toeHeelPtiPct` (10 %).
     - Screenshot: `phone-real-ble-scenario-p.png`.
     - The two test alerts are untagged rows in the phone's database. SR
       clears test data.
   - **`n`** (19:35:49): back to เดินปกติ, 999 steps. Screenshot:
     `phone-real-ble-scenario-n.png`.
3. **Mock screenshots at 100 % text, against the boards** (debug builds,
   in-memory database):
   - **FeetDGait**, `MOCK=safe`, rules:
     - `phone-100-feetdgait-walk-rules.png`: กำลังเดิน, steps, เดินปกติ,
       "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม";
     - `phone-100-feetdgait-walk-rules-balance.png`: the balance card.
   - **FeetDGaitIdle**, `MOCK=standing`, switched live from walking:
     - `phone-100-feetdgaitidle-standing.png`: ยืนหรือนั่งอยู่,
       "ยังไม่มีผลตอนนี้", "ผลล่าสุด 19:38 · เดินปกติ", and the
       standing balance 47 : 53;
     - `phone-100-feetdgaitidle-details.png`: details with "ผลประเมินล่าสุด
       19:38 · เดินปกติ (กฎพื้นฐาน)" and "ความไม่สมดุลของแรงกดขณะยืน 13%".
       This is user decision 3 on a real device.
   - **FeetDGaitToe**, `MOCK=toeWalk GAIT_MODEL=demo-toe`:
     - `phone-100-feetdgaittoe-model.png`: เดินเขย่งปลายเท้า, 2 segments,
       "ปานกลาง";
     - `phone-100-feetdgaittoe-details.png`: details with PAI 0 %, PTI
       asymmetry 0 % (ค่าอ้างอิง 20%), confidence 78 % (ใช้ผลเมื่อ 60%
       ขึ้นไป), "โมเดล AI (Model A)" and "ช่วงละ 2 วินาที ประเมินทุก 1
       วินาที";
     - `phone-100-feetdgaittoe-probabilities-cop.png`: the probabilities
       (6 / 4 / **78** / 7 / 5 %) and both CoP feet.
   - At 411 dp, "ยืนหรือนั่งอยู่" fits on one line (BACKLOG 50 is about
     390 dp).
4. **Drop-in proof (user addition): passed.**
   - I copied only `model_a.tflite` and `normalization.json` from
     `assets/models_dummy/` into `mobile/assets/models/`. I did not copy
     `check.json`, did not commit the copy, and used no define.
   - `flutter build apk --release` built an 85.6 MB APK, installed with
     `-r`. Real BLE, both boards.
   - BLE debug › "Gait model":
     - **"ready (assets/models)"**;
     - inference **median 3.27 ms, max 11.30 ms** (65 runs);
     - "check: no check.json", as a real model will show;
     - "now: normal · rules · lowConfidence": the model ran, and the
       untrained dummy fell below `minConfidence`.
   - Screenshot: `phone-release-dropin-gait-model.png`.
   - Then I removed the two copies. `mobile/assets/models/` holds only
     its README, and `git status` showed nothing under `mobile/assets/`.
5. **Final release build installed** (empty slot, 85.4 MB, `-r`):
   - BLE debug: "no model in assets/models (rules)", inference "—",
     "now: normal · rules · noModel";
   - Gait tab: กำลังเดิน, 1,374 steps, เดินปกติ with "ประเมินด้วยกฎพื้นฐาน
     เพราะโมเดล AI ยังไม่พร้อม";
   - screenshots: `phone-release-final-gait-model-empty.png` and
     `phone-release-final-gait-tab.png`.
   - The phone keeps the earlier study data. Nothing was uninstalled or
     cleared.

## Leftovers and notes for the next sessions

- **BACKLOG 48 (S9):** the release APK grew from 64.6 to 84.6 MB.
  Consider per-ABI APKs or an app bundle.
- **BACKLOG 49 (SR):** the rule-based gait thresholds are provisional.
  Mocks: `watch` reads antalgic, which is correct for its 1200 / 960 ms
  stances.
- **BACKLOG 50 (S10):** at 390 dp, "ยืนหรือนั่งอยู่" wraps in its
  half-width card. It fits at 411 dp.
- **BACKLOG 41:** no in-/out-toeing direction yet; no note for
  `rotated_foot`.
- Not on the boards, applied as defaults (§8.5):
  - the no-data estimate card (`bluetooth_off` icon and connect button);
  - CoP shown while walking;
  - the "ผลประเมินล่าสุด" row has no suffix for a model result;
  - "— (ต้องเชื่อมต่อทั้งสองข้าง)" for two-foot rows.

## Decisions needed

None. S8A was accepted on 2026-10-25.

**Follow-up (user decision 2026-10-25), BACKLOG 51, S9's first item, before
SR:**
- The app's `StepDetector` must not split one stance when the summed kPa
  dips briefly below `steps.contactKpa`.
- Fix: hysteresis, or merging stances separated by a short dip, with new
  provisional `steps` keys.
- Tests replay the pre-fix simulator walk at offsets 12 and 19 and expect
  one step per stance.
- The SR manual step count stays.

## Next session

S8B: Connection and Settings (`work/flutter-connect-settings`).

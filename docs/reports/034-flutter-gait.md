# 034 — S8A: Gait tab, GaitClassifier and the Model A slot, simulator walk

Branch `work/flutter-gait` (from `main` at `a0ead89`) · 2026-10-25 ·
Session S8A (`docs/SESSIONS.md` §3)
Spec: DESIGN-SPEC §8.3, §12, §13, §14 and Appendix A; DATA-CONTRACT §7,
§8.2, §8.3.1, §8.3.2. Plan approved 2026-10-25, with the user's
decisions on the TFLite package, the dev-only dummy model, the gait-note
source and PTI asymmetry. The user also added two items: the drop-in
release proof on the Note 10, and an SR confusion table for the
rule-based classes.

**Status: everything automated passes, and the emulator checks are done.
The ESP32 reflash and all Note 10 checks are waiting on the user**
(section "Note 10 checkpoint"). Neither board nor the phone was attached
during the session.

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
  - After data collection (late Nov), the real model needs only the two files in `assets/models/` (proof on the
    Note 10: waiting on user).
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
| (this commit) | This report |

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
- **Spec gaps it listed (left as is, for the user):**
  - "ผลล่าสุด" also shows in the no-data card.
  - The CoP's "เท้าซ้าย/ขวา เส้นทางของแรงกด" is a TalkBack label, and the
    visible text is "ซ้าย"/"ขวา".
  - The PAI detail has no freshness limit (it is the engine's last
    step-pair PAI).
  - `normalization.json` `"version"` is not checked.

## Verify

- `flutter analyze`: no issues. `flutter test`: **696 passed**, goldens
  included.
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
- **Simulator:** `pio test -e native` 40/40, `pio run` left and right
  both succeed. Normal-walk gate figures are in the Summary; a ×4 sweep
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

## Note 10 checkpoint — waiting on user

Run by me over adb when the phone is attached, using `adb install -r`
only. Font scale is set to 1.0 for screenshots and restored to 1.3
afterwards. The results are for the user to compare and accept.

1. **Timing:** profile build with `GAIT_MODEL=dummy`. In BLE debug ›
   "Gait model", the check should pass with inference median and max
   ≤ 100 ms (contract §7.5). — *waiting on user*
2. **Screenshots at 100 % text vs the boards:**
   - `MOCK=safe` (rules) vs FeetDGait;
   - `MOCK=toeWalk GAIT_MODEL=demo-toe` with details open vs FeetDGaitToe;
   - `MOCK=standing` vs FeetDGaitIdle.

   — *waiting on user*
3. **Real BLE with both boards reflashed** (S8A simulator; serial logs
   started before the phone connects), about 2 minutes:
   - "ตอนนี้ กำลังเดิน";
   - steps rise at about 109 a minute (two feet, 1100 ms stride);
   - "เดินปกติ" with the rules line;
   - `p` then `n` on serial still work.

   — *waiting on user*
4. **Drop-in proof (user addition):**
   - Release APK with the dummy's `model_a.tflite` and
     `normalization.json` copied into `mobile/assets/models/` (not
     committed, no define), installed with `adb install -r`.
   - BLE debug › "Gait model" should show "ready (assets/models)" and
     inference timing. There is no check line, because `check.json` is
     not copied, as with a real model.
   - Then remove the copy and rebuild. — *waiting on user*
5. **Final release build** (empty slot) installed with `adb install -r`.
   — *waiting on user*

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

- The four review spec gaps above: keep them as built, or change them?
- Accept the Appendix A drafts (or send them to the medical expert with
  the alert copy).

## Next session

S8B: Connection and Settings (`work/flutter-connect-settings`).

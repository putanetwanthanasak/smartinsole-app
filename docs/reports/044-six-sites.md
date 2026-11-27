# 044 — S11-1: six sites per foot, data path (DATA-CONTRACT v1.7)

**Status: done, waiting for review** (2026-11-27, branch `work/six-sites`).
The plan was approved on 2026-11-25. S11-2 (UI, docs and release 1.0.0+7,
report 045) comes after this is merged.

## 1. What changed

Each foot now has **6 sites**: the v1.6 indexes 0–5 with their meaning
unchanged:

| Index | Site |
|---|---|
| 0 | hallux |
| 1 | MTH1 |
| 2 | MTH2–3 |
| 3 | MTH5 |
| 4 | lateral midfoot |
| 5 | heel centre |

Each site has one Velostat pressure sensor and one NTC next to it. v1.6's
medial arch (6) and lateral heel (7) are no longer read. The insoles keep
their 8 pads, and the firmware reads 6.

- **Contract.** DATA-CONTRACT v1.7 changes these sections: §1, §2.2–2.3,
  §3.1, §3.2, §5.1, §5.3, §6, §7.1, §7.3, §8.2, §8.3, §8.3.1, the S8A
  addendum, Appendix B, **Appendix C** and the 1.7 history row.
  - Sensor packet: 200 bytes at N = 6. It needs MTU 203; the 4-sample
    fallback is 104 bytes and needs MTU 107.
  - Temperature v2 is generalized to `8 + 3 × count` bytes. The app
    requires count 6, so the packet is 26 bytes.
  - The calibration JSON lists exactly 6 channels.
  - Model A takes `[1, 100, 24]`.
  - Load concentration is computed over 6 zones, still at 40 %.
  - The heel is heel centre only.
  - The same numbers are in `docs/BLE-INTERFACE.md` and FLUTTER-PLAN §2/§5.
- **`shared/`.**
  - `sensor_layout.json` is now version 2: 6 sites, plus a `retired` list
    that keeps ids 6/7 as names only. The `arch` region is gone.
  - `model_input.json` is now version 3, with 24 channels. The names are
    the same as version 1, but the new version number means older
    `normalization.json` files are still refused.
  - Test vectors:
    - `temperature_v2.json` is now at 6 sites;
    - the v1.6 file is kept as `temperature_v2_8sites.json`, and every
      case in it is refused;
    - `sensor.json` (N = 6) is the study file again.
  - There is a new capture fixture, `capture_fixture/schema3/`.
    `schema1/` and `schema2/` stay frozen.
- **App (`mobile/lib`, 39 files).**
  - The counts come from `sensor_layout.json`: 6 FSR, 6 temperature sites,
    12 model channels per foot.
  - The parser is unchanged and still accepts any N; the app refuses
    N ≠ 6 at connect.
  - New temperature check order (§4).
  - Retired-site names for v1.6 data (§3).
  - Capture schema 3.
  - A stored baseline whose length is not 12 counts as "record again".
  - The rule-based classifier and gait note no longer include the arch,
    and the heel is site 5 only.
- **Firmware.**
  - Simulator: `left` and `right` are built at `FSR_COUNT=6`. An `fsr8`
    env replaces `left_fsr6`; it is a build check only, so v1.6's
    eight-channel walk still compiles.
  - FW-1 (`firmware/insole/`): `FSR_COUNT` and `kCalChannels` are 6, and
    the mux and `[raw]` loops run to `kFsrCount`. The mux map is still a
    placeholder (§6).
- **Laptop tools.**
  - `sim_check.py`: temperature offsets are computed from count, in the
    app's check order.
  - `compare.py`: takes the site count and ids from `sensor_layout.json`.
  - `cal_trial.py`: reads a `[raw]` line of any length.
  - `load_capture.py`: reads schemas 1, 2 and 3.
  - `preprocess.py`: FSR count from `model_input.json`; gait rows from
    schema 3 only.
  - `make_dummy_model.py`: regenerated a 24-channel dummy.

## 2. Verification

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` (goldens included) | **1129 passed** |
| Goldens | 71 regenerated and reviewed side by side with the old ones (§5) |
| `node shared/test_vectors/generate.mjs --check` | Up to date |
| `load_capture.py --selftest` | PASS: 96 checks, schemas 1, 2 and 3 plus a mixed session |
| `preprocess.py --selftest` / `--make-vectors` | PASS; a second run gives no diff |
| `sim_check.py --selftest` | 98 vector cases, PASS (it also refuses every v1.6 8-site vector) |
| Simulator `pio test -e native` | 42/42; `pio run -e left -e right -e fsr8` SUCCESS |
| FW-1 `pio test -e native` | 28/28; `pio run -e buildcheck` SUCCESS |
| `compare.py` on an old capture | A v1.6 board's run (SR-1, offline file) is judged against v1.7: 232-byte packets → `lengthMismatch`, 32-byte temperature → `tempCount`, as intended |
| Simulator boards reflashed (user OK, 2026-11-27) | **Left:** boot `side L, fsr_count 6`; live `sim_check --side L --duration 300`: 56/56 PASS, 1,875 packets of 200 bytes, 0 gaps, 6.250 Hz, temperature 26 bytes at 6 sites every 30 s, calibration N = 6 (381 bytes, long read), TARE/REBOOT/reconnects as before. **Right:** boot `side R, fsr_count 6`; the same run, 56/56 PASS, 1,875 packets, 0 gaps, 6.251 Hz |
| `spec-reviewer` on `git diff main...HEAD` | 1 blocker and 2 minor findings, all fixed (§7) |

The first left upload stopped mid-transfer ("Packet content transfer
stopped"); the retry verified. The right board had just been plugged in
and was found on USB port 5, not port 7 as on 2026-10-25. Before flashing,
each board's side was read from its own boot line. Its log showed the
right board was still on the v1.6 build (`side R, fsr_count 8`).

**The Note 10 cannot read the reflashed simulators until S11-2's
1.0.0+7.** The phone's current build expects 8 + 8, and refuses the
boards with `calibrationFsrCount` ("N 6 (needs 8)").

## 3. Stored v1.6 data

The drift schema does not change; it stays at v3, so there is no
migration. Nothing is deleted or rewritten.

- **Temperature readings.** The columns `site6_*` and `site7_*` stay but
  are no longer written. Reads return sites 0–5.
- **Baselines.** A 14-value baseline is kept, but it does not count as a
  baseline: the app shows "record again". The next recording replaces it
  under the same key.
- **Alerts and days at the retired zones.**
  - They are named from `footLayout.retiredById`: 'อุ้งเท้า' and
    'ส้นเท้าด้านนอก'. The title uses the retired region name, so the old
    alert "ส้นเท้าซ้ายรับน้ำหนักมากตอนเดิน" still reads the same.
  - No map is drawn for them, and a raw id is never shown.
  - An 8-entry stored pressure map is drawn over the first 6 zones.
- **Test.** `test/storage/v16_rows_test.dart` writes what a v1.6 build
  stored into a file database, then reopens it with the v1.7 code. It
  checks that:
  - every row count is unchanged;
  - reads give 6 sites;
  - raw `site7_c` is kept on the old rows and is null on a new one;
  - retired alerts get names and no map;
  - the 14-value baselines are ignored and then replaced.
- **One deliberate drop.** A stored v1.6 alert at `lateralHeel` no longer
  gets the `heel_walking` gait note, because the note now covers `heel`
  only (`gait_note.dart`). The spec-reviewer noted that §8.3.1 doesn't
  cover this case. **Decision for you:** keep the drop, or name
  `lateralHeel` in the note too, for old alerts only.

## 4. Changes from the plan

1. **Temperature check order.** The plan checked count first. That
   reported 11-, 31- and 33-byte packets as `tempCount`, which is
   misleading. The app now checks:
   1. the 12-byte v1 packet (with its own hint), a packet shorter than the
      header, or a length other than `8 + 3 × count` for its own count
      byte → `tempLength`;
   2. a self-consistent packet whose count is not 6 → `tempCount`; v1.6's
      32-byte packet is labelled "the v1.6 8-site packet";
   3. quality above 2 → `invalidQuality`.

   §3.2, the generator and the vectors are updated to match:
   `count_8_in_26_bytes` is now `tempLength`, and `count_5_self_consistent`
   and `count_0_header_only` were added as `tempCount`.
2. **Appendix C was rewritten in S11-1, not S11-2,** so that the contract
   is complete in one PR and can be sent to the hardware team as soon as
   this is merged. Its hex examples are generated from the vectors:
   - the 200-byte sensor packet;
   - the 26-byte `quality_mixed` temperature packet;
   - `unreadable_one_site`;
   - the 381-byte compact 6-channel calibration JSON;
   - the rejected 12-byte packet and the rejected 32-byte count-8 packet.
3. **The dummy model computes its own baseline.** Since S9-2,
   `session_baseline` refuses the fixture's synthetic calibration, so
   `make_dummy_model.py` now takes the plain per-foot median of the valid
   rows. It is a dev-only asset, and the check file matches.
4. **FW-1's widest calibration now fits.** With 6 channels, even a
   32-character id with every number at its widest is 481 bytes, which is
   under 512. The test that expected a refusal became "the widest blob
   fits, and a short buffer is refused, never cut off".

## 5. Goldens

71 goldens changed. Each was reviewed against the old image:
- Most of them changed by about 1,300 px: the two dots per foot that are
  gone.
- The second warm site in the demos is now lateral midfoot instead of
  lateral heel.
- Diagnostics reads `N 6 · temperature v2, 6 sites`.
- In My feet › Pressure, the details table has 6 rows. The concentration
  figure changed (35 % / 32 % instead of 31 % / 27 %) because it is now
  computed over 6 zones.
- The temperature dots are still 8/12. The dot sizes are S11-2's job.

## 6. For the hardware team and the thesis

**Thesis and IRB.** Thesis doc 03 and IRB doc 10 say 6 FSR + 2 NTC per
foot; the app is now 6 + 6.
- Pressure matches: 6 sites, 24 model channels.
- The 6 temperature sites, and "Velostat" instead of "FSR", are thesis
  edits for you to make, not code changes.

**Hardware questions** (add these to report 043 §7):
1. **Mux channel per site (v1.7):** which mux channel does each of sites
   0–5 use, on each board?
2. **Bridged pairs:** on the right board, the hallux showed on C05 and C06
   together (report 043).
   - The 6 channels chosen must not include both halves of a bridged pair.
   - `config.h` says this next to `kMuxChannelOfSite`; its validity check
     only catches the same channel used twice.
3. **NTCs:** do the boards carry the 6 NTCs, NTC i next to FSR i?
   - If not, the board sends −32768 with quality 2 (`noNtcReading`, which
     is already 6 × −32768).
4. **Unread pads:** do the two pads that are no longer read need anything
   on the board, such as a pull-down or a mux channel left free?

Appendix C (v1.7) is the page to send, once you have reviewed it.

## 7. Spec review

`spec-reviewer` checked `git diff main...HEAD` against DATA-CONTRACT v1.7
and FLUTTER-PLAN §6. DESIGN-SPEC is left for S11-2. Everything it found is
fixed in `296d1f7`:

- **Blocker, in the doc I wrote.** Appendix C said the temperature quality
  bytes start at offset 16. At count 6 they start at 8 + 2 × 6 = **20
  (0x14)**, as §3.2's table, the app and the simulator all have it.
  - Firmware written from the wrong text would put quality over temp[4]
    and temp[5] and still pass every length, count and quality check.
  - The app would then show wrong temperatures, and could raise a false
    `TEMP_DELTA`.
  - Fixed, and the `quality_mixed` caption now says bytes 0x14–0x19.
- **Minor:** FW-1's `cal set` error message said index "0-7". Fixed to
  "0-5".
- **Minor:** the `preprocess.py` vector generator used v1.6's accel/gyro
  boundary. Fixed, the vectors were regenerated, and the app's test still
  matches bit for bit.
- **Cosmetic:** a Diagnostics log line said "contract v1.6". Fixed.

Checked by the review and found fine:
- the parser order in Dart, `sim_check.py` and every vector;
- no zone index 6/7 is ever read;
- rule 4 (two-foot metrics) and rule 12 (no threshold literals).

## 8. Build numbers

- No APK was built in S11-1; `pubspec.yaml` stays at 1.0.0+6.
- S11-2 releases **1.0.0+7**, followed by its Note 10 checkpoint (with the
  S10 phone checks).
- S10b moves to **1.0.0+8**. Its SESSIONS entry now also covers:
  - the battery-255 "USB" display and the `SI-` capture refusal (report
    043);
  - BACKLOG 80, board binding.

## 9. Next

1. Review and merge this PR. I ask before the push.
2. S11-2 on `work/six-sites-ui`:
   - dot sizes;
   - Temperature tab for 6 sites;
   - copy and Thai joiners for the retired names;
   - DESIGN-SPEC, BACKLOG (64/65 resolved, 66, 67), PROGRESS and
     `mobile/CLAUDE.md`;
   - the SESSIONS status rows;
   - release 1.0.0+7;
   - the Note 10 checkpoint. I ask before you plug in the phone.

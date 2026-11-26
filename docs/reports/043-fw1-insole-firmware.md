# 043 — FW-1: our firmware for the real insole, and what the right board's sensors do

**Status: in progress** (2026-11-09, branch `work/fw1-insole`, stacked on
`work/study-readiness` / PR #38). This report collects the hardware findings
from the hardware team's right board, which still runs their self-test
sketch. It also covers the FW-1 firmware written so far. No board has been
flashed. FW-1 can't be finished until the hardware team sends the pin map.

All board readings here come from the read-only serial log of the
self-test sketch. The sketch prints the 16 mux channels C00–C15 once a
second as raw ESP32-C3 ADC codes. We treat those codes as 4095 ≈ 2.5 V with
no eFuse calibration, so **every millivolt, ohm and fit number below is
approximate**. The pull-down is 1 kΩ (hardware team).

Raw logs and sessions are kept outside the repo, in
`~/smartinsole-data/board-checks/043-fw1-right/`:
- `rest-press/serial.log`
- `trial-cal-hallux-1/`
- `trial-cal-hallux-2/`, which includes `edges-crosstalk.txt` and the scripts that made it

Only short excerpts appear here, and no MAC address.

## 1. Summary

- **The hallux sensor reads on two mux channels, C05 and C06, which are
  always equal.** They match within ±3 counts in 96.4 % of 6,096 tables and
  within ±10 in all but two tables, across the full range 291–2444.
  - This points to two mux inputs wired to the same node (a bridge, or one
    sensor wired to both), or to the sketch reading one channel twice.
  - It is **not** a mux addressing fault and **not** supply droop (§4.4).
- **Crosstalk:** loading the hallux also raises C02 (+8 to +17 % of the
  hallux change) and C03 (+4 to +12 %) on every load.
  - C01 and C04 only dip briefly when the weight is placed or lifted.
  - The other 10 channels stay within ±2 %.
- **Velostat behaviour (trial, approximate):**
  - The hallux reading rises from about 580 at rest to 1400 / 1690 / 1950
    counts under 0.54 / 1.04 / 1.54 kg on a 20 mm coin (17 / 32 / 48 kPa).
  - It takes 3–5 s to reach 90 % of the plateau.
  - After each lift it drops 77–155 counts *below* its pre-load level and
    recovers within about 10 s.
  - The same 1.04 kg read 10 % higher coming down than going up.
- **The 8-sensor press test (0→7) and the first hand-press checks showed
  no response on any channel.** The hallux response first appeared at
  14:15. Which sensor is on which channel is still unknown for 7 of the 8
  sensors.
- **Unloaded readings drift with handling.**
  - At rest, untouched for 5 min, channels fell 5–27 %.
  - Over the afternoon, after handling, the channels near the hallux
    (C01–C06) settled 2–40 % lower (C05/C06 the most), while the others
    rose 5–12 %.
  - TARE at the start of every session is necessary. A 30 s rest after
    handling is not enough to settle.
- **The trial's range (≤ 48 kPa) is below the app's watch (75 kPa) and
  alert (200 kPa) thresholds.** The real calibration needs weights up to
  about 5 kg on a sensor-sized puck (§4.3).
- **FW-1 step a is done:**
  - `firmware/insole/` with 28 host tests passing;
  - the C3 build compiles (`buildcheck`: RAM 8.4 %, flash 40.2 %);
  - the guide/analysis tool `tools/calibration/cal_trial.py`.

## 2. FW-1 so far

The decisions are in `docs/DATA-CONTRACT.md` addendum 2 (§3.1, §3.3, §5.1,
§5.2):
- the wire unit is the divider voltage in counts of 3.3 V;
- a board with no battery sends 255 / 0 mV;
- one IMU frame is used for both insoles, with a per-foot axis map;
- the simulator's BLE core is reused through `lib_extra_dirs`, and
  `firmware/simulator/` is unchanged.

| Part | File(s) | State |
|---|---|---|
| Wire unit, two ADC ranges, saturation | `lib/insole_hw/src/adc_units.*`, `src/fsr_mux.*` | host-tested; device code compiles |
| IMU axis map per foot | `lib/insole_hw/src/axis_map.*`, `include/config.h` | host-tested; maps are placeholders |
| Calibration JSON (strict parse, ≤ 512 bytes, 6/4 digits) | `lib/insole_hw/src/cal_json.*`, `src/cal_store.*` (NVS `fw1cal`) | host-tested |
| TARE = 1 s mean, refused if a channel moves > 120 counts | `lib/insole_hw/src/tare_mean.*` | host-tested |
| No-NTC temperature, no-battery status, saturated flag | `lib/insole_hw/src/insole_frames.*` | host-tested against `shared/test_vectors` |
| BLE server, 50 Hz tick, serial `cal` / `cal set` / `cal test` / `raw on` | `src/ble_server.*`, `src/main.cpp` | compiles; not run |
| MPU6050 ±8 g / ±1000 °/s, DLPF 20 Hz | `src/mpu6050.*` | compiles; not run |
| Flash guard | `tools/upload_guard.py` | refuses buildcheck, any non-`usb-Espressif_` port, and no port given |

**Checks:**
- `pio test -e native`: 28/28 pass.
- `pio run -e buildcheck`: success.
- The `right`/`left` envs refuse to compile until `config.h` has the
  hardware team's pin map (`PINMAP_FILLED_IN`).

**ArduinoJson finding:** ArduinoJson 7.4 parses short decimals as `float`
(0.000113 comes back as 0.000112999995). The board therefore stores
calibration numbers at fixed precision (a and area at 6 significant digits,
b at 4). `cal set` prints the stored JSON so the laptop tool can compare it
byte for byte with what it sent. This replaced a digit check that could not
work.

## 3. The C3's ADC and the wire unit (1 kΩ pull-down)

The table below uses the **contract's example curve** (a = 1.23×10⁵,
b = −1.05, A = 113 mm²). It is **not a curve for the real Velostat sensors**.

| True kPa | V_out | Sent as counts of 3.3 V → app kPa | Raw C3 code sent instead → app kPa | ±35 mV (12 dB range) | ±10 mV (0 dB range) |
|---|---|---|---|---|---|
| 5 | 27 mV | 33 → 4.9 | 6.7 (+34 %) | 0.1–12.1 | 3.1–7.0 |
| 10 | 52 mV | 64 → 9.9 | 13.5 (+35 %) | 3.0–17.4 | 8.0–12.1 |
| 25 | 121 mV | 151 → 25 | 33.9 (+36 %) | 17.3–33.0 | 22.8–27.3 |
| 50 | 227 mV | 282 → 50 | 68.6 (+37 %) | 41.4–58.8 | 47.5–52.5 |
| 75 | 324 mV | 402 → 75 | 104 (+39 %) | 65.7–84.6 | 72.3–77.7 |
| 100 | 413 mV | 512 → 100 | 140.5 (+41 %) | 90–110 | 97.1–102.9 |
| 200 | 715 mV | 888 → 200 | 295 (+48 %) | 187–213 | 196–204 |
| 400 | 1151 mV | 1428 → 400 | 652 (+63 %) | 381–420 | — |
| 800 | 1679 mV | 2084 → 800 | 1635 (+104 %) | 765–837 | — |
| 1500 | 2156 mV | 2676 → 1500 | 5299 (+253 %) | 1429–1576 | — |

- **Ceiling:** the C3 reads up to 2.5 V. With this curve that is about
  2,550 kPa, and the saturated flag is set from 2.45 V (≈ 2,340 kPa).
- **Low end:** 10 kPa ≈ 64 counts, where one count ≈ 0.17 kPa. The ±35 mV
  error of the 12 dB range becomes 3–17 kPa there.
  - FW-1 therefore re-measures readings below 700 mV in the 0 dB range
    (±10 mV, so 8–12 kPa at 10 kPa).
  - TARE removes the constant part of the error.
- With Velostat the rest reading is not near 0 V, as §4 shows.
- **App side:** a count of 4095 would make the app compute about 10¹² kPa;
  its clamp is numeric only. This goes to BACKLOG.

## 4. Hardware findings (right board, self-test sketch)

### 4.1 Rest, 5 min untouched (12:36:41–12:41:41, 296 tables)

| Ch | Mean | Range | Start → end (drift) |
|---|---|---|---|
| C00 | 823 | 98 | 865 → 817 (−6 %) |
| C01 | 736 | 315 | 912 → 668 (−27 %) |
| C02 | 405 | 145 | 474 → 394 (−17 %) |
| C03 | 416 | 126 | 484 → 410 (−15 %) |
| C04 | 802 | 348 | 1019 → 746 (−27 %) |
| C05 = C06 | 816 | 183 | 916 → 807 (−12 %) |
| C07 | 809 | 91 | 838 → 791 (−6 %) |
| C08–C15 | 376–1049 | — | −5 to −9 % each |

- Rest values of 0.23–0.64 V are expected for Velostat, which has a finite
  resistance when unloaded.
- Every channel falls in the first minute and then mostly levels off.
- Each channel correlates 0.72–0.96 with the mean of the others, so the
  channels move together.

### 4.2 Press test, sensors 0→7 by hand (from 12:42:23)

- No channel showed a 5-s step anywhere between 12:42 and 12:49.
- The largest events were:
  - C03 jumping up and down (+768 / −141) and C04 dipping −368 at
    12:45:35–45, with every other channel −50 at the same moment;
  - a slow drift on C01/C04/C05 afterwards.
- Both look like handling, not a pressed sensor.
- Between 13:49 and 14:14, hand-press checks again showed no channel
  rising more than about +125.
- The hallux response first appears in the guide's check at 14:15
  (attempt 1): C06 +710, C05 +704.
- **So 7 of the 8 sensors still have no known channel.** Repeat the 0→7
  press test with the guide's live view (§6).

### 4.3 Trial calibration: hallux, 20 mm coin and a water bottle

**Set-up:**
- Coin (≈ 0.003 kg), then a 1.5 L bottle placed alone on the coin at
  500 / 1000 / 1500 ml (≈ 0.53 / 1.03 / 1.53 kg with the bottle).
- Load on the sensor = bottle + coin. **Masses are approximate (no scale).**
- The bottle was steadied with one fingertip.
- Area 314 mm², so 0.54 / 1.04 / 1.54 kg ≈ 16.7 / 32.3 / 47.9 kPa.

**Attempt 1** (`trial-cal-hallux-1`, partial, note only):
- The check found C06 +710, C05 +704, C04 −279, C01 −223.
- Stopped at 14:18:40 during the 1000 ml hold.

**Attempt 2** (`trial-cal-hallux-2`):
- The check found C06 +540, C05 +538, C04 −358, C01 −222.
- The session stopped at 14:24:25.9 (Ctrl-C or end of input) after
  500, 1000 and 1500 ml up and 1000 ml down. Round 1's 500 ml down and
  round 2 are not in the session.
- The log shows 13 more loads between 14:25:10 and 14:33:38 that have no
  guide timestamps. They are left out of this analysis until we know which
  fill each one was.

**The guide's own `analysis.md` is not valid for this session.**
- The bottle went on 4–11 s after each "place" beep and came off 3–8 s
  after each "lift" beep. The guide's fixed windows (last 5 s of each
  hold) therefore caught the rise and the next lift.
- The numbers below use the physical edges instead: the second the C06
  reading jumps.
- Fix for the next trial: start each hold when the user presses Enter after
  placing, or when the guide sees the jump (§6).

| Load | kg (approx) | kPa | Before (coin) | Plateau (last 4 s) | ±sd | Peak | Rise to 90 % | mV (approx) | R Ω (approx) |
|---|---|---|---|---|---|---|---|---|---|
| 500 ml up | 0.536 | 16.7 | 592 | 1403 | 24 | 1480 | 3.4 s | 857 | 2852 |
| 1000 ml up | 1.036 | 32.3 | 579 | 1689 | 40 | 1755 | 4.8 s | 1031 | 2200 |
| 1500 ml up | 1.536 | 47.9 | 542 | 1954 | 157 | 2339 | 4.0 s | 1193 | 1766 |
| 1000 ml down | 1.036 | 32.3 | 590 | 1860 | 165 | 2027 | 3.4 s | 1135 | 1907 |

**Settling:**
- The reading reaches 90 % of its plateau 3–5 s after it starts rising
  (this includes setting the bottle down).
- It does not settle within 6–15 s:
  - under 500 ml it peaked at +7 s and then fell 110 counts in 6 s;
  - under 1500 ml it swung ±300 counts (sd 157) with the hand steadying
    the bottle;
  - the 1000 ml down plateau was still rising when the bottle was lifted
    after 6 s.
- For the real calibration: a stand instead of a hand, holds of at least
  30 s with the value taken from the last 10 s, and the settle time
  measured again then.

**Up vs down:**
- 1000 ml read 1860 coming down (after 1500 ml) against 1689 going up:
  +171 counts, 12 % of the 1500 ml change.
- The bottle was lifted between loads, so this is a memory of the previous
  load, not a continuous loading/unloading loop. With 6 s and 10 s holds
  it is also partly the unsettled rise.

**After each lift:**
- The reading falls 77–155 counts below its pre-load level within 1–3 s.
- Where the next load was at least 10 s away, it was back within ±41 counts
  10 s after the lift.
- After the finger press it dropped −131 and was still +85 above its old
  level 20 s later.

**Fit of log(F) against log(R), approximate:**

| R used | All 4 holds | 3 up holds |
|---|---|---|
| R from the reading (no tare) | F = 3.75×10⁷ · R^−1.98, R² = 0.916 | F = 2.26×10⁸ · R^−2.21, R² = 0.991 |
| R from reading − pre-load level (the app's §5.1 after TARE) | F = 1.04×10⁶ · R^−1.41, R² = 0.941 | F = 2.79×10⁶ · R^−1.52, R² = 0.992 |

- Three load levels spanning ×2.9 in force say little about the curve's
  shape.
- The exponent (−1.4 to −2.2) is steeper than the contract example's −1.05.
- These numbers are a first look at the Velostat, not a calibration.

**Range:**
- The top load is about 48 kPa, below the app's watch (75 kPa) and alert
  (200 kPa) thresholds (`shared/thresholds.json`). The trial does not test
  the sensor where alerts happen.
- On this coin, 200 kPa needs about 6.4 kg.

**For the real calibration, get:**
- Weights up to about 5 kg in 6–8 steps (e.g. 0.25, 0.5, 1, 1.5, 2, 3, 4,
  5 kg), each weighed on a kitchen scale (±1 g).
- A rigid, flat puck about the sensor's active area (measure it first).
  On a 12 mm puck (113 mm²), 200 kPa is 2.3 kg and 5 kg is 434 kPa.
- A stand or guide tube that keeps the weight upright with no hand on it.

### 4.4 C05 = C06 and crosstalk under the hallux loads

Each figure is a channel's change from just before the load to the plateau,
in counts, with its percentage of the C06 change.

| Load | C06 | C05 | C05 − C06 at plateau | C01 | C02 | C03 | C04 | C07 | Other 9 (median, range) |
|---|---|---|---|---|---|---|---|---|---|
| finger press (check) | +566 | +564 | −0.5 | +76 | +119 | +44 | −26 | −87 | −24 (−87 … −8) |
| 500 ml up | +811 | +815 (100.5 %) | +1.0 | +112 (14 %) | +140 (17 %) | +95 (12 %) | +17 (2 %) | +12 (1.5 %) | +7 (+2 … +12) |
| 1000 ml up | +1110 | +1109 (99.9 %) | +0.2 | −106 (−10 %) | +98 (9 %) | +40 (4 %) | −83 (−8 %) | +4 | +16 (+4 … +21) |
| 1500 ml up | +1412 | +1412 (100.0 %) | +0.2 | +74 (5 %) | +115 (8 %) | +113 (8 %) | +19 (1 %) | +12 | +3 (−5 … +12) |
| 1000 ml down | +1270 | +1271 (100.1 %) | +0.5 | +31 (2 %) | +155 (12 %) | +74 (6 %) | −40 (−3 %) | −12 | −14 (−26 … −4) |

"Other 9" means C00 and C08–C15. Everything else ever seen during loads
stays within ±2 % of the C06 change.

**What it looks like:**

1. **C05 and C06 are the same electrical node: shared wiring, not mux
   addressing.**
   - They agree within ±3 counts in 96.4 % of 6,096 tables (12:30–14:37) and
     within ±10 in all but two tables, at every level from 291 to 2444 and
     under every load (100.0 ± 0.5 %).
   - The two exceptions (at most 46 counts) were in the middle of a fast
     change. The sketch reads the channels a few ms apart, which fits one
     node read twice.
   - A select-line fault would make several channel pairs identical (8 for
     one stuck line). It would also only merge channels that differ by one
     address bit, and 5 (0101) and 6 (0110) differ by two. No other pair is
     ever close.
   - **Likely causes:**
     - mux inputs 5 and 6 bridged;
     - the hallux sensor wired to both inputs;
     - the sketch reading the same input for both channels.
   - If a second sensor shares the node, pressing that sensor will also move
     C05/C06. The repeated 0→7 press test will show this.
2. **C02 and C03 rise with every hallux load: neighbour coupling, cause open.**
   - The same direction every time, 8–17 % (C02) and 4–12 % (C03) of the
     hallux change, and they dip with it at each lift.
   - It is either mechanical (the load spreading through the insole layers
     to neighbouring sensors) or electrical (a resistive path between
     traces).
   - **Two checks separate them:**
     - with the power off, the resistance between the hallux trace and the
       C02/C03 traces (should be open);
     - loading the hallux with a puck smaller than the sensor.
3. **C01 and C04: handling transients, not steady crosstalk.**
   - They dip 67–356 counts for 1–3 s at each placement and lift and recover
     in about 10 s.
   - Under a steady load their change varies in sign (−10 % to +14 %).
   - The finger press moved the uncoupled channels −2 to −9 %; the bottle
     (no hand on the insole) did not. These are the same handling drops seen all day
     (§4.2, §4.5).
4. **Not supply droop.**
   - Droop would pull every other channel down by the same fraction of its
     own reading, growing with the load.
   - The 9 uncoupled channels moved −2.2 % to +2.3 %, with a sign that
     changes between loads (1000 ml up: all +1.6 to +2.3 %; 1000 ml down:
     all −0.3 to −2.2 %) and no growth from 500 to 1500 ml. That matches
     the common drift seen at rest.
   - The sensor's extra current at the top load is about 1 mA (≈ 1.2 V
     across 1 kΩ).

### 4.5 Unloaded readings across the session

Mean counts per window; `~` marks windows that follow handling.

| Window | C00 | C01 | C02 | C03 | C04 | C05/06 | C07 | C08 | C12 | C15 |
|---|---|---|---|---|---|---|---|---|---|---|
| 12:36 rest test, 1st min | 847 | 904 | 466 | 471 | 1006 | 905 | 842 | 1077 | 892 | 394 |
| 12:41 rest test, 5th min | 814 | 698 | 403 | 410 | 763 | 815 | 786 | 1039 | 856 | 366 |
| 13:50 | 866 | 777 | 446 | 509 | 924 | 997 | 985 | 1106 | 910 | 372 |
| 14:00 | 817 | 742 | 412 | 490 | 880 | 901 | 912 | 1040 | 858 | 355 |
| ~14:21:48 trial rest, first 10 s | 864 | 655 | 316 | 379 | 665 | 548 | 893 | 1100 | 901 | 360 |
| ~14:22:08 trial rest, last 10 s | 887 | 722 | 356 | 422 | 729 | 620 | 924 | 1127 | 920 | 368 |
| ~before 500 / 1000 / 1500 / 1000 ml (coin on) | ~897 | 607–729 | 325–341 | 390–442 | 675–725 | 542–592 | 955–972 | 1142–1160 | 935–944 | 373–377 |
| ~14:35–14:37 after the trial (insole state unknown) | 877 | 704 | 399 | 460 | 743 | 684 | 898 | 1117 | 911 | 357 |

- **Within the trial:** the 30 s rest after the finger-press check was
  still rising (C05/06 +72, C01 +67, C04 +64 between its first and last
  10 s).
- **Pre-load levels with the coin on:** C06 stayed within 542–592 across
  the four loads.
- **Across the afternoon:** compared with 14:00, the trial's pre-load
  levels were lower on the channels near the hallux (C01 2–18 %, C02–C04
  10–23 %, C05/C06 34–40 %) and higher on the others (C00 and C07–C15,
  +5 to +12 %). So the unloaded level depends on handling history.
- **Logger gap:** the log has no readings from 13:07:54 to 13:26:03 and no
  boot messages around it.

## 5. Velostat, TARE and the calibration track

**Decisions (user, 2026-11-09):**
- TARE averages each channel's rest value over 1 s, at the start of every
  session.
- Fit F = a·R^b against the sensor's resistance in ohms, computed from
  eFuse-calibrated millivolts (FW-1 option B), so a/b don't depend on which
  firmware track wins.
- Calibrate the right insole's 8 sensors right after FW-1 is flashed and
  passes board_check. Calibrate the left insole when its firmware sends
  option-B units.
- Adding the NTCs later does not touch the Velostat layers. NTC calibration
  against a thermometer is a separate step.
- **Dependency:** calibration waits until the hardware is final (resistors,
  insole layers).

**Risks seen today:**
- drift at rest (−5 to −27 % in 5 min);
- slow settling (more than 15 s);
- undershoot after unloading;
- memory of the previous load (about 12 %);
- handling sensitivity;
- neighbour coupling.

Temperature sensitivity and differences between sensors are not measured
yet. The contract's power law (§5.1) was written for FSRs. The trial's
exponents differ from the example, so it must be checked against real
calibration data before the app relies on it.

**Procedure (plan):** one sensor at a time:
- TARE;
- known weights through a rigid puck of the sensor's area;
- 6–8 loads up, then down;
- at least 30 s per hold (the trial showed 15 s is too short), using the
  last 10 s;
- 3 repeats.

kPa = m · 9.80665 / A / 1000. The tool records from FW-1's `raw on` lines
(1 s means in counts of 3.3 V) or from the self-test tables until FW-1 runs.

**Fit and outputs (plan):**
- Per channel: the log-log fit, R², up/down hysteresis, drift, and MAE/RMSE
  on held-out loads. MAE/RMSE is thesis objective 1, sensor accuracy on the
  bench.
- If the power law fits poorly, an alternative such as a polynomial in log
  space or a per-sensor lookup table. Either needs a contract change, so it
  waits for the user's OK.
- **Output:** compact calibration JSON (≤ 512 bytes), loaded with
  `cal set <json>` on FW-1's serial port.

**Open decision: TARE and R for Velostat.**
- §5.1 subtracts `offset_adc` *before* computing R. With Velostat resting
  at 0.3–0.6 V, that R is not the sensor's resistance, so a/b fitted on the
  real R give the wrong kPa in the app.
- The trial reports both fits.
- **Options:**
  - (a) Fit a/b on the R the app computes (after TARE): no contract change.
  - (b) Compute R from the reading without TARE, and subtract the rest force
    F(R_rest) instead. This changes §5.1.
  - (c) TARE in conductance (G − G_rest). This also changes §5.1.
- **Recommendation:** record untared millivolts during calibration so all
  three can be fitted, choose by held-out error, and only then propose any
  §5.1 change.

## 6. Tool: `tools/calibration/cal_trial.py`

**`guide`:**
- a hand-press check with a live view (stops if no channel moves ≥ 60
  counts and records nothing);
- rest, coin, and the bottle loads up and down with Enter-gated refills;
- a beep and a timestamp in `session.json` for every step.

It reads only the log that `serial_read.py` writes and never opens the port.

**`analyse`:**
- per-hold means, drift, settle time, return after lift, up vs down,
  round 1 vs 2;
- both fits;
- the range and the shopping list.

Never overwrites an `analysis.md`. Tested on a made-up log (full run, and
the no-response stop).

**Limitation found today:** holds start at the beep, but placing the bottle
took up to 11 s. The next version should start each hold on Enter or on the
detected jump. Attempt 2 was analysed from the physical edges with the
scripts saved next to the session.

## 7. Questions for the hardware team (new, ahead of the existing list)

1. **C05 = C06:**
   - With the power off, is there continuity between mux inputs 5 and 6, or
     between the two sensor traces?
   - Does the self-test sketch read input 5 for channel 5 and input 6 for
     channel 6?
   - Which sensor should be on each?
2. **Channel map:** which mux channel is each of the 8 sensors on (hallux,
   MTH1, MTH2–3, MTH5, lateral midfoot, heel centre, medial arch, lateral
   heel)? Today only the hallux responded, on C05/C06.
3. **C02/C03 coupling:** where are those sensors relative to the hallux,
   and is the resistance between their traces and the hallux trace open
   with the power off?
4. **Pull-down placement:** is there one 1 kΩ resistor per sensor, or one
   on the mux common?
5. **Velostat construction:**
   - one sheet across all sensors, or separate pieces?
   - is any sensor preloaded by the insole layers?

## 8. Leftovers and decisions needed

- **User:** the open §5 decision (TARE and R for Velostat).
- **User:** what the 13 loads after 14:24:25 were, if they should be
  analysed.
- Next trial: repeat the 0→7 press test with the live view; fix the guide's
  hold start.
- FW-1 next steps:
  1. pin map from the hardware team;
  2. user's go-ahead;
  3. flash backup;
  4. flash the right board;
  5. board_check acceptance (`compare.py` needs updating for battery 255 and
     the C3 saturation ceiling).
- BACKLOG: the app's kPa at count 4095.
- After PR #37 merges:
  - add to S10b: refuse SI- captures and show "USB" when battery_pct is
    255;
  - fix the SESSIONS status row's date.

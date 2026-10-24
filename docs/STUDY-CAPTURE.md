# Study day: research capture on the phone

How to run one volunteer session with the phone app and get the data onto
the laptop. The procedure follows the IRB-approved proposal **doc 03**.
Where `docs/SmartInsole_TestProtocol_v1.md` differs, doc 03 wins (see
BACKLOG 32). If the phone capture fails in the middle of a session, switch
to the laptop: `docs/STUDY-FALLBACK.md`.

Built in S4C (`docs/reports/027-flutter-capture.md`). Code:
`mobile/lib/capture/`. Tools: `tools/capture/`.

## IRB rules the app enforces

- **Subject codes only.** The code field accepts `SI-001` to `SI-999`
  (study) or `TEST-001`… (rehearsal) and nothing else. There is no name
  field and no free text anywhere in the flow.
- **Coded data only** (doc 03): sex, an age range (never an exact age),
  foot length per foot, and room temperature. For an `SI-` code **all are
  required** (doc 03 records the room temperature every time). Start
  stays disabled, with a "Required for SI- codes: …" line, until every
  field is filled and valid. `TEST-` codes keep them optional.
- **Inclusion (doc 03):** age 21–30, so the age-range choices are
  21–25 / 26–30. For an `SI-` code, a foot length outside 25.5–27.5 cm
  (shoe size 42) blocks Start with "Does not meet the inclusion
  criteria". `TEST-` codes take any value.
- **Data stays on the phone** in the app's private storage until you
  export it. The export copy goes to the app's own external folder, which
  other apps can't read (Android 11+). It is removed from there after the
  laptop copy passes its checks.

## Before the volunteer arrives

1. Phone charged. Sound on, media volume up: the cues play on the media
   stream, so they still sound in silent mode. Do Not Disturb off.
2. Both insoles charged to **at least 80 %**. The pre-check blocks
   anything lower.
3. Connect the left and the right insole. Until Home has its own connect
   flow, this is Settings → **BLE debug (temporary)** → Scan → connect
   each insole as LEFT / RIGHT, then Back.
4. Settings (gear, top right of Home) → under **สำหรับผู้วิจัย**, press
   and hold **ส่วนผู้วิจัย** for 2 seconds. Research capture opens. Under
   **1 · Pre-check**, both feet must be green: streaming, battery ≥ 80 %, firmware and calibration read.

## The session

1. **2 · New session**: type the subject code, then sex, age range, both
   foot lengths and the room temperature (all required for `SI-` codes). The box below shows the gait
   order for this session (normal first, the other four random) and the
   antalgic pain side (odd code = left, even = right). Tap **Start
   session**. The screen stays on from here until you leave the session.
2. **Calibration (30 s standing still):** ask the volunteer to stand still
   with weight on both feet, then tap **Start recording**. It stops on its
   own.
3. **For each of the 5 gaits**, in the order shown:
   1. Demonstrate the gait. For antalgic the screen shows the pain side;
      for rotated foot, pick in-toeing or out-toeing first (required).
   2. Tap **Start practice (30 s), then record**. Practice is not recorded.
      Recording (3 min) starts by itself when practice ends. Use **Record
      now, no practice** only for a redo.
   3. Put the phone in your pocket and walk beside the volunteer.
4. **While recording**, nothing reacts to a short touch, and Back is
   blocked. The only controls are two **hold-for-2-seconds** buttons:
   - **Mark invalid** / **Valid again**: hold when the volunteer leaves the
     instructed gait, and hold again when they are back in form. Those rows
     get `valid = 0`.
   - **Stop early**: ends the recording now. It is saved as
     `stopped_early` and stays valid; the analysis decides later whether
     to use it. Press Redo if you want a full recording.
5. **Cues** (sound + vibration), so you don't need to look:

   | Cue | Sound | Vibration |
   |---|---|---|
   | Practice starts | two low beeps | two short |
   | Recording starts | one high beep | one |
   | 10 s left | two beeps | two |
   | Recording ended | three beeps | two long |
   | A foot's link lost (repeats every 5 s) | three low beeps | four short |
   | Link back | one high beep | one short |

   Holding **Mark invalid** confirms with the "10 s left" cue; **Valid
   again** confirms with the "link back" cue.

6. **After each recording**, the screen shows samples per foot and any
   gaps. Rest is open-ended (doc 03); the rest clock is only for your
   information.
   - **Next** when the volunteer is ready.
   - **Redo this trial** if it went wrong (a gap, wrong gait, stopped
     early). The old attempt is **kept**, marked invalid (`redo`), and the
     trial is recorded again as attempt 2.
7. After the last gait, the summary shows every trial. Any done trial can
   still be redone from there.

**If the app closes mid-session**, open Settings → hold **ส่วนผู้วิจัย**
for 2 s → the
session under **3 · On this phone** → **Resume**. A recording that was
running is kept, marked `interrupted`, and that trial must be recorded
again.

## Alerts during the session (S7)

Every alert the app raises **while this session's screen is open** (any
phase: calibration, a trial, rest or the summary) is tied to the session
by its time stamp, never by the subject code. It goes into the export as
`alerts.csv` and is deleted from the phone with the session.

- **Do the warm-compress step (doc 03) with the session open**, so its
  `TEMP_DELTA` alert lands in this session's `alerts.csv`. An alert raised
  after you leave the session screen is not part of the export.
- The app counts a temperature difference as an alert when it is
  **above** 2.2 °C on two readings in a row (readings come every 30 s).
  Doc 03 counts a warm-compress event as qualifying at **≥ 2.2 °C** on
  the reference thermometer. The two differ only at exactly 2.20 °C; the
  analysis uses doc 03's definition for qualifying events.
- **`PRESSURE_PTI` is not expected to fire during data collection.** It
  is the mean per-step pressure-time integral over the last 60 minutes of
  walking, and the trials are 3 minutes each, so a session never builds
  that window up. Its evaluation relies on the unit tests
  (`mobile/test/rules/alert_engine_test.dart`), not on study data. A
  `PRESSURE_PTI` row in a study export would be unexpected and worth a
  look.
- The same alert (code + foot + zone or site) is raised at most once per
  30 minutes, so a second warm compress within 30 minutes on the same
  foot and site gives no second row.

## Export (right after the session)

1. Summary (the list icon at the top right, or the screen after the last
   gait) → **Export for USB (adb)**. The screen shows the folder it staged
   the files in.
2. Plug the phone into the laptop (USB debugging on), then:

   ```
   python3 tools/capture/export_capture.py --dest ~/smartinsole-data
   ```

   For each staged session the script:
   - pulls it and checks every file's SHA-256 against `manifest.json`;
   - runs the data checks (see below);
   - saves it to `~/smartinsole-data/<sessionId>/`, never overwriting a
     different copy;
   - asks before removing the staged copy from the phone.

   Add `--serial <id>` if more than one device is attached.
3. **Back up** `~/smartinsole-data/<sessionId>/` to a second place (the
   protocol asks for two copies).
4. Only then: in the app, Summary → **Delete from phone**. It asks twice,
   and only works after an export.

## What the checks say

`python3 tools/capture/load_capture.py check <session folder>` prints one
line per check; `PASS` at the end means no FAIL.

- **FAIL**, in a valid attempt:
  - a 50 Hz step is more than 1 ms off 20 ms;
  - missing packets or a link loss;
  - a `completed` trial shorter than planned, or with fewer than 98 % of
    its samples;
  - labels inconsistent with the code (pain side, rotation, file names);
  - a planned trial with no valid attempt (when the session is done), or
    with two.
- **WARN**: stopped early, or segments marked invalid. These are fine,
  just shown.
- **INFO**: problems in attempts already marked invalid (e.g. a redone
  one).
- **`alerts.csv`**: FAIL on an unknown code, a level that does not match
  its code, a zone / site / side that is not valid for the code, rows
  out of time order, or an alert from before the session was created.
  WARN when the file is missing (an export from before S7).

## Files (one session folder)

| File | Contents |
|---|---|
| `session.json` | Code, coded subject data, room temperature, trial order and seed, pain side, timings, calibration summary (resting kPa per channel, starting temperatures, starting ΔT), every attempt, exports |
| `<code>_<nn>_<label>_a<k>.csv` | One row per sample per foot: unix time, device time, side, connection session, seq, sample index, missing packets, flags, `valid`, raw ADC ×6, kPa ×6, accel g ×3, gyro °/s ×3, temperature on the first row after each reading |
| `<code>_<nn>_<label>_a<k>.json` | Sidecar: gait and model index, pain side / rotation, planned and actual duration, end reason, valid / invalid reason, marked segments, gaps, per foot calibration table, firmware, battery, counts, temperature readings, app version |
| `alerts.csv` | Export only: the alerts raised while the session screen was open, oldest first (header only if none). `at_ms` (unix ms), `code`, `level` (1–5), `patient_status` (what Home showed), `side`, `zone`, `site`, `measured_value`, `threshold`, `gait_class`, `gait_confidence`, `read_at_ms`, `details` (JSON) |
| `manifest.json` | Size and SHA-256 of every file (from the export) |

`nn` is 00 for calibration, then 01–05 in the subject's order. For
training, `load_capture.model_matrix(trial)` gives the 24 model channels
in `shared/model_input.json` order. It pairs the feet by the same rule
the app uses (`pairing` in that file) and drops rows marked invalid.

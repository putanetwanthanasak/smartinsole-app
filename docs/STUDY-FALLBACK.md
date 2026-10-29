# Study-day fallback: capture on the laptop web app

> **Warning (S8D, 2026-10-29): this fallback does not work with the
> 8-sensor boards (DATA-CONTRACT v1.6).** The frozen web app reads only
> the v1.5 format. With a v1.6 board it refuses the 8-channel calibration,
> so Connect fails; past that, it would read the 28-byte samples at its
> fixed 24-byte stride (wrong numbers, no error) and a 32-byte temperature
> packet as 0.08 °C. Nothing usable can be captured. Until the user
> decides what replaces it (`docs/BACKLOG.md` item 63, before S9), there
> is no laptop fallback for the real boards. The steps below apply only to
> a board still running v1.5 firmware (6 FSR, 12-byte temperature); the
> simulator's `left_fsr6` build is not one (it sends temperature v2).
> Details: report 037.

Use this only when phone capture fails in the middle of a study session.
The normal phone procedure is `docs/STUDY-CAPTURE.md`.
Only one central may hold the insoles at a time, so the phone gives them up
first. Checked against the simulator in S3B (`docs/reports/025-*.md`).

**Have ready every study day:** the laptop charged and on mains power, sleep
and screen lock off, Google Chrome, and this repo in `~/smartinsole-app`.

## 1. Free the insoles from the phone

1. On paper: the time, and the trial that was running.
2. Turn the phone's **Bluetooth off** (quick settings). This always works,
   even if the app is stuck. Tapping Disconnect is not enough on its own,
   because the app reconnects by itself after a link loss.
3. Keep whatever the phone already saved. Export it after the session as
   usual.

## 2. Open the capture page

1. In a terminal: `cd ~/smartinsole-app && npm run dev`.
2. In Chrome, open **`http://localhost:5173/?ds=ble#/capture`**. A green
   "BLE DEV PANEL" appears at the bottom.
   - A Console notice "Web Bluetooth is experimental on this platform" is
     normal on Linux.
3. Keep this tab in front for the whole session. Chrome slows background tabs.

## 3. Connect both feet (always with the picker)

1. In the dev panel, **left** row: **Forget device** → **Connect** → pick a
   `SMARTINSOLE` device → **Pair**. Then do the **right** row the same way.
2. **Always Forget first.** A plain Connect to a remembered insole fails with
   "Bluetooth Device is no longer in range" once it has been disconnected for
   more than about 30 s (Linux forgets it).
3. The list may show old names. The app checks the side itself. If you
   picked the wrong insole, the row shows "Connected device reports
   foot_side=… but was connected into the … slot". Forget → Connect again,
   and pick the other one.
4. Wait until both rows show `connected`, `cal=…` with a device id, and
   `pkts=` rising.

## 4. Start a web-app session

1. Subject code: the **same code** as on the phone. Fill in the other fields.
   → **Start Session**.
2. **30 s calibration**: the volunteer stands still → **Start 30s countdown**
   → review → **Confirm**. It's required, because this is a new session for
   the web app.
3. On paper: "switched to laptop at HH:MM, from trial X".

## 5. Each remaining trial

1. **Reconnect both feet right before the trial**, as in step 3 (Forget →
   Connect, for left and for right). Then **start the trial within
   2 minutes**. If more time has passed (the calibration in step 4 counts),
   reconnect again. The web app re-syncs its clock 5 minutes after each
   connect, and that re-sync can shift one foot's timestamps by 160 ms.
   Reconnecting keeps it out of the 3-minute trial.
2. Tap the **gait pattern**. For antalgic, pick the affected side. For
   rotated foot, pick in-toeing or out-toeing.
3. **Start** → walk 3 min (watch the timer; it doesn't stop by itself) →
   **Stop**.
4. A bad stretch (stumble, talking, stopping): while recording, tap **Mark
   segment invalid**, and tap again when it's over.
5. After Stop, check that both dev-panel rows show **`dropped=0`** and
   **`pkts` = `seq` + 1**. If not, note it on paper with the trial.

## 6. If a foot drops (the web app does NOT reconnect by itself)

The top card shows `L: error` or `R: error`, and that row in the dev panel
shows `error`.

1. Tap **Mark segment invalid** at once, then **Stop**.
2. On paper: the time and the trial.
3. Reconnect that foot as in step 3 (Forget → Connect → pick → Pair).
4. Repeat the whole trial with the same gait pattern.

## 7. Export (before anything else)

1. **Export session** (or the download icon in the header). Chrome saves
   `<sessionId>_samples.csv` and `<sessionId>_metadata.json` to
   `~/Downloads`.
2. Copy both files to the study folder **now**, and check that the CSV isn't
   empty.
3. Check the file:
   `/usr/bin/python3 firmware/simulator/tools/webapp_csv_check.py ~/Downloads/<sessionId>_samples.csv`.
   Breaks between trials are listed, not failed. An "AMBIGUOUS" or "lost"
   step at a re-sync is a 160 ms clock step if step 5.5 showed no loss.
   `--assume-no-loss --write-corrected <out.csv>` writes a copy with those
   steps undone.
4. **End session**. Delete the session data only after the copy is safe.

## Good to know

- The web-app CSV has no `seq` column. A lost link shows only as a missing
  stretch of rows for that foot, so write the time on paper.
- Details: BACKLOG 28 (clock steps) and 29 (reconnect needs the picker).

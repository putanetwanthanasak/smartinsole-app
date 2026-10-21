# 025 — S3B (reduced): web app fallback check

Branch `work/webapp-fallback-check` · 2026-10-21/22 · Session S3B
(`docs/SESSIONS.md` §3, v2.2)

**Status: done.** The frozen laptop web app captures correctly from the
new simulator on its own:
- both feet, 26 984 rows each over 9 minutes;
- no lost packets;
- every step 20 ms except one resync step.

The **web app was not modified**. Two web-app behaviours turned up. You
decided "no web-app change" for both. They are handled in the new
`docs/STUDY-FALLBACK.md` and tracked as BACKLOG 28/29:
1. a 5-minute clock resync that can shift one foot's `tUnixMs` by exactly
   160 ms;
2. reconnecting a remembered insole on Linux needs the picker.

## What was done

1. **Docs v2.2** (`c52c541`). `docs/SESSIONS.md` and `docs/FLUTTER-PLAN.md`
   were replaced by your `~/Downloads` versions.
   - They were diffed against main first. Nothing merged was lost: every
     removed line is an intended v2.2 change.
   - The only date change: "Advisor (2026-10-19)" became "Advisor
     (2026-10-26)", which is the meeting date.
2. **`firmware/simulator/tools/serial_log.py`** (new). The S3A board logger,
   which had never been committed:
   - opens a CP2102 by its `/dev/serial/by-path/` name, with DTR/RTS low and
     a flushed input buffer;
   - writes laptop timestamps and strips control bytes;
   - **refuses bare `ttyUSB` names and any port that resolves to the Quectel
     modem** (tried: it refused the modem without opening it).
3. **`firmware/simulator/tools/webapp_csv_check.py`** (new, standard library
   only):
   - infers lost packets from the `tUnixMs` timeline, because the web-app
     CSV has no `seq` column;
   - matches each non-20 ms step to a logged `SYNC_TIME`;
   - checks that both feet are present over the same span and at 50 Hz;
   - `--assume-no-loss --write-corrected` undoes the web app's resync steps
     within each take (your decision, see Decisions);
   - `--selftest`: 15 cases.
4. **Executable paper check**: a scratchpad harness, not committed, like
   report 015. Output in `025-webapp-fallback-check/harness-output.txt`.
5. **Live run** with both boards. The laptop was the only central; the
   phone's Bluetooth was off throughout.
6. **Docs:**
   - `docs/STUDY-FALLBACK.md` (new, your addition at plan approval);
   - BACKLOG 28 and 29;
   - SESSIONS status row and S4 carry-forward notes;
   - simulator README section for the two tools.

## Paper check (`src/ts/data/WebBleDataSource.ts`, read, then executed)

| Question | Reading | Executed (harness) |
|---|---|---|
| `seq` restarting at 0 on START, per connection | `resetPerConnectionState()` clears `lastSeq`/`droppedPackets` on every connect. Gaps are counted from the first packet, with the 65535 wrap | `dropped=0`, last seq = packets − 1, on the first connection and after disconnect → connect |
| Boot-based `t0_ms` | `getUint32`; the offset is simply larger; `tUnixMs` is still wall time | offset = boot time + latency (10–157 ms); last sample within 116 ms of the clock |
| Report-015 check misfiring | Drops need a **strictly lower** `t0` (sensor l.503/l.515, temp l.578). Boot time never decreases within a connection | No warning in any run. Packet #0 is held, then committed: samples = 8 × packets exactly |
| BACKLOG 27 (before-START drop) | Not applicable: the web app has no START gate | — |
| Formats | Bytes match the TS-parser vectors (S2A/S2B). The calibration JSON has every required field; `SYNC_TIME` is 9 bytes | Simulator-format calibration parsed; 5 `SYNC_TIME` writes of 9 bytes |
| A real loss is still caught | — | One lost `seq` → `dropped=1`, and the CSV check FAILs at the right row |

The harness transpiled the unmodified sources with `typescript` from
`node_modules`. The only text change was `import.meta.env.DEV` → `true`.
It drove them with a fake GATT that behaves like the new simulator, in
fake time.

## Live results (2026-10-21 23:55 → 2026-10-22 01:20)

Left `88:57:21:B7:74:9E` on laptop USB port 3-6; right `38:18:2B:8A:26:D6`
on port 3-7 (new cable). Chrome 156 on Ubuntu, `?ds=ble#/capture`, central
`98:59:7A:62:7A:6D` (this laptop). Serial logs:
`025-webapp-fallback-check/serial-{left,right}.log`.

| Step | Result | Evidence |
|---|---|---|
| Setup | ✅ Chrome had Web Bluetooth with no flag (only Chrome's "experimental on this platform" notice) | Your Console report |
| 1 Connect | ✅ Both connected, `cal` correct, `dropped=0`. Each board: MTU 247 → 8/pkt, interval 30 ms, 3 notifications on → `SYNC_TIME` (9 bytes, accepted) → `START_STREAM`, 6.25 Hz, 0 notify failures. Board uptime at START 381 s (L) and 490 s (R) | Serial logs 00:04:32 / 00:04:53 |
| 2 Reconnect | ⚠️ → ✅ Disconnect → Connect failed on both rows with "NetworkError: Bluetooth Device is no longer in range". No connection attempt reached either board. **Forget device → Connect → picker → Pair** worked on both: `seq` restarted (L 194 = pkts − 1, R 148 = pkts − 1), `dropped=0`, no warnings, and the board's `t0` continued from boot (381 → 3 578 s, 490 → 3 674 s) | BACKLOG 29; serial 00:57:50 / 00:57:57 |
| **3 Capture** | ✅ Calibration + one "normal" take of about 9 min. Dev panel after Stop: L `pkts=5795 seq=5794`, R `pkts=5749 seq=5748`, `dropped=0 truncated=0`, both connected. No Console warnings | Your screenshot; `csv-check-live.txt` |

**Step 3 CSV** (`TEST-S3B-1792605719387_samples.csv`, 14 882 816 bytes,
SHA-256 `ca62b70257824129ddf357dbdc89028c810260c58b0c003e40965a6deccddaae`;
metadata JSON `6fa3215f…b53c831c`; not committed, per your instruction):

| | Left | Right |
|---|---|---|
| Rows | 26 984 | 26 984 |
| Span / rate | 539.66 s / 50.000 Hz | 539.82 s / 49.985 Hz |
| Steps of exactly 20 ms | 26 983 of 26 983 | 26 982 of 26 983; one 180 ms step at row 12392, 20 ms after the resync `SYNC_TIME` at 01:07:58.824 → AMBIGUOUS |
| Rows per 10 s window | 500–500 | 492–500 (the window with the step) |
| L/R start / end | +36 ms / −124 ms | |
| Script verdict | **PASS** | **PASS** |

**The 180 ms step is a clock step, not a loss:**
- the dev panel shows `pkts = seq + 1` and `dropped=0` for the connection;
- both feet have the same row count for the same take;
- after `--write-corrected`, every step on both feet is 20 ms and L/R is
  **+36 ms at both start and end** (`csv-check-corrected.txt`). A lost
  packet would have left the end 160 ms off.

The other 17 columns are byte-identical to the export.

**Done when** (SESSIONS S3B): "5 minutes of web-app raw capture from both
boards, no missing `seq`, 20 ms spacing". **Met:** 9 minutes, no missing
packets, 20 ms spacing apart from the documented resync step.

## Findings

### Resync steps are exactly 20 + 160·k ms (BACKLOG 28)

`syncTime()` sets `offset = send time − device time of the last sample
received`, every 5 minutes. The serial log shows Chrome's writes exactly
**300 000 ms** apart (`d_unix 300000`, 3 times on each board).
300 000 ms = 1 875 packets of 160 ms. So every resync after the first
changes the offset by exactly 160·k ms, where k is how many more or fewer
packets had arrived at send time:
- k = 0: invisible (left foot here);
- k = +1: a 160 ms hole with no data lost (right foot here);
- k = −1: `tUnixMs` goes backwards by 140 ms.

Board-vs-laptop drift never enters, because both differences are exact.

Effects:
- such a step looks exactly like a lost packet in a CSV without `seq`;
- it shifts that foot's timestamps against the other by 160 ms (8 samples)
  from that point on.

It doesn't depend on the new simulator, because the old one had the same
packet period. **S4 must not copy this formula** (SESSIONS carry-forward).

### Reconnect needs the picker on Linux (BACKLOG 29)

BlueZ deletes an unpaired device `TemporaryTimeout` = 30 s after it
disconnects. `bluetoothctl info` showed both boards "not available", while
a passive scan saw both advertising (−43/−50 dBm). The web app's Connect
reuses the remembered `BluetoothDevice` without scanning, so
`gatt.connect()` fails at once. Forget device → Connect (picker) always
works. That matters for the fallback's "a foot drops" path, so it's now in
the procedure.

### Laptop and hardware observations

- **The left board's USB is flaky.** Port 3-6 had the old cable.
  - At plug-in it attached and detached 4 times in 9 s (23:55:24–33).
  - The first logger open then read nothing for 20 s. The board was
    advertising, so it was running.
  - A second open (no central connected yet) read clean.
  - At **01:13:31** port 3-6 dropped and re-enumerated (`journalctl -k`),
    which ended the left serial log. That was 41 s after the take ended
    (last row about 01:12:50), so the data isn't affected.
  - The right board on its new cable stayed attached the whole time.
  - In S3A the cycling was on the other port, so the cable, the board's USB
    socket or the laptop port 6 is suspect. **Replace or swap before the S4
    checkpoint.**
- **`pkill -f` matched its own shell** while stopping the loggers, which
  aborted that command. The loggers had stopped anyway. Stop processes by
  PID from now on.
- The last line of the right log (01:20:44) has replacement characters.
  That was the logger being killed in the middle of a line.

## Checks

| Check | Result |
|---|---|
| v2.2 docs diffed before replacing | Pass: nothing merged lost (see item 1) |
| `webapp_csv_check.py --selftest` | Pass, 15/15 (`csv-check-selftest.txt`) |
| Harness on the unmodified `WebBleDataSource` | Pass, all checks (`harness-output.txt`) |
| Harness CSV → `webapp_csv_check.py` | Clean run PASS, L/R +14 ms. The lost-packet run FAILs at the lost row |
| Live steps 1–3 | Pass (step 2 with Forget → Connect, see BACKLOG 29) |
| Web app, `mobile/`, `shared/` untouched | Pass: `git diff main --stat -- index.html src css public package.json package-lock.json vite.config.ts tsconfig.json mobile shared` is empty |
| FLUTTER-PLAN §6 | Rule 1: the 20 ms spacing in the script is the contract constant. Rule 12: no clinical thresholds in the tools (2 s span tolerance and 5 s break are test parameters). Other rules: app-side, not touched |
| Emulator / Note 10 | Not applicable: no app change, and the phone stayed off the insoles by design |

## Decisions made

- **Resync step (BACKLOG 28): no web-app change** (your answer). It's
  handled two ways:
  1. the fallback procedure reconnects both feet before each 3-minute
     trial, so no resync can fall inside a trial;
  2. `--write-corrected` undoes steps afterwards.
- **Correction to what I offered in the question:** `--write-corrected` is
  equal to the per-connection anchor only **within a take**. A resync that
  falls between two takes leaves no trace in the CSV, so it can't be undone.
  That's why the procedure step matters more than the tool.
- **Reconnect (BACKLOG 29):** procedure only (Forget → Connect). A one-line
  web-app fix is noted in the item if you ever want it.
- **CSV not committed** (your instruction). The hashes above identify it.

## Decisions needed

None. You may now **delete the `TEST-S3B` session data** in the web app
(Export was done and the CSV is hashed). Please also check the left board's
USB cable before S4.

## Leftovers (BACKLOG)

- **28 (new):** web-app resync steps of 20 + 160·k ms, and no `seq` in its
  CSV. Includes the S4 warning.
- **29 (new):** Chrome/BlueZ reconnect needs the picker after about 30 s.
- 27 is unchanged (S4).

## Next session

S4 (DeviceManager + timing) on the phone. From here:
- the offset must be anchored to each packet's own arrival, not to "send
  time − last received sample" (BACKLOG 28);
- `serial_log.py` is now committed for the S4 checkpoint logs;
- fix the left board's USB before that checkpoint.

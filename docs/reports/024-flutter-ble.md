# 024 — S3A: BLE, both feet (Flutter)

Branch `work/flutter-ble` · 2026-10-20/21 · Session S3A (`docs/SESSIONS.md` §3)

**Status: done.** The Note 10 checkpoint passed on 2026-10-21 (section "Note
10 checkpoint results"). The user ran it on the device; Claude Code
cross-checked it against the boards' serial logs and the phone's BLE log.
Done-when for S3A, "both feet stream continuously for 5 minutes on the
Note 10", is met.

## What was done

1. **`docs/SESSIONS.md` → v2.1** (`f0485d5`). The S2B/S2C Verify and
   Done-when lines keep the 66c3c81 bleak/test-vector wording, because
   v2.1's shorter versions dropped pass criteria (confirmed at plan
   approval).
2. **Right board flashed.** Only the second board was plugged in; it was
   flashed with `pio run -e right -t upload` (the Quectel modem was never
   opened).
   - `sim_check.py --side R --duration 60 --reconnects 1 --no-control`:
     PASS, 0 failures. R = `38:18:2B:8A:26:D6`, foot_side 1, 375 packets,
     0 gaps, 6.249 Hz.
   - After the swap, `sim_check.py --side L`: PASS. L =
     `88:57:21:B7:74:9E`, foot_side 0.
3. **Dependencies and permissions** (`5fb5e6c`).
   - Added `flutter_blue_plus ^2.3.14` and `permission_handler ^12.0.3`,
     plus `fake_async` as a dev dependency.
   - `AndroidManifest.xml`:
     - `BLUETOOTH_SCAN` (`neverForLocation`) and `BLUETOOTH_CONNECT`.
     - Legacy `BLUETOOTH`, `BLUETOOTH_ADMIN` and `ACCESS_FINE_LOCATION`,
       all with `maxSdkVersion="30"`.
     - `uses-feature bluetooth_le required=false`.
4. **BLE layer** in `mobile/lib/ble/` (`1ab7d49`; file list in
   `lib/ble/README.md`):
   - **`BleCentral` / `BleLink`.** Our own thin interface. Only
     `fbp_central.dart` touches flutter_blue_plus, so the plugin can be
     replaced later and the tests run on a fake.
   - **`BleHub`**, shared by both feet. It tracks readiness (permission and
     adapter) and runs one shared scan, leased by whoever needs it, with
     no more than 4 starts per 30 s, safely under Android's limit of 5 (a 6th start in 30 s is silently blocked). It
     also remembers recent sightings, records which foot owns which insole
     (the other foot gets `inUseByOtherFoot`), and lets only one connection
     setup run at a time.
   - **`BleDataSource`**, one per foot (`InsoleDataSource`, contract §6).
     The full sequence runs on **every** connect and reconnect:
     1. connect (`License.nonprofit`, `mtu: null`, `autoConnect: false`)
     2. request MTU 247
     3. priority HIGH
     4. discover services
     5. read status and **check `foot_side`**
     6. read calibration
     7. **MTU fit check**
     8. subscribe
     9. `SYNC_TIME` (9 bytes)
     10. `START_STREAM`
   - **MTU fit.** With N = 6, 8 samples per packet need MTU 203 and 4 need
     MTU 107 (123 for N = 8).
     - Below the 4-sample minimum the foot goes to `problem(mtuTooSmall)`.
       No START is sent, the link is disconnected, and a Thai message with
       a Retry button is shown.
     - An MTU change in the middle of a stream is checked the same way.
   - **Wrong side (rule 8).** Checked both at connect and on every later
     status notification. The result is `problem(wrongSide)`, with no
     START and no auto-reconnect. The advertised name is shown "(display
     only)" and is never used to decide the side.
   - **Stale packets (rule 9, BACKLOG 20):**
     - Each connection gets a generation number, so anything from an older
       connection is dropped.
     - Sensor and temp packets that arrive before this connection's START
       is acknowledged are dropped.
     - t0 and temp `t_ms` must move forward modulo 2³² within a connection.
       Each new connection resets that check.
     - Everything dropped is counted by reason, never dropped silently.
   - **`seq` gaps** are counted with wrap at 65535.
   - **Calibration** is read again when flags bit1 goes from 1 to 0
     (BACKLOG 23).
   - **Reconnect.** After an unexpected disconnect, the foot goes back to
     searching on the shared scan and backs off 1, 2, 4, then 5 s,
     indefinitely.
     - Bluetooth off parks it.
     - A denied permission makes the foot `LinkBlocked`.
     - The user's Disconnect sends STOP and never reconnects.
   - **Frames.** `SensorFrame` carries `receivedAt` (phone clock, rule 3)
     and, per sample, `deviceMs = t0 + i·20` (rule 1), kPa, g and dps.
     Every packet is emitted; nothing is throttled here (rule 10).
     Converting to unix time and handling staleness is S4.
5. **Temporary debug screen** (`da47f98`):
   - File `lib/ui/screens/debug_ble_screen.dart`, route `/debug-ble`. It is
     opened from Settings → "BLE debug (temporary)" and S8B hides it.
   - Labels are technical English. Problem and readiness messages are Thai,
     with the English detail under them (decided at plan approval).
   - Contents:
     - scan list keyed by remote id, with "Connect as LEFT/RIGHT" buttons
     - one card per foot: state, MTU, samples/packet, N, status, pkt/s
       over 10 s, seq gaps, rejects, the drop counters, sessions and link
       losses, kPa and temperature
     - event log with "Copy log"
   - "Last packet X s ago" and the quiet-stream banner (after 2 s) are
     computed when the card is drawn (rule 2). The 250 ms tick only
     redraws.
6. **Fresh counters per insole and the emulator entrypoint** (`34b559a`):
   - **Bug found on the emulator:** after re-binding a foot to another
     insole, the old insole's packets and kPa stayed on the card under the
     new id. Re-binding now starts new `LinkStats`, and a test covers it.
   - `test_driver/main_mcp.dart` with `--dart-define=BLE_FAKE=true` runs the
     app on a scripted fake with three insoles: the two real ids, plus one
     with MTU 23.
   - `main.dart` now exposes `runSmartInsole(overrides:)`.
7. **Docs:** `lib/ble/README.md`, `mobile/CLAUDE.md` (layout, a new "BLE
   connection rules" section, the `BLE_FAKE` flag, the driver frame-sync
   tip, and the BLE fakes that `pumpApp` installs) and BACKLOG 20, 23, 25,
   26.

### Found and fixed by the tests or the emulator

- **The scan stopped between retries.** At first a foot gave up its scan
  lease when a connect failed. During the backoff no sightings arrived, so
  the next attempt found the device "not seen" and waited again. The foot
  now holds the lease from the start of searching, through every retry,
  until it is streaming (tests "failed attempts back off 1, 2, 4, then 5 s"
  and "a power-cycled board is found again by the scan").
- **`dispose()` used `ref`** in the debug screen. Riverpod forbids that
  after unmount, and it threw in the widget tests. The hub is now stored in
  a field.
- **Stats were not reset on re-bind.** See item 6.

## Checks

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `dart format --set-exit-if-changed lib test test_driver` | 0 changed |
| `flutter test` | **183 passed** (129 before; 42 `ble_data_source_test`, 7 debug-screen widget tests, 5 goldens) |
| Web app untouched: `git diff main --stat -- index.html src css public package.json package-lock.json vite.config.ts tsconfig.json` | Empty |
| Simulator R and L with `sim_check.py` | PASS (see item 2) |

**Mutation check.** Four mutations were applied to `ble_data_source.dart`
one at a time. Each made tests fail, and the file was restored after each:

| Mutation | Test(s) that caught it |
|---|---|
| Skip the `foot_side` check | "reconnect: a reflashed board that now reports the other side is rejected" (and others) |
| Treat START as acked before writing it | "packets before the START acknowledgement are dropped" |
| Don't request MTU (assume 247) | 10 tests, including "a lost link reconnects with MTU 247 and the side checked again" |
| Disable the t0-forward check | "t0 must advance within a connection; duplicates are dropped" |

**Rules, against the diff:**

| Rule | Where | Verdict |
|---|---|---|
| 1 `t0 + i×20` | `SensorSample.deviceMs` comes straight from the S2A parser | ✅ |
| 2 no latched staleness | Connection state is event-driven. "Last packet X s ago" and the quiet banner are computed when drawn. The timers only schedule retries and redraws | ✅ |
| 3 arrival time | `receivedAt = now()` (`clockProvider`) on every frame; the device clock is never used for arrival time | ✅ |
| 8 wrong side | Checked at connect and on status notifications: problem, no START, no reconnect | ✅ |
| 9 stale packets | Generation number + before-START drop + t0/t_ms forward (mod 2³²) | ✅ (checks 1 and 2 of BACKLOG 20) |
| 10 50 Hz / 10 Hz split | The BLE layer emits every packet unthrottled; the 10 Hz display path is S4 | ✅ |
| 12 no hardcoded thresholds | No clinical threshold in `lib/ble/`. The debug screen's 2 s "quiet" banner is a developer hint, not a clinical threshold | ✅ |

**Unit tests** (`test/ble/ble_data_source_test.dart`, `fake_async`) cover:

- the exact call order
- MTU 247 requested on the first connect and on every reconnect
- MTU 247 → 8/pkt, 120 → 4/pkt, 23 → `mtuTooSmall` with no START; N = 8
  at MTU 120 → too small; a mid-stream MTU drop
- wrong side at connect and via a status notification
- a device named "SMARTINSOLE-R" that reports left is accepted as left
- drop before the START ack; drop of late packets from the old connection
- t0 backwards and duplicates dropped; t0 restart on a new connection
  accepted; the uint32 wrap accepted; temp `t_ms` handled the same way
- rejects counted by reason (wrong N → `lengthMismatch`)
- seq gaps, including the wrap
- the calibration re-read on the bit1 falling edge
- backoff timing; no reconnect after the user's Disconnect
- Bluetooth off/on; permission denied
- one insole can't be bound to both feet; scan start rate limit; fresh
  counters on re-bind

### Emulator (Pixel 7 AVD, Android 17, Dart MCP + adb)

Screenshots are in `docs/reports/024-flutter-ble/`.

**Fake BLE** (`BLE_FAKE=true`):

| File | Shows |
|---|---|
| `1-scan.png` | Scan list keyed by remote id, names marked "(may be cached)" |
| `2-both-streaming.png` | Both feet STREAMING · MTU 247 · 8/pkt · N 6, about 6.2–6.3 pkt/s, 0 gaps, 0 rejects, side read from `foot_side` |
| `4-rebind-fresh-stats.png` | Left re-bound to the MTU-23 insole: `PROBLEM · mtuTooSmall` with the Thai message, "MTU 23 fits no packet; 4 samples of N = 6 need MTU 107", fresh counters, Retry |
| `5-event-log.png` | The event log for the same run: "MTU requested 247, got 23", "disconnected by user" before the re-bind |

The wrong-side state was also seen live: 88:57… connected as RIGHT gave
"wrongSide: insole reports foot_side left, this slot is right" and
"แผ่นรองเท้านี้เป็นข้างซ้าย ใช้เป็นข้างขวาไม่ได้". That screenshot was
overwritten while the re-bind bug was being fixed, so the committed picture
of it is the golden `test/goldens/screens/ble_debug_problems.png`.

**Real plugins** (no fake; the emulator's virtual Bluetooth):

| File | Shows |
|---|---|
| `6-emulator-real-plugins.png` | Android's own "Nearby devices" permission prompt, raised by `permission_handler` |
| `7-permission-denied.png` | "Don't allow" → "ต้องอนุญาตให้แอปใช้บลูทูธก่อน" / `needsPermission`, with an Allow button; Scan disabled |
| `8-permission-granted.png` | Allow → readiness card gone, "adapter: on". A real scan started with no errors (`get_runtime_errors`: none) |

**Driver note:** the debug screen's 4 Hz tick keeps a frame pending, so
`flutter_driver` taps time out unless `set_frame_sync` is off. Some taps
also had to go through `adb shell input tap`. This is noted in
`mobile/CLAUDE.md`.

## Observations and decisions

- **flutter_blue_plus license.** 2.x is under the FlutterBluePlus License:
  free for accredited educational institutions, nonprofits and
  organisations under 50 employees. KMUTT thesis use qualifies, so
  `connect()` passes `License.nonprofit` (the user's decision). If the
  project ever goes commercial, the `BleCentral` layer lets
  `flutter_reactive_ble` (BSD) or a paid FBP licence go in without touching
  `BleDataSource`.
- **`permission_handler` is pinned to `^12.0.3`.** 13.x pulls in
  `permission_handler_android` 14.1.0, which fails the build with
  "requires … compile against version 37 … :app is currently compiled
  against android-36". AGP 9.1 supports at most 36. Version 12.0.3 uses
  `permission_handler_android` 13.0.1 (compileSdk 35). Recorded as
  BACKLOG 26.
- **Android ≤ 11 location** is declared but left to flutter_blue_plus's
  own request. This is untested; the Note 10 is Android 12 (BACKLOG 26).
- **The `seq` look-ahead was not implemented** (the optional idea in
  BACKLOG 20).
  - It would hold the first packet of every connection until the second
    arrives, which delays the stream.
  - When `seq` 0 itself is lost, it either drops a real packet or never
    fires.
  - The generation number and the before-START drop already cover the
    stale-packet case the simulator can produce.
- **The connection interval can't be read** through Android's public API.
  The app requests HIGH priority each time (BACKLOG 25). The interval
  actually granted comes from the simulator serial log
  (`[ble] conn N: interval …`), which the checklist captures.
- **No wakelock.** The checklist asks for a 10-minute screen timeout.
  Keeping the app alive with the screen off is a later session's job.
- **Checkpoint setup problems (laptop side, not the app):**
  - **Serial garbage after plug-in.** For the first few minutes after both
    boards were plugged in, both ports read repeating garbage at 115200,
    even with nobody else holding them. A baud scan a few minutes later
    read 100 % clean at 115200, and it stayed clean. ModemManager probing
    the new ports is the likely cause, but this isn't proven. The logger
    now opens with DTR/RTS low and flushes the input buffer.
  - **adb kept losing the phone.** Several times the USB link stayed up
    while adb stopped listing the phone (fixed each time by
    `adb kill-server`). The phone also dropped off USB at 20:52–20:54
    (during the first install, until the user fixed the connection),
    21:10:58 and 21:20:03. None of this touched
    Bluetooth: both foot sessions continued, and the app process never
    restarted. After 21:20 the app's side was read from the screen.
  - **The right board's USB cable may be loose.** Unplugging once
    (step 6b) produced several connect/disconnect cycles in the kernel log
    between 21:23 and 21:25, including a 1-s attach. Every cycle recovered
    by itself, but the cable or socket should be checked or replaced
    before S3B.
- **The debug screen is temporary.** It reads `BleDataSource.stats`
  directly, which S4's real screens won't do. S8B hides it.

## Note 10 checkpoint results (2026-10-21) — PASSED

Phone: Samsung Note 10 (SM-N975F, Android 12), debug build. Boards: left
`88:57:21:B7:74:9E` on laptop USB port 6, right `38:18:2B:8A:26:D6` on port
7 (by-path; the CP2102s share one by-id). Evidence in
`docs/reports/024-flutter-ble/`:

- **Serial logs:** `note10-serial-left.log` and `note10-serial-right.log`,
  laptop time, stray control bytes stripped.
- **Phone log:** `note10-phone-ble.log`, the app's `[ble]` lines from 20:57
  to 21:20. The capture ended when adb lost the phone, see Observations.
- **Screenshots:** `note10-*.jpg`, taken by the user.

The phone's clock runs about 1.6 s behind the laptop's: its "streaming"
line comes 1.6 s before the board logs `START_STREAM`. Times below are
laptop time unless marked "phone".

| Step | Result | Evidence |
|---|---|---|
| 1 Install | ✅ Debug APK installed; app launched (pid 14079 for the whole run) | `adb install` → Success |
| 2 Permission | ✅ Nearby-devices prompt → Allow; scan card + two IDLE cards, no readiness card | User; phone log `permission: granted`, `adapter: on` |
| 3 Scan | ✅ Both found by service UUID within 1 s (RSSI −61 / −63) | Phone log |
| 4 Connect | ✅ L streaming 21:00:51 (phone), R 21:01:08 (phone); MTU 247 granted, 8/pkt, N 6; calibration `SIM-L-001` / `SIM-R-001` | Phone and serial logs |
| **5 Five minutes** | ✅ **Both cards at 21:09–21:10 (≈ 9 min):** 6.30 pkt/s, seq = packets − 1 (3395 / 3354), gaps 0, rejects 0, all drop counters 0, sessions 1, link losses 0, last packet 0.1 s | `note10-5-*.jpg`; boards: 6.25 pkt/s sent, 0 notify failures, 0 MTU drops, 0 disconnects |
| 6a EN reset (right) | ✅ Board reboot 21:19:43.8 → app `link lost` ≈ 5 s later (supervision timeout 5000 ms) → full sequence again → streaming ≈ 7 s after the reset, no tap. Card: sessions 2, link losses 1, gaps 0. Left unaffected | `note10-6a-*.jpg`; both logs |
| 6b Unplug/replug (right) | ✅ Back to STREAMING · MTU 247 by itself. Card: sessions 4, link losses 3, failed 0, gaps 0, rejects 0, **dropped before START 1** (BACKLOG 27). Left kept streaming. The kernel saw three plug-ins (21:23:55, 21:24:36, 21:25:38), see Observations | `note10-6b-*.jpg`; kernel log |
| 7a Left board as RIGHT | ✅ `PROBLEM · wrongSide`, "แผ่นรองเท้านี้เป็นข้างซ้าย ใช้เป็นข้างขวาไม่ได้" / "insole reports foot_side left, this slot is right"; calibration not read; sessions 0, failed 1; only Retry. Board: connected 21:37:04, disconnected 21:37:07, **no START**, no retry. Disconnect beforehand sent STOP to both boards, and both stayed IDLE | `note10-7a-*.jpg`; serial logs |
| 7b Right board as LEFT | ✅ Same result, mirrored. Verified by the user on the device. Board: connected 21:44:33.8, disconnected 21:44:36.5, no START, no retry | User; right serial log |
| 8 Bluetooth off/on | ✅ Verified by the user on the device: Bluetooth-off card, both feet stopped with no error loop; after Bluetooth on, both back to STREAMING · MTU 247 by themselves. Boards: both disconnected at 21:47:56.5; right reconnected 21:48:13.3, left 21:48:15.2 (one setup at a time), each with MTU 247 → 8/pkt, 11.25 ms, SYNC_TIME, START, then 6.25 pkt/s | User; both serial logs |

**Connection interval (BACKLOG 25):** after the HIGH request, the Note 10
settled at **11.25 ms** on both boards, on every connect and reconnect,
with latency 0 and supervision timeout 5000 ms. Each connection briefly
passes through 45–48.75 ms and 7.5 ms first. nRF Connect, which makes no
request, stayed at 48.75 ms in S2C.

One extra session not in the checklist: 21:41:37–21:44:24 the right board
streamed in the RIGHT slot before step 7b. It started with START and ended
with STOP, so it was a normal user connect and disconnect.

### The checklist as given

Phone: Samsung Note 10 (SM-N975F, Android 12, `RF8M83P4STZ`). Please send
back the "Copy log" text or a screenshot for each step marked 📋.

0. **Before you start:**
   - Set the phone's screen timeout to 10 minutes and turn on Bluetooth.
   - Plug **both** boards into the laptop and tell me. I'll match each
     `/dev/serial/by-path/…` to its CP2102 with `udevadm` (never the
     Quectel) and start one serial log per board **before** the phone
     connects. Opening a port resets that board.
1. With the phone on USB, run in `mobile/`: `flutter run -d RF8M83P4STZ`
   (debug build).
2. Go to Settings (gear) → "BLE debug (temporary)". When Android asks for
   Nearby devices, tap **Allow**. 📋 if anything other than the scan card
   and two IDLE foot cards appears.
3. Tap **Scan**. Expect two rows, `88:57:21:B7:74:9E` and
   `38:18:2B:8A:26:D6`.
4. On `88:57:21:B7:74:9E`, tap **Connect as LEFT**. On `38:18:2B:8A:26:D6`,
   tap **Connect as RIGHT**. Both cards should show
   `STREAMING · MTU 247 · 8/pkt · N 6`. 📋
5. **Leave both feet streaming for 5 minutes** with the screen on. Then
   check both cards. 📋 (screenshot of both cards plus Copy log)
   - packets about 6.25/s (10 s)
   - seq gaps 0
   - rejects 0
   - every "dropped" counter 0
   - last packet under 1 s ago
   - link losses 0
6. **Power cycle:**
   - Press **EN** on the right board. Within a few seconds the right card
     should go RETRY/SEARCHING → STREAMING by itself, with **MTU 247**
     again and "sessions 2".
   - Then unplug the right board's USB, wait 5 s, and plug it back in.
     That ends its serial log; tell me and I'll restart it.
   - The card should recover the same way. 📋
7. **Wrong side:**
   - Tap **Disconnect** on both cards. Both should go IDLE and stay IDLE.
   - Scan, then connect `88:57:21:B7:74:9E` as **RIGHT**. Expect
     `PROBLEM · wrongSide` and "แผ่นรองเท้านี้เป็นข้างซ้าย
     ใช้เป็นข้างขวาไม่ได้", with no reconnect loop.
   - Disconnect, then connect `38:18:2B:8A:26:D6` as **LEFT**. Expect the
     same, with "…ข้างขวา ใช้เป็นข้างซ้ายไม่ได้". 📋
8. **Bluetooth off/on:**
   - Connect both correctly again.
   - Turn Bluetooth off in quick settings. Expect the card
     "บลูทูธปิดอยู่ กรุณาเปิดบลูทูธ" and both feet blocked.
   - Turn it on again. Both should reconnect by themselves (MTU 247). 📋
9. Tell me when you're done. I'll stop the serial logs and read the
   connection interval the Note 10 granted (`[ble] conn N: interval …`)
   for BACKLOG 25.

**Pass:** step 5 meets every expectation for both feet. Steps 6–8 behave
as described. If anything differs, the log is what I need.

## Leftovers (BACKLOG)

- **20:** checks 1 and 2 implemented; look-ahead deliberately not
  implemented (status added).
- **23:** the app re-reads calibration on the bit1 falling edge; the
  contract question is still open.
- **25:** interval part resolved. The Note 10 grants 11.25 ms after the
  HIGH request. S4 still measures the ±10 ms cross-foot timing.
- **26 (new):** Android ≤ 11 location path untested; `permission_handler`
  pin until compileSdk 37 / a newer AGP.
- **27 (new, S4):** the first packet after START can be dropped as "before
  START" when Android delivers it before the write ack, and the gap counter
  misses it. Seen once on the Note 10 (6b). Two fix options are in the item.

## Decisions needed

None. Optional: replace the right board's USB cable (see Observations)
before S3B, where the laptop logs while the phone streams.

## Next session

S3B (per `docs/SESSIONS.md`): laptop and phone connected at the same time.

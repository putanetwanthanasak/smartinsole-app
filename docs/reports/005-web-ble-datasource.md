# 005 — WebBleDataSource: a real IDataSource backed by Web Bluetooth

Closes the loop this app's architecture has been built around for several
passes (`IDataSource` → `DeviceManager` → screens) without ever actually
carrying live data. `MockDataSource` is untouched and remains the default;
this adds a second, selectable implementation.

**Scope respected:** no IndexedDB, no research capture mode, no Capacitor,
no Firebase. `DeviceManager`'s throttling and the raw path (report 004) are
unchanged beyond feeding them real data. None of the five screens' rendering
was touched.

---

## New files

| File | Role |
| --- | --- |
| `src/ts/data/webBluetooth.d.ts` | Minimal ambient Web Bluetooth types — TypeScript's default DOM lib doesn't include this API (not yet a W3C Recommendation). Scoped to exactly what's used, not the full spec surface — see "why not @types/web-bluetooth" below. |
| `src/ts/data/bleProtocol.ts` | Every UUID, opcode, and packet-layout constant, copied from `docs/BLE-INTERFACE.md`. Pure data, no logic. |
| `src/ts/data/blePacketParser.ts` | Pure parsing/scaling functions — bytes in, structures out, no GATT, no state, no side effects. |
| `src/ts/data/WebBleDataSource.ts` | The `IDataSource` implementation — GATT lifecycle, subscriptions, error handling. Calls into the parser; owns nothing about wire-format details itself. |
| `src/ts/devBlePanel.ts` | Dev-only connect UI, mounted by `main.ts` outside the five screens. See "two-device connect flow" below. |

## Changed files

- `src/ts/data/DeviceManager.ts` — `usingWebBle` (dev-only, `?ds=ble`), `bleSources`, dev handle extended.
- `src/ts/main.ts` — skips boot-time `connectAll()` and mounts the dev panel when `usingWebBle` is true.
- `docs/BLE-INTERFACE.md` — "What's still open" updated with what implementing against it actually found.

---

## How the packet parser is structured, and where it lives

`blePacketParser.ts` is deliberately separated from `WebBleDataSource.ts`:
every function takes a `DataView` (or, for calibration, decoded text) and
returns a plain parsed structure or throws — no `BluetoothRemoteGATTServer`,
no connection state, no timers, nothing that requires a real device, a
simulator, or even a Web-Bluetooth-capable browser to exercise. The byte
offsets in it can be read and checked against `docs/BLE-INTERFACE.md`'s
tables directly, function by function, without needing hardware in the
loop.

`WebBleDataSource.ts` owns everything the parser doesn't: `requestDevice()`,
GATT connect/service/characteristic resolution, subscribing/unsubscribing
notifications, the control-write handshake (`SYNC_TIME`, `START_STREAM`),
reconnect logic, and turning parsed structures into the `SensorSample` /
`TempReading` / `DeviceStatus` shapes `IDataSource` promises. It calls
`blePacketParser.ts`'s functions; it does not duplicate any byte-offset
knowledge itself.

`bleProtocol.ts` sits underneath both — every UUID, opcode, and
byte-layout constant, matching CLAUDE.md Convention #6 ("never inline a
number that has a name") extended to the BLE wire format the same way
`constants.ts` already does it for clinical thresholds.

**Why a hand-written `webBluetooth.d.ts` instead of `@types/web-bluetooth`:**
no new runtime dependency either way (types never ship to the bundle), but
a hand-written file scoped to the dozen calls this adapter actually makes
is smaller to review and audit than pulling in the full spec surface — the
same reasoning `icons.ts` already applies to Lucide's icon barrel. If a
future pass needs more of the API, extend this file rather than add the
package.

---

## How the two-device connect flow works

Web Bluetooth's `requestDevice()` requires a real user gesture, and two
insoles means two separate gestures — no way around it, per the brief. This
is fundamentally incompatible with `main.ts`'s existing boot-time
`deviceManager.connectAll()` (called from `DOMContentLoaded`, not a
gesture) — calling `requestDevice()` from there would fail immediately with
a `SecurityError`.

**Resolution:** `DeviceManager.ts` exports `usingWebBle` — true only when
the app is loaded in dev mode with `?ds=ble` in the URL. When true,
`main.ts` skips `connectAll()` entirely and instead mounts
`devBlePanel.ts` — a small, clearly-marked, non-screen UI element appended
directly to `<body>`, outside `#view` and outside `.device-frame`, so it's
never confused with product UI and survives every route change. It exposes
independent **Connect**, **Disconnect**, and **Forget device** buttons per
side, each a real click (real user gesture) that calls
`deviceManager.connect('left')` / `connect('right')` — exercising the
existing per-side `ConnectionState` machinery exactly as the four wired
screens already do, just from a debug trigger instead of Settings (which
this pass doesn't touch).

**Reconnect optimization, not required by the brief but worth stating
explicitly:** only `requestDevice()` needs a gesture; `BluetoothDevice.gatt
.connect()` on an already-granted device does not. `WebBleDataSource` keeps
its `BluetoothDevice` reference across a normal `disconnect()`, so
reconnecting the SAME device after an intentional disconnect or a
transient error does not re-prompt the picker — only the very first pairing
of each physical device does. `forgetDevice()` (wired to the panel's
"Forget device" button) discards that reference on demand, and is called
automatically on a side-mismatch (see below), so the wrong device is never
silently reconnected to.

**Not wired to any of the five screens this pass** — a real "Connect Left
Insole" button belongs in Settings' existing "Connected devices" section,
which is screen-rendering work explicitly out of scope here. The data-layer
piece (`DeviceManager.connect(side)` working correctly against a real
`IDataSource`) is what this pass delivers; wiring a product UI to it is
future work.

---

## What happens on each failure mode

| Failure | Behavior |
| --- | --- |
| **User cancels the device picker** | `requestDevice()` rejects with `NotFoundError`; `connect()` catches specifically that, sets state back to `'disconnected'`, and resolves normally — not an error, per the brief. Confirmed live (see Verify) — a real cancellation returned the source to `disconnected` with no thrown error. |
| **START_STREAM write fails** | Thrown from inside `connect()`'s try block, caught by the outer catch, which tears down the GATT connection, sets state `'error'`, and re-throws — `connect()`'s promise rejects. A device that "looks connected and sends no data" cannot result from this path; either the write succeeds and streaming starts, or connect() fails outright. |
| **Sensor packet arrives truncated** (shorter than its own header's `count` implies) | Logged distinctly (`console.error`, tagged, includes seq/expected/actual byte counts), counted in `truncatedPackets`, and the packet's samples are NOT parsed or emitted — a truncated packet's bytes can't be trusted, so nothing is guessed from them. One truncated packet does not fail the connection; `CONSECUTIVE_TRUNCATION_ERROR_THRESHOLD` (5) in a row escalates the side to `'error'`, on the reasoning that a single glitch and a persistent link problem are different failure modes deserving different responses. |
| **Calibration read fails, or the JSON is malformed/wrong shape** | `parseCalibrationJSON` throws with a specific reason (invalid JSON, missing field, wrong channel count); `connect()`'s catch tears down and rejects. No default curve, ever — a bad calibration blob is a hard connect failure per the brief, not a fallback to plausible-looking wrong numbers. |
| **Side mismatch** (`foot_side` in the initial Device Status read doesn't match the slot) | `BleSideMismatchError` thrown before calibration is even read (fail fast); GATT torn down; the device reference is explicitly forgotten (`forgetDevice()`) so the next `connect()` attempt prompts a fresh picker rather than silently reconnecting to the wrong physical device. Also checked on every SUBSEQUENT status notification, not just at connect — if a device's reported side ever changes mid-connection, the source disconnects rather than keep emitting under a slot it can no longer trust. |
| **Unexpected GATT disconnect** (device powered off, out of range) | Distinguished from an app-initiated `disconnect()` via an `intentionalDisconnect` flag; an unexpected drop tears down and sets state `'error'` (not `'disconnected'`) — the UI's existing error/offline tone distinction (already present in `home.ts`'s connection strip) can tell the two apart. |
| **Browser has no Web Bluetooth support** | `connect()` checks `navigator.bluetooth` up front, sets state `'error'`, and rejects with a clear message before attempting anything. |

---

## Time sync — one place the contract's procedure needed a decision

The contract's offset formula (`offset = unix_time_at_send −
most_recently_received_t_ms`) needs a previously-received device timestamp
to subtract from — but the procedure's own step 1 says to send `SYNC_TIME`
"on successful connect," which in this implementation happens before any
sensor/temp packet has arrived (subscriptions are set up, then `SYNC_TIME`
is sent, then `START_STREAM`). The very first sync call therefore has
nothing to compute an offset from.

**Decision:** the first sync write still happens exactly where the contract
says (before `START_STREAM`), but computing an offset from it is a no-op
until data exists. The moment the first sensor or temperature packet
arrives, `WebBleDataSource` opportunistically computes an offset from
*that packet's own arrival time* (`Date.now() - deviceMs`, the same
arrival-based idea the contract's formula itself uses, just triggered by
data instead of the sync write). Every sample before that first packet uses
pure arrival time as `tUnixMs` (honest, not device-trusting — Convention #5
in `CLAUDE.md` is about exactly this). In practice this gap is at most one
packet. The scheduled 5-minute resync afterward always has data to work
from and follows the contract's procedure exactly.

`DeviceManager.lastSampleAt` is unaffected either way — it already always
uses arrival time regardless of any of this, unchanged, per the brief.

---

## What in `docs/BLE-INTERFACE.md` turned out to be wrong or incomplete

Updated directly in that file's "What's still open" section (not just here)
so it stays the first thing the next reader sees:

1. **New gap: `offset_adc`'s application is unspecified.** The calibration
   blob schema includes a per-channel `offset_adc`, but the FSR scaling
   formula given (`V_out → R_fsr → F_newton → P_kPa`) never shows where it
   enters the calculation. Rather than invent an interpretation (e.g.
   subtracting it from raw ADC before computing `V_out` — the common
   convention for a field named "offset," but not confirmed), `adcToKpa()`
   implements the formula exactly as documented and does not use
   `offsetAdc` — the brief was explicit: "do not invent any value that
   should come from those [docs]." `offsetAdc` is still parsed and carried
   on `CalibrationChannel` so it isn't silently dropped from the type, just
   not consumed yet. Needs an answer from whoever owns this part of the
   contract.
2. **Narrowed, not resolved: calibration blob framing.** The doc already
   flagged this as open; this pass's answer is "trust Web Bluetooth's
   standard GATT long-read behavior, no manual chunking" — reasonable, but
   unverified against the real simulator's actual characteristic, since I
   don't have access to it this session.
3. **Resolved (as far as this implementation goes): `SimulatorDataSource`.**
   `WebBleDataSource` pointed at the simulator IS this app's answer — one
   adapter, since the simulator and real hardware are electrically
   identical BLE peripherals from the app's side of the link. Not confirmed
   with the hardware/contract team, just the position taken; worth a nod of
   confirmation from whoever owns that part of the contract too.

Nothing else in the document needed correcting — every UUID, opcode, byte
offset, and scaling factor used matches what's written there exactly.

---

## Verify — what I could and could not actually run

**I do not have the ESP32 simulator or a USB dongle.** Everything below
that requires either is explicitly left open, per the brief, rather than
reasoned to a claimed result.

| Check | Status |
| --- | --- |
| Connect to the simulator, write START_STREAM, receive and parse packets | **NOT RUN** — no simulator available. `npm run build` typechecks the parser and adapter cleanly, and the packet-layout offsets were written directly against `docs/BLE-INTERFACE.md`'s tables, but nothing has parsed a byte that came from a real device. |
| Confirm 8 samples emitted per packet, timestamps 20 ms apart | **NOT RUN** — same reason. The unpacking loop (`for (let i = 0; i < parsed.samples.length; i++)`, `deviceMs = t0Ms + i*20`) is straightforward to read and matches the contract, but "I read the code and it looks right" is not the same claim as "I ran it against a real 8-sample packet," and this report says which one this is. |
| Confirm the calibration read and the kPa conversion against known raw values | **NOT RUN** — no real calibration blob or known raw ADC values available to check `adcToKpa()`'s output against. This is also the check most likely to surface the `offset_adc` gap above as a real numeric discrepancy, not just a documentation gap. |
| Disconnect and reconnect cleanly; connect one side only; connect both | **PARTIALLY RUN.** The Chrome extension was available this session, and — unplanned, but real — this machine has an actual Bluetooth adapter (`navigator.bluetooth.getAvailability()` returned `true`). Loading `?ds=ble` correctly skipped the boot-time auto-connect and mounted the dev panel; the app itself correctly fell back to every existing "no data" state (offline connection strip, `0/5 Not worn` status, heatmap's per-foot "No data" overlay) with zero screen-rendering changes needed, confirming the existing no-data machinery generalizes to "no real source connected yet" exactly as designed. Clicking "Connect" on the left slot triggered a real `requestDevice()` call (a native OS device chooser, invisible to browser automation); cancelling it (Escape) returned the source cleanly to `'disconnected'` with no thrown error or console exception — a genuine, unscripted confirmation of the cancellation-handling path in §"What happens on each failure mode" above. What was NOT and could not be tested this way: actually selecting a real device from that picker, since none was advertising (no simulator running) — so the calibration-read, START_STREAM, packet-parsing, and reconnect-to-a-real-device paths remain unverified, only the pre-pairing and cancellation paths were exercised for real. |
| `npm run build` clean, all five routes still work on mock | **RUN, PASSED.** Clean build both before and after (bundle hash unchanged — see "production bundle" note below). All five routes screenshotted on mock with the BLE toggle absent, rendering identically to before this pass; no console errors traceable to the app. |

**Production bundle note, found while checking this:** `usingWebBle` is
gated on `import.meta.env.DEV`, which Vite statically replaces at build
time. In a production build this makes the entire `if` branch — and every
BLE module it pulls in — dead code, which Rollup eliminates outright:
`dist/assets/index-*.js`'s hash and size are byte-identical before and
after this pass, and a `grep` for `WebBleDataSource`/`requestDevice` in the
built bundle returns zero hits. The BLE stack costs nothing in the shipped
app unless a dev build explicitly opts in — not something I set out to
prove, but a genuinely nice property this pass's gating produced.

---

## Not fixed or done in this pass, on purpose

- No product UI for connecting real hardware (Settings' "Connected devices"
  section) — screen rendering is out of scope; the dev panel is a stand-in
  for testing the data layer only.
- `offset_adc` unused in the kPa conversion — flagged, not guessed at.
- Calibration blob chunking — trusted to standard GATT behavior, not
  independently verified.
- Everything explicitly out of scope per the brief: IndexedDB, research
  capture mode, Capacitor, Firebase.

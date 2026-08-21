# BLE Hardware Test Checklist

Run this at the machine with the ESP32 simulator and USB dongle. No Claude
Code involvement needed — every step is something to type or click
yourself. Where a check's "correct" value depends on the contract rather
than on what this app's code happens to produce, that's stated explicitly,
derived from `docs/DATA-CONTRACT.md` / `docs/BLE-INTERFACE.md` directly —
a checklist that only confirms the code agrees with itself is worthless,
and none of the numbers below come from that.

## Setup

1. `npm run dev` in the project root.
2. Chrome or Edge (Web Bluetooth doesn't exist in Firefox/Safari). Open
   `http://localhost:5173/?ds=ble#/home` — the `?ds=ble` is required, it's
   the dev-only switch away from the mock data source.
3. Confirm a black bar with green monospace text appears fixed to the
   bottom of the page: **"BLE DEV PANEL (?ds=ble) — not part of the app
   UI"**, with a `left` row and a `right` row, each showing Connect /
   Disconnect / Forget device buttons, `state=disconnected`, and a
   diagnostics line (`pkts=0 dropped=0 truncated=0 unparseable=0 seq=—
   offset=—ms cal=—`).
   - **If this bar doesn't appear:** the `?ds=ble` query param didn't take
     — check the URL bar still has it after the page loads (the app doesn't
     drop it, but confirm), and that you're running `npm run dev`, not
     `npm run preview`/a production build (the BLE code doesn't exist in a
     production build at all — see report 005's "production bundle" note).
4. Open DevTools (F12) → Console tab. Turn on "Preserve log" (small
   checkbox near the top of the Console panel) so nothing is lost if a
   check causes a page reload. Keep this open for every check below.
5. Make sure the ESP32 simulator is powered on and advertising, and the
   USB dongle is plugged into the machine running Chrome (not a different
   machine — Web Bluetooth uses the browser's own host adapter).

---

## Check 1 — Connect the left side

**Do:** Click **Connect** in the `left` row. Chrome shows a native device
picker — select the simulator (it advertises as `SMARTINSOLE-L`).

**Correct looks like:** Within a couple seconds, the `left` row shows
`state=connected`, and the diagnostics line starts counting up
(`pkts=` increasing every ~160 ms).

**If it fails:**
- Picker shows no devices at all → simulator isn't advertising, or the
  dongle isn't recognized by Chrome. Check the simulator's own serial
  log for an advertising/boot message; check Windows' Bluetooth settings
  recognizes the dongle.
- `state=error` right after picking the device → look in the console for a
  line tagged `[WebBleDataSource:left]`. Capture that exact line — it
  names which step failed (device status read, calibration read, or the
  `START_STREAM` write).
- Nothing happens after selecting the device (state stays `connecting`
  indefinitely) → capture the console as-is after ~15 seconds; this
  usually means a GATT operation is hanging, and which `console.error` (if
  any) appeared last tells you which one.

---

## Check 2 — 8 samples per packet, 20 ms apart

Not visible anywhere in the UI — read it from the console. The contract
fixes packets at 6.25 Hz, 8 samples each (`docs/BLE-INTERFACE.md` "Sensor
Stream packet"), so **50 samples/second** and **20 ms** between samples are
the numbers to check against — not anything this app computes.

**Do**, once `left` shows `state=connected`, paste into the console:

```js
let n = 0;
const stop = window.__insole.bleSources.left.onSample(() => n++);
setTimeout(() => { stop(); console.log('samples in 5s:', n, '≈ Hz:', (n/5).toFixed(1)); }, 5000);
```

**Correct looks like:** `samples in 5s: ~250 ≈ Hz: ~50.0` (any value
roughly 240–260 is fine — packet timing isn't perfectly metronomic).

**What a failure means:** if you see roughly **31** samples in 5 seconds
(`≈ Hz: ~6.2`), only one `SensorSample` is being emitted per packet instead
of eight — the exact bug hard requirement #3 in the original implementation
brief exists to prevent. That's a real bug in `WebBleDataSource.ts`'s
unpacking loop, not a timing artifact — capture this number and file it.

**Do**, for the spacing itself, paste:

```js
let prevT = null, i = 0;
const stop2 = window.__insole.bleSources.left.onSample(s => {
  const d = prevT === null ? null : s.tUnixMs - prevT;
  console.log(i++, 'Δ=' + d + 'ms');
  prevT = s.tUnixMs;
});
setTimeout(stop2, 2000);
```

**Correct looks like:** a repeating pattern of **seven** steps of `Δ=20ms`
(small deviation, e.g. 18–22, is fine — it comes from `t0_ms`'s own
resolution, not from BLE jitter — see the note below), followed by **one**
larger jump of roughly 140–180ms, then the pattern repeats. That larger jump
is the gap between one packet's last sample and the next packet's first —
packets arrive every ~160ms (1000/6.25), 8 samples span 140ms
(7 × 20ms) of that packet, so a ~20–40ms idle gap between packets is
expected and correct, not a bug.

*Why the ~20ms steps are this precise regardless of real BLE timing:* each
sample's `tUnixMs` is computed as `t0_ms + i×20 + offset` — a straight line
through the header's own declared timestamp, not measured from when the
notification actually arrived. So this check isn't really testing BLE
timing precision; it's testing that the unpacking loop reads `t0_ms` and
`count` correctly and computes each of the 8 samples' timestamps from them
— which is exactly what hard requirement #3 needed confirmed.

---

## Check 3 — Calibration read succeeded and looks right

**Do:**

```js
window.__insole.bleSources.left.getDiagnostics().calibration
```

**Correct looks like** (per `docs/DATA-CONTRACT.md` §5.1's schema — this is
what the contract defines, not what the parser happens to produce):

- `deviceId`: a non-empty string.
- `rPulldownOhm`, `sensorAreaM2`: both numbers, both greater than 0.
- `channels`: an array of **exactly 6** entries. Each entry has numeric
  `index`, `a`, `b`, `offsetAdc`. The six `index` values, taken together,
  must be exactly `{0, 1, 2, 3, 4, 5}` — one each, no duplicates, no gaps
  (per `docs/BLE-INTERFACE.md`'s FSR channel table: 0=hallux, 1=1st
  metatarsal, 2=3rd metatarsal, 3=5th metatarsal, 4=midfoot, 5=heel).

**If it fails:**
- `calibration` is `null` even though `state=connected` → shouldn't be
  possible (a failed calibration read fails `connect()` outright, so the
  side would show `state=error`, not `connected` — see Check 1). If you
  somehow see this combination, that's itself a bug — capture the full
  console output from the connect attempt.
- `state=error` right after connecting → look for a console line starting
  `Calibration blob is not valid JSON`, `Calibration blob missing...`, or
  `Calibration blob has N channels, expected 6` — the exact message tells
  you what's wrong with the blob itself (capture it verbatim; it's
  diagnosable directly, no further digging needed).

---

## Check 4 — kPa values are plausible and match the standalone test page

The standalone test page is already verified correct against this same
simulator — so if the two disagree, **the fault is this app's parser, not
the device.**

**Do:** With `left` connected, open the standalone test page in a second
window/tab, pointed at the same simulator (or note that it's already
connected there if it holds a persistent connection — BLE allows only one
active GATT connection per device at a time, so you may need to disconnect
one side to let the other connect if the simulator doesn't support multiple
simultaneous links). Watch this app's Home screen heatmap (`#/home`, not
the dev panel) and the standalone page side by side while pressing/
releasing the physical FSR sensors on the insole.

**Correct looks like:**
- **At rest (no load on any sensor):** every zone in this app's heatmap
  should read a low kPa value, close to 0 — **specifically because of the
  `offset_adc` fix in this pass**: the zero-point subtraction means a
  resting sensor's ADC reading (which IS the calibration blob's own
  recorded zero-point) should now compute to a near-zero kPa, not a
  "phantom" nonzero baseline. If you have numbers captured from before this
  fix, they'll read noticeably higher than what you see now — that's
  expected and is the fix working, not a new discrepancy.
- **Under load:** both this app and the standalone page should show
  elevated readings for the zone under pressure, broadly proportional to
  each other (press harder → both read higher). Exact numbers won't be
  identical between the two — they're sampling at different instants — but
  the *shape* (which zone is highest, roughly how much higher than
  baseline) should match.

**If it fails:** a resting reading that's still tens of kPa (not near-zero)
suggests the offset subtraction isn't taking effect — check
`window.__insole.bleSources.left.getDiagnostics().calibration.channels`
and confirm `offsetAdc` values are actually nonzero/plausible for your
hardware (if the blob's own `offset_adc` values are all 0, there's nothing
for the fix to subtract — that's a calibration-data issue, not a parser
bug). A value wildly different from the standalone page under the same
load (order-of-magnitude off, or one side positive and the other
effectively zero) is a scaling or byte-offset bug — capture: the exact kPa
this app shows, the exact reading the standalone page shows for the same
moment, and which zone.

---

## Check 5 — Sequence gaps / dropped packets

**Do:**

```js
window.__insole.bleSources.left.getDiagnostics()
```

Look at `totalPackets` and `droppedPackets`.

**Correct looks like:** `droppedPackets` at or very close to `0` — over a
clean, close-range BLE link, packet loss should be rare. As a sanity check
on `totalPackets` itself: after being connected for *N* seconds,
`totalPackets` should be roughly `N × 6.25` (the contract's packet rate) —
e.g. ~188 after 30 seconds. If `totalPackets` is far below that even with
`droppedPackets=0`, packets aren't arriving at the expected rate at all
(different problem from packet loss — check the notification subscription
succeeded, not the seq-gap math).

**What an unhealthy number means:** `droppedPackets` reaching more than a
few percent of `totalPackets` indicates real BLE packet loss (radio
interference, connection interval issues, distance from the dongle) — not
a parser bug, since seq tracking is simple wraparound arithmetic on a
16-bit counter straight off the wire. Capture both numbers, roughly how
long the connection had been up, and whether anything in the environment
could cause RF interference (other BLE/WiFi devices very close by).

---

## Check 6 — Truncation (silent MTU negotiation failure)

Web Bluetooth gives no direct way to read the negotiated MTU from
JavaScript — this diagnostic count is the only way this app can detect the
fallback path.

**Do:**

```js
window.__insole.bleSources.left.getDiagnostics()
```

Look at `truncatedPackets` and `unparseablePackets`.

**Correct looks like:** both `0`. MTU 247 easily fits a 200-byte sensor
packet (247 − 3 bytes of ATT overhead = 244 usable, per the standard ATT
protocol), so under normal negotiation there's no reason for a truncated
packet to ever occur.

**If `truncatedPackets` is nonzero:** MTU negotiation likely didn't reach
247 and packets are arriving shorter than their own header's `count` field
implies (this is the contract's own documented fallback — see
`docs/BLE-INTERFACE.md`'s Connection Parameters table). The console will
have a line like:

```
[WebBleDataSource:left] TRUNCATED sensor packet: seq=1234 expected 200B for count=8, got 104B
```

Capture that exact line — the expected-vs-actual byte counts tell you
precisely how much data is missing per packet. Also check
`getDiagnostics().droppedPackets` at the same time — heavy truncation with
zero dropped-seq gaps means packets ARE all arriving, just short.

---

## Check 7 — Disconnect, reconnect, confirm no second device picker

**Do:** With `left` connected, click **Disconnect**. Then click **Connect**
again (same button, same row — do NOT click "Forget device" in between).

**Correct looks like:** No device picker appears the second time —
`state` goes straight from `disconnected` → `connecting` → `connected`
without Chrome asking you to choose a device again.

**If a picker appears anyway:** that means the previously-granted device
reference wasn't retained across the disconnect — capture whether you
clicked "Forget device" at any point before this (which correctly WOULD
cause a picker to reappear — that's not a bug, that's what the button is
for) versus a plain Disconnect → Connect cycle with no Forget in between
(which would be a real bug in the reconnect path).

---

## Check 8 — Side mismatch (connect `SMARTINSOLE-L` into the RIGHT slot)

The simulator advertises as `SMARTINSOLE-L` and reports `foot_side=0` in
its Device Status packet — connecting it into the `right` row's slot (which
expects `foot_side=1`) is a free, repeatable test of the mismatch-detection
path without needing a second physical device.

**Do:** Make sure `right` shows `state=disconnected` (disconnect it first
if needed). Click **Connect** in the `right` row and select the same
simulator from the picker.

**Correct looks like:**
- `right` ends up at `state=error`, NOT `state=connected`.
- The console shows a line from `[WebBleDataSource:right]` reading exactly:

  ```
  Connected device reports foot_side=0 (left), but was connected into the right slot.
  ```

- Click **Connect** on `right` again: the device picker should appear
  again (not a silent reconnect to the same wrong device) — this confirms
  the mismatch handler correctly forgot the device rather than leaving it
  cached for next time.

**If it fails:** if `right` instead shows `state=connected` with data
flowing, **stop and capture everything** — this is the exact failure hard
requirement warned about (a silently mislabelled side corrupts every
bilateral metric the app computes: ΔT, PAI, symmetry). Capture: the full
console log from the connect attempt, `getDiagnostics()` output for both
`left` and `right`, and whether the `left` slot was also connected to the
same physical device at the same time (BLE typically only allows one
active connection per device — if both slots show connected to what's
actually one physical simulator, that's worth noting on its own).

---

## What to capture on ANY failure, to make it diagnosable rather than "it didn't work"

1. **Which check number failed**, and the exact step within it.
2. **The full console output** for that check — copy-paste text, not a
   screenshot if you can help it (text is searchable/diffable). Everything
   tagged `[WebBleDataSource:left]` or `[WebBleDataSource:right]` is
   relevant; include a few lines before and after, not just the one that
   looks like the error.
3. **`getDiagnostics()` output for both sides**, captured right after the
   failure:
   ```js
   JSON.stringify({ left: window.__insole.bleSources.left.getDiagnostics(),
                     right: window.__insole.bleSources.right.getDiagnostics() }, null, 2)
   ```
4. **Whether it reproduces** — try the same check again once. "Happened
   once, then worked fine" and "happens every time" point at different
   kinds of bugs (transient RF/timing vs. a real logic error).
5. **Browser + OS**: Chrome/Edge version, Windows build, and whether you're
   using the USB dongle specifically or a different Bluetooth adapter.

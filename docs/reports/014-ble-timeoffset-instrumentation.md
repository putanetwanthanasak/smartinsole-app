# 014 — L/R offset gap: instance-sharing ruled out; live instrumentation added for the real cause

Follows report 013, whose "stale/leftover data" hypothesis is now ruled out
by the user's own clean single-take reproduction: one connect, one
calibration, one Start→Stop, one export — both sides individually correct
(50.0 Hz, correct intra-packet spacing per report 012), but a
**644,578 ms → 644,418 ms** gap between `L` and `R`'s `deviceTUnixMs`,
nearly constant (160 ms drift) across the whole 50 s take. Report 013's
fake-GATT reproduction only ever drove one `WebBleDataSource` instance at a
time and could not have caught a defect that only manifests with two
instances live concurrently — this report checks that specifically, then
adds live instrumentation for what report 013 couldn't reach without real
hardware.

## 1. Hypothesis 1 — shared/misattributed instance state: ruled out

Checked directly, no instrumentation needed for this part — it's a
structural question a reproduction can't answer more conclusively than
reading the actual construction and field declarations can.

**`bleSources` constructs two genuinely separate instances**
(`DeviceManager.ts`):

```ts
export const bleSources = usingWebBle
  ? { left: new WebBleDataSource('left'), right: new WebBleDataSource('right') }
  : null;
```

Two distinct `new WebBleDataSource(...)` expressions — two separate object
allocations, not the same reference stored twice under different keys.

**No `static` fields anywhere in the class** — `grep -n "static "
WebBleDataSource.ts` returns nothing. `timeOffsetMs`, `lastKnownDeviceMs`,
`resyncTimer`, and every other piece of per-connection state are plain
instance fields (`private fieldName: Type = ...;` inside the class body),
so each instance owns its own independent copy — there is no path for
`right.connect()` to touch anything belonging to `left`'s object.

**The notification handlers are arrow-function class fields**, not
`.bind(this)` calls or free functions:

```ts
private readonly onSensorNotify = (ev: Event): void =>
  this.handleSensorValue((ev.target as BluetoothRemoteGATTCharacteristic).value!);
```

An arrow function used as a class field initializer captures `this`
lexically at the point each instance is constructed — `left.onSensorNotify`
and `right.onSensorNotify` are two separate closures, each permanently bound
to its own instance. There is no mechanism here for one side's GATT
notification to be misrouted into the other side's handler.

**Conclusion: not this.** No shared state, no singleton reuse, no
cross-instance closure capture. The two sides' `timeOffsetMs` values are
computed completely independently, exactly as the architecture intends.

## 2. Hypothesis 2 — independent per-device uptime, correctly handled in principle

Each ESP32's `t0_ms` is presumably milliseconds since *its own* boot
(`millis()`-style), and the two physical boards very likely have very
different uptimes right now, given the debugging history (temp-quality fix,
calibration testing, possible reflashing) described in report 013. This is
fine *in principle* — `toUnixMs()`'s job is exactly to absorb an arbitrary,
independent per-device boot offset via each side's own `timeOffsetMs`,
computed at that side's own connect time from that side's own first packet.
Nothing about the design assumes the two devices share an epoch.

The failure mode that WOULD break this, which report 013 flagged and this
report is built to check: **if the very first packet used to anchor the
offset is not actually "fresh"** — i.e., not delivered at the moment it was
generated, but a stale or buffered notification from before this specific
connection's listener was really "live" — then `Date.now()` at anchor time
reflects real "now," but `lastKnownDeviceMs` reflects some earlier moment,
and the computed offset is wrong by roughly however stale that first
packet was. Whether this is possible depends on real Web Bluetooth/BLE
stack/peripheral-firmware behavior this app's code doesn't control and
that a synthetic fake-GATT layer — by construction, since I write every
packet's contents and timing myself — cannot expose. This needs real
hardware, which is why report 013 said so and why no third synthetic
attempt was made here.

## 3. Instrumentation added (temporary — remove once answered)

All new lines are tagged `[014-INSTRUMENT:...]` (distinct from this file's
existing `[WebBleDataSource:...]` error/warn tags) and marked `TEMPORARY —
docs/reports/014-*.md` at each call site, so they're trivial to find and
strip once the cause is confirmed. Dev-gated (`import.meta.env.DEV`), same
as every other diagnostic already in this file.

**Anchor establishment — sensor path** (`handleSensorValue`), logs the raw
device-clock value, the wall-clock instant used as "now," and the resulting
offset, exactly once per connection, right when `timeOffsetMs` transitions
from `null`:

```
[014-INSTRUMENT:<side>] SENSOR anchor established: raw t0_ms=<n>, lastKnownDeviceMs=<n>, Date.now()=<n>, timeOffsetMs=<n>
```

**Anchor establishment — temp path** (`handleTempValue`), same shape, for
the (less likely, since sensor packets arrive far more often) case where a
temperature packet wins the race to establish the anchor first:

```
[014-INSTRUMENT:<side>] TEMP anchor established: raw t_ms=<n>, Date.now()=<n>, timeOffsetMs=<n>
```

**Every resync attempt** (`syncTime`, both the connect-time call and every
periodic `RESYNC_INTERVAL_MS` tick) — logs whether it was a no-op (before
any packet has arrived) or an actual recompute, with the before/after
offset:

```
[014-INSTRUMENT:<side>] SYNC_TIME called but lastKnownDeviceMs is null — no-op (expected for the connect-time call made before any packet has arrived).
[014-INSTRUMENT:<side>] SYNC_TIME resync: lastKnownDeviceMs=<n>, Date.now()=<n>, previousOffset=<n>, newOffset=<n>
```

**First 5 packets' raw arrival cadence** (`handleSensorValue`), regardless
of anchor status — this is the one built specifically to test the
backlog-flush theory in §2: a genuine live 50 Hz stream should show
`raw t0_ms` advancing by ~160 ms per packet while arriving ~160 ms apart in
real time; a backlog flush would instead show several packets landing in a
tight real-time burst while `t0_ms` jumps by much more than 160 ms between
them:

```
[014-INSTRUMENT:<side>] packet #0: raw t0_ms=<n>, arrival Date.now()=<n>
[014-INSTRUMENT:<side>] packet #1: raw t0_ms=<n>, arrival Date.now()=<n>
... (through #4)
```

**Confirmed the instrumentation itself fires correctly** (smoke check only
— not a reproduction of the real defect, which needs real hardware; this
just proves the log lines exist, fire at the right moments, and read
sensibly, using the same fake-GATT harness as report 013):

```
[014-INSTRUMENT:left] SYNC_TIME called but lastKnownDeviceMs is null — no-op (expected for the connect-time call made before any packet has arrived).
[014-INSTRUMENT:left] packet #0: raw t0_ms=1000, arrival Date.now()=1787418429445
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=1000, lastKnownDeviceMs=1140, Date.now()=1787418429445, timeOffsetMs=1787418428305
[014-INSTRUMENT:left] packet #1: raw t0_ms=1160, arrival Date.now()=1787418429446
[014-INSTRUMENT:left] SYNC_TIME resync: lastKnownDeviceMs=1300, Date.now()=1787418429446, previousOffset=1787418428305, newOffset=1787418428146
```

## 4. What to run

1. `npm run build` (already confirmed clean on this branch), then
   `npm run dev`.
2. Open `http://localhost:5173/?ds=ble#/capture` in Chrome, DevTools console
   open, **before** connecting either side.
3. Connect LEFT via the dev BLE panel. Watch for the `packet #0`–`#4` and
   `SENSOR anchor established` lines for `left`.
4. Connect RIGHT the same way. Watch for the same lines for `right`.
5. Run the same clean take that produced this report's numbers (calibrate,
   one Start→Stop, export) so the instrumentation output corresponds
   exactly to a session you can also check against the exported CSV.
6. Paste back the full console output for both sides' anchor
   establishment and first-5-packets blocks (and any `SYNC_TIME resync`
   lines, if the take runs past `RESYNC_INTERVAL_MS`).

**What would confirm the backlog-flush theory:** `right`'s (or `left`'s)
first few `packet #N` lines showing `raw t0_ms` jumping by far more than
~160 ms between consecutive packets while their `Date.now()` values are
nearly identical (a burst) — and an anchor `timeOffsetMs` that, when you
compute `Date.now() - timeOffsetMs`, doesn't land near the wall-clock time
you actually pressed connect.

**What would point elsewhere:** clean ~160 ms-spaced packets from the very
first one, in which case the anchor itself was fine and whatever produces
the 644-second gap is happening somewhere this instrumentation doesn't
cover — worth saying so plainly rather than forcing the data to fit the
theory, and this report's instrumentation would need extending, not the
theory kept regardless.

## 5. Scope

`WebBleDataSource.ts` only: one new temporary field
(`debugPacketsSinceConnect`, reset in `resetPerConnectionState()`), five
new temporary `console.log` call sites, all clearly marked for removal.
No other file touched, no fix applied — this report is instrumentation to
get the evidence report 013 couldn't reach, not a fix.

Branched from `work/csv-timestamp-granularity` (same base as report 013,
**not** stacked on top of report 013's branch) — both are sibling
investigations of the same file's timestamp territory, kept independent so
either can be reviewed or reconciled on its own.

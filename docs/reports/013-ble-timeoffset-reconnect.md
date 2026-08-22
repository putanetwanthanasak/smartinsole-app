# 013 — L/R `deviceTUnixMs` gap: investigated, not reproduced in `connect()`/reconnect logic

Investigates a critical finding from real-hardware data, distinct from report
012 (which fixed intra-packet spacing — confirmed working: "intra-packet
spacing is now perfect, all 20ms deltas, both sides"). This report is about
a **cross-side** gap in the same captured session: `R` and `L` samples'
`deviceTUnixMs` values ~537,788 ms (~9 minutes) apart, which would make
`data_loader.py`'s 15 ms `merge_asof` alignment drop the entire session (zero
pairs within tolerance anywhere).

**Bottom line up front: I could not reproduce the suspected defect.** I
traced and tested the exact mechanism the hypothesis names —
`connect()`/`resetPerConnectionState()`/`syncTime()`'s handling of
`timeOffsetMs` across a reconnect — via three distinct repro scenarios, all
matching or exceeding what was asked, and all three show the current code
re-anchoring correctly, not carrying a stale offset. I have not applied a
fix to that logic, because I could not show it is broken. What I did add:
a dev-only diagnostic (`OFFSET_JUMP_WARN_MS`) that will surface a real
discontinuity immediately in the console the next time this is tested
against actual hardware, rather than only being discoverable after export
by hand — see §4. I'm also offering my best alternative explanation for
the observed gap, given the evidence — see §5.

## 1. What the hypothesis specifically claims, and what the code actually does

The hypothesis: `timeOffsetMs` is established once on first-ever packet and
never reset on reconnect, so a side reconnected minutes after the other
carries a stale, minutes-old anchor.

Reading `WebBleDataSource.ts`'s `connect()`:

```ts
async connect(): Promise<void> {
  if (this.state === 'connected' || this.state === 'connecting') return;
  ...
  this.setState('connecting');
  this.resetPerConnectionState();   // <-- unconditional, every connect() call
  try {
    if (!this.device) { /* requestDevice() — only on first-ever pairing */ }
    ...
```

`resetPerConnectionState()` (called here, before any GATT work, regardless
of whether this is a fresh pairing or a reconnect to an already-known
`this.device`):

```ts
private resetPerConnectionState(): void {
  this.timeOffsetMs = null;
  this.lastKnownDeviceMs = null;
  ...
}
```

Both fields the offset depends on ARE nulled on every `connect()` call,
unconditionally — including reconnects. The very next packet re-establishes
a fresh offset (`handleSensorValue`/`handleTempValue`: `if
(this.timeOffsetMs === null) this.timeOffsetMs = Date.now() -
this.lastKnownDeviceMs;`), anchored to whatever "now" actually is at
reconnect time. As written, this should already prevent exactly the failure
mode described. That reading alone isn't proof against an async-ordering
subtlety only visible at runtime, so I built and ran the reproduction
requested rather than stop at the read.

## 2. Reproduction — three scenarios, real code, no hardware available

No physical BLE adapter or ESP32 simulator is reachable from this
environment, so this is not literally "reconnect to your simulator" — it's
the closest available substitute: the real, unmodified `connect()` /
`disconnect()` / `resetPerConnectionState()` / `syncTime()` /
`handleUnexpectedDisconnect()` driven end-to-end against a fake Web
Bluetooth GATT layer (built for this report — fake `characteristic`/
`service`/`gatt`/`device` objects implementing just the methods
`WebBleDataSource` actually calls: `getCharacteristic`, `readValue`,
`startNotifications`, `writeValueWithResponse`, `characteristicvaluechanged`
notifications, `gattserverdisconnected`). `Date.now` is monkey-patched to
simulate elapsed real time cheaply (no literal multi-minute sleep) — this
is the only thing about ambient state altered; the class's own code is
untouched except the same two mechanical, disclosed test-only patches used
for report 012's verification (`.js`→`.ts` import extensions,
`import.meta.env.DEV` → a global test flag, since plain Node has no Vite
env injection).

**Scenario A — same instance: connect, disconnect, wait 9 min, reconnect**
(the literal case the hypothesis names):

```
first packet: real now=1787417146010, sample.tUnixMs=1787417146010, diff=0ms
post-reconnect packet: real now=1787417686011, sample.tUnixMs=1787417686010, diff=1ms
=> gap between "now" and reconnected sample's tUnixMs: 1ms (FRESH — no staleness)
```

**Scenario B — your exact suggested repro: left connects, 9 minutes pass,
right connects fresh, both record "concurrently"**:

```
real now=1787417686011
left  sample tUnixMs=1787417686171, diff from now=-160ms
right sample tUnixMs=1787417686011, diff from now=0ms
=> L/R gap: 160ms (TIGHT — no cross-side staleness)
```

(The 160 ms here is an artifact of the test's own synthetic packet timing
choice, not a defect — negligible next to the reported 537,788 ms.)

**Scenario C — a genuinely different code path: an *unexpected* disconnect**
(native `gattserverdisconnected` event, exercising `handleUnexpectedDisconnect()`,
not `disconnect()`), **then reconnect**:

```
[WebBleDataSource:left] unexpected GATT disconnect
post-reconnect packet: real now=1787417686012, sample.tUnixMs=1787417686012, diff=0ms
=> gap: 0ms (FRESH — no staleness)
```

All three: gap after reconnect is single-digit milliseconds, not minutes.
The current reconnect/offset lifecycle re-anchors correctly in every path
tested, including the one the hypothesis specifically named.

## 3. Answering the three specific checks

- **Is `timeOffsetMs` reset inside `connect()`/`resetPerConnectionState()`
  on every new connection, or only computed lazily on first-ever packet?**
  Reset on every `connect()` call, unconditionally (§1) — confirmed by
  direct reading and by Scenario A/C reproducing a clean reconnect with no
  staleness.
- **Does `SYNC_TIME` actually get re-sent and re-anchor the offset on every
  `connect()`, not just the first?** Yes — `await this.syncTime();` runs
  inside `connect()`'s main sequence every time, not gated on any
  "first connection ever" flag. (It's a no-op the moment it's called, by
  design — `lastKnownDeviceMs` is null then — but the *real* re-anchor
  happens one step later, from the first post-reconnect packet, which is
  what Scenarios A/C exercise.)
- **Is `RESYNC_INTERVAL_MS` correctly re-running for a connection that's
  been up long enough, or could a stale timer reference survive reconnect?**
  `teardownGatt()` (called from both `disconnect()` and
  `handleUnexpectedDisconnect()`) clears `resyncTimer` before any
  subsequent `connect()` creates a new one — no code path skips this. Not
  independently stress-tested here (that would require literally waiting
  out `RESYNC_INTERVAL_MS` or faking Node's timer queue, not just
  `Date.now` — see §6), but nothing in the teardown/setup sequence gives a
  stale timer a way to survive a reconnect.

## 4. What I added instead of a speculative fix: an observability hook

I'm not confident enough — given the reproduction above — that this is an
app-level `connect()`/offset-lifecycle bug to change that logic without
evidence it's actually broken. Changing correct-looking code to "fix" an
unconfirmed defect risks masking whatever the real cause is and adds
complexity for nothing. Instead, `WebBleDataSource.syncTime()` now warns
(dev-only) when a resync recomputes `timeOffsetMs` more than
`OFFSET_JUMP_WARN_MS` (1000 ms) away from its own immediately-previous
value:

```ts
const newOffset = sendUnixMs - this.lastKnownDeviceMs;
if (import.meta.env.DEV && this.timeOffsetMs !== null) {
  const jump = Math.abs(newOffset - this.timeOffsetMs);
  if (jump > OFFSET_JUMP_WARN_MS) {
    console.warn(`[WebBleDataSource:${this.side}] clock offset jumped ${jump}ms on resync ...`);
  }
}
this.timeOffsetMs = newOffset;
```

1000 ms is chosen because ordinary crystal drift is ppm-level (a bad
100 ppm crystal drifts ~8.6 s/day — nowhere near 1 s over one
`RESYNC_INTERVAL_MS`), so anything past that threshold means something
discontinuous happened, not routine timekeeping noise. Verified this fires
correctly and only when it should:

```
--- calling syncTime() again immediately (normal case, tiny/no discontinuity) ---
warnings so far: 0
--- simulating a real 9-minute discontinuity, then resync ---
warnings after simulated jump: 1
  [WebBleDataSource:left] clock offset jumped 540000ms on resync (...) — not explainable by normal clock drift.
```

If whatever produced your 9-minute gap happens again on real hardware, this
will print to the console at the moment it happens, not require finding it
by hand in an exported CSV afterward.

## 5. Best alternative explanation, given the evidence

The reproduction rules out the hypothesized mechanism as tested. A
537,788 ms gap is also too large to be explained by "resync didn't happen"
alone even if it somehow failed silently every time — ordinary clock drift
over any realistic session length is milliseconds, not minutes, so an
un-resynced-but-*correctly-established* offset would still track real time
closely. A gap this size most likely means the two samples being compared
were **not actually captured at the same real moment** — most plausibly,
rows from two different pattern takes recorded at genuinely different
points across a debugging session that itself spanned many minutes of
connect/disconnect/calibration testing, rather than two rows the app
believed were concurrent. That would produce exactly this shape of number
(large, not a fixed hardware quantity) with no code defect anywhere.

**How to tell the two apart on your next real-hardware pass:** do one
clean session — connect both sides together, do a single Start→Stop take
with both feet moving, export, and compare `L`/`R` rows from *that one
take* specifically (not any other rows in the file). If the gap is still
large in that clean take, that's strong evidence of a genuine, still-unfound
defect and worth another investigation pass with the actual console open
(the new warning in §4 would fire immediately if it's the offset
mechanism). If the gap disappears, it confirms the rows compared this time
weren't from a concurrent take.

## 6. What I did not verify

- Real BLE hardware, at all — everything here is the real class's code
  driven against a fake GATT layer, not a real adapter or your ESP32
  simulator. Real BLE-specific failure modes (a `writeValueWithResponse`
  that silently fails or times out under real radio congestion, a
  `RESYNC_INTERVAL_MS` timer actually elapsing in a real long-lived
  session) are not exercised here — `Date.now` was faked, but Node's real
  timer queue was not, so the periodic resync's *timer actually firing*
  after 5 real minutes was not itself under test, only the `syncTime()`
  logic it calls (tested directly in §4).
- Whether the specific two rows you compared really came from the same
  take — I have no access to your actual exported file, only the two
  values you reported.

## 7. Scope

One diagnostic addition to `WebBleDataSource.ts` (`OFFSET_JUMP_WARN_MS`
constant + the warning in `syncTime()`). No other file touched. Branched
from `work/csv-timestamp-granularity` (report 012), since this investigation
concerns the `deviceTUnixMs` field that branch introduces and which is not
yet on `main`.

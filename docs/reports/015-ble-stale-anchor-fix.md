# 015 — Fix: stale first-packet anchor poisoning timeOffsetMs

Fixes the root cause reports 013/014 traced but couldn't reach without real
hardware: report 014's instrumentation caught it directly in the console
log, no further live testing needed to confirm the mechanism.

## 1. The mechanism, confirmed

```
[left]  packet #0: raw t0_ms=1163852, arrival Date.now()=1787418735506
[left]  packet #1: raw t0_ms=160
[right] packet #0: raw t0_ms=1163077, arrival Date.now()=1787418744326
[right] packet #1: raw t0_ms=160
```

Packet #0 on **both** sides carries a large `t0_ms` (~19.4 min), then
packet #1 drops to 160 and increments cleanly from there (packets #2–4
confirmed 320/480/640). Per `esp32-ble-simulator`'s `main.cpp`
(sibling repo, not this one): `START_STREAM` (`0x01`) sets
`gStreamStartMs = millis()` at the moment it's received, and
`t0 = millis() - gStreamStartMs` thereafter — i.e. `t0_ms` is
**stream-epoch-relative**, reset to ~0 on every `START_STREAM`. Packet #0's
large value is a notification already in flight from a **previous** stream
epoch (this test session's own history of many earlier connect/disconnect
cycles, per report 013), delivered right after this connection subscribes
— arriving before this connection's own `START_STREAM` had taken effect
on the firmware side.

**Note for the contract owner, not resolved here:** `docs/BLE-INTERFACE.md`
and `docs/DATA-CONTRACT.md` both describe `t0_ms`/`t_ms` as "ms since
device boot," not stream-epoch-relative. The simulator's actual behavior
contradicts that. This app's fix (below) doesn't depend on resolving which
is "correct" — detecting a rollback and re-anchoring from it is safe either
way — but the docs and the simulator disagree, and that's worth reconciling
independently of this report. Flagging per instruction, not touching
firmware or the contract docs from this pass.

**The bug:** `WebBleDataSource` anchored `timeOffsetMs` from whichever
sensor packet arrived first after subscribing
(`if (this.timeOffsetMs === null) this.timeOffsetMs = Date.now() -
lastKnownDeviceMs;`), with no check that this first packet actually
belonged to the current stream epoch. Working through the arithmetic on
packet #0 specifically: since it's self-referential (its own arrival time
anchors its own `t0`), packet #0's *own* samples actually get
roughly-correct, "now"-looking timestamps — it's every packet *after* it
that inherits the wrong offset and lands ~19 minutes in the past, which is
exactly why the reported gap is large, stable within one short take (fixed
at connect-time, no resync yet during a 50 s take against a 5-minute
resync interval), and differs between L and R (each board's leftover stale
`t0` value differs, matching the ~1163852 vs ~1163077 seen above).

## 2. The fix — two parts, both landed together

**Part 1 — don't trust the first packet blindly.** The very first sensor
packet of a connection is now held (`pendingFirstSensorPacket`), not
committed/emitted immediately. When the second packet arrives:

- If its `t0_ms` is **lower** than the held packet's — a rollback, which a
  genuine sensor stream's `t0` never does within one epoch — the held
  packet is **dropped outright**, never converted into a `SensorSample`,
  and a warning is logged. The second packet becomes the true first
  packet of this connection and anchors `timeOffsetMs` itself.
- Otherwise, the held packet really was the legitimate first packet and is
  committed normally, in order, ahead of the second.

**Part 2 — ongoing defense-in-depth.** Every packet after that first
decision is still checked against the last *committed* packet's `t0_ms`.
If a rollback is seen anywhere later in the stream, `timeOffsetMs` is
invalidated so the packet that revealed it re-anchors fresh — this can't
retroactively un-emit whatever packet immediately preceded it (already
committed by the time the rollback is visible; a real-time notification
handler has no lookahead once a packet has actually been processed), which
is exactly why part 1's one-packet buffer is scoped to connect-time only,
not applied to every packet indefinitely — buffering every packet would
add a permanent 160 ms latency to a sustained 50 Hz stream for a failure
mode the evidence only shows happening once, right at connect.

Applied identically (structurally) to the temperature path's own,
independent `t_ms` counter — a rollback there also invalidates the shared
`timeOffsetMs` — **without** the one-packet buffer: temp packets arrive far
less often, there's no direct evidence of the same stale-notification
issue on that characteristic, and the sensor path's own correction already
fixes the shared offset field well before a low-rate temp packet would
matter.

**Should the stale packet be emitted with a corrected offset instead of
dropped?** No — recommending drop, per the lean in the request. It's not
just a mislabeled timestamp: the packet's pressure/IMU *values* are
themselves stale sensor readings from a previous test session, not just
data that needs a timestamp fix. Keeping cosmetically-relabeled stale data
in a research-capture CSV is worse than a small, well-understood one-packet
(160 ms) gap at the very start of a connection — exactly the kind of subtle
corruption this project's capture-mode work already treats as unacceptable
elsewhere (see report 010 §6's bugs, CLAUDE.md's fabricated-bilateral-
reading rule).

**Firmware-side defense in depth (flagged, not implemented — separate
repo):** should `START_STREAM` handling flush/discard the in-flight
notification queue before `gStreamStartMs` resets, so a stale packet can't
race the reset at all? Worth considering for `esp32-ble-simulator`, but
that's `main.cpp` in a different repository — noted here per instruction,
not touched from this pass.

## 3. Code

`WebBleDataSource.ts`:

- New fields: `lastCommittedSensorT0Ms`, `lastTempTMs`,
  `pendingFirstSensorPacket` (holds both the parsed packet and its actual
  arrival time — see below), all reset in `resetPerConnectionState()`.
- `handleSensorValue()` now captures `arrivedAt = Date.now()` at the top
  (before any buffering decision), then implements the hold/drop/commit
  logic described above.
- New `commitSensorPacket(parsed, arrivedAt)` — the conversion/emit logic
  that used to be inline in `handleSensorValue()`, now a shared method so
  both the "commit the held packet" and "commit the current packet" paths
  use identical logic.
- `handleTempValue()` gets the equivalent rollback check against
  `lastTempTMs`, no buffering.

**A correctness subtlety caught and fixed during implementation, not left
in:** `commitSensorPacket()` must anchor using the *specific packet's own*
arrival time, not a fresh `Date.now()` call made at commit time. Because
the held first packet can be committed slightly later — during the second
packet's arrival, once the hold/drop decision is made — calling
`Date.now()` inside `commitSensorPacket()` itself would have anchored the
first packet ~160 ms late (one packet's worth), reintroducing a smaller
but real timing error on every subsequent sample. Fixed by threading the
packet's actual arrival timestamp through explicitly
(`pendingFirstSensorPacket.arrivedAt`) rather than recomputing "now" at
whatever later moment the packet happens to be processed.

**This branch is built on top of report 014's** (`work/ble-timeoffset-
instrumentation`), not as an independent sibling off report 012's branch
like 013/014 are to each other — the user's verification step needs both
the instrumentation *and* the fix present together (see §4: the anchor log
line has to fire correctly on the fix's own re-anchored packet, in the
same test run). Report 014's instrumentation is untouched and still
present, kept intentionally through this fix's real-hardware verification
round — the plan is to remove it once that's confirmed, not in this pass.

## 4. Verification

No physical hardware available in this environment — same constraint as
reports 013/014. Verified against the real, unmodified
`WebBleDataSource`/`blePacketParser` (copied only to fix `.js`→`.ts`
imports and the `import.meta.env.DEV` test-env patch, same as prior
reports) via the same fake-GATT harness, fed the **exact stale/rollback
pattern from the user's own instrumentation log** (`1163852 → 160 → 320 →
480 → 640`), not a new synthetic guess. Report 014's instrumentation is
active throughout, so this also directly confirms the request's own VERIFY step: the
anchor line firing on the correct (small) packet.

**Single side, stale packet #0 then a clean restart** — note the anchor
line firing on `t0_ms=160`, not `1163852`, and the drop warning appearing
first:

```
[014-INSTRUMENT:left] packet #0: raw t0_ms=1163852, arrival Date.now()=1787419860514
[014-INSTRUMENT:left] packet #1: raw t0_ms=160, arrival Date.now()=1787419860514
[WebBleDataSource:left] dropped stale first sensor packet (seq=1, t0_ms=1163852) — this connection's second packet's t0_ms=160 rolled back, meaning the held packet belonged to a previous stream epoch, not this connection. See docs/reports/015-*.md.
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=160, lastKnownDeviceMs=300, Date.now()=1787419860514, timeOffsetMs=1787419860214
SensorSamples emitted: 32 (expect 32 = 4 packets x 8, NOT 40 — packet #0 dropped)
first tUnixMs=1787419860374, last=1787419860994, spread=620ms (expect ~620ms for 4 packets of 8 samples @ 20ms)
last sample vs "now": -479ms (expect small, not ~19 minutes)
```

**Two sides, each with their own distinct stale packet #0** (`1163852` for
left, `644100` for right — different values, matching real per-board
uptime differences):

```
[WebBleDataSource:left] dropped stale first sensor packet (seq=1, t0_ms=1163852) — ...
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=160, ...
[WebBleDataSource:right] dropped stale first sensor packet (seq=1, t0_ms=644100) — ...
[014-INSTRUMENT:right] SENSOR anchor established: raw t0_ms=160, ...
left  first real sample tUnixMs=1787419860376
right first real sample tUnixMs=1787419860376
=> L/R gap: 0ms (TIGHT — fixed)
```

**Sanity — normal connection, no stale packet at all** (must behave
exactly as before the fix — anchor still fires on the genuinely-first
packet, nothing dropped):

```
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=1000, ...
SensorSamples emitted: 24 (expect 24 = 3 packets x 8, none dropped)
all consecutive deltas === 20ms: true
```

**Defense-in-depth — a rollback appearing mid-stream, not at connect:**

```
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=1000, ...
[WebBleDataSource:left] sensor t0_ms rolled back mid-stream (seq=1: 1320 -> 200) — re-anchoring timeOffsetMs from this packet.
[014-INSTRUMENT:left] SENSOR anchor established: raw t0_ms=200, lastKnownDeviceMs=340, ..., timeOffsetMs=1787419860178
SensorSamples emitted: 40 (expect 40 — mid-stream rollback re-anchors but cannot un-emit prior packets)
last sample vs "now": -159ms (expect small — re-anchored, not carrying the old offset)
```

All four match expectations: the stale packet is dropped and warned about
*before* the anchor line fires on the correct packet, the L/R gap collapses
from ~19 minutes to 0 ms, the no-stale-packet case is bit-for-bit
unaffected (still exactly 20 ms spacing, nothing dropped, anchor still
fires on the true first packet), and a hypothetical mid-stream rollback
re-anchors correctly (a second `SENSOR anchor established` line appears)
even though it can't retroactively un-emit the packet before it — matching
the documented, accepted limitation of that path.

Also: `npm run build` (`tsc --noEmit && vite build`) clean.

**Not yet verified: real hardware.** Re-run the exact same instrumented
test (both sides, console open) against your ESP32 simulator. Confirm the
`SENSOR anchor established` line now fires on the packet whose `t0_ms` is
small/near-zero — and, if a stale packet is present, that a
`dropped stale first sensor packet` warning appears immediately before it,
same order as the transcripts above. Then run a full clean take + export
and confirm the exported CSV's L/R `deviceTUnixMs` gap has dropped to tens
of milliseconds, not minutes.

## 5. Scope

`WebBleDataSource.ts` only. No other file touched.

Branched from `work/ble-timeoffset-instrumentation` (report 014) — stacked
on it, not a sibling off report 012 like 013/014 are to each other, since
this fix needs 014's instrumentation present for its own real-hardware
verification pass. Report 014's log lines are unchanged by this fix except
where noted (the anchor line now logs whichever packet actually
establishes the offset, which may be the second packet rather than the
first if the first was dropped).

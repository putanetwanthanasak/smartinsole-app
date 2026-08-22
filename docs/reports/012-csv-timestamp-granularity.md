# 012 — CSV `tUnixMs` granularity: correct value discarded one hop downstream

Fixes a timestamp-granularity defect in the research-capture CSV export,
found by inspecting exported data directly: consecutive rows within one BLE
packet (8 samples) showed `tUnixMs` values within ~1 ms of each other, then
jumped ~120–160 ms to the next packet's 8 samples — e.g.
`258500,258500,258501,258501,258501,258501,258501,258501, 258624` — instead
of the spec's `t0_ms + i×20` spread evenly across ~140 ms. Row *count* was
already confirmed correct (report 010 §3: 50.1 Hz/side); this is a value
problem, not a rate problem.

## 1. Trace result: the correct value exists, and is discarded one hop downstream

**`WebBleDataSource.handleSensorValue()` computes it correctly**
(`WebBleDataSource.ts:416,424`):

```ts
const deviceMs = parsed.header.t0Ms + i * SENSOR_SAMPLE_SPACING_MS;   // = 20 (bleProtocol.ts:42)
const sample: SensorSample = {
  tUnixMs: this.toUnixMs(deviceMs),   // device-timeline, clock-offset corrected
  ...
};
this.samples.emit(sample);            // one emit() per sample, i = 0..7
```

**It never reaches `RawPressureSample`.** `DeviceManager.box()`'s `onSample`
handler (`DeviceManager.ts:82-100`, pre-fix) built `RawPressureSample` from a
single `Date.now()` call, ignoring `s.tUnixMs` entirely:

```ts
const arrivedAt = Date.now();
...
const raw: RawPressureSample = { side: source.side, tUnixMs: arrivedAt, ... };
```

`WebBleDataSource`'s for-loop emits all 8 samples of one BLE notification
synchronously, back-to-back, in a single JS task — each `emit()` re-enters
this handler and calls `Date.now()` again. Total work per sample (a couple
of array maps, one object allocation) is far under 1 ms, so all 8 `Date.now()`
calls land within the same or adjacent millisecond — exactly the reported
pattern. The next packet's notification event fires a real ~140–160 ms later
(8 samples at 50 Hz), which is the jump.

This was deliberate, but for a different field's purpose than the one it got
reused for. `RawPressureSample.tUnixMs`'s doc comment (pre-fix) said
*"Arrival time... never the device's own clock"* — correct and intentional
for `gait.ts`, `RawPressureSample`'s original and, until report 010, only
consumer: `gait.ts:320-325` uses it solely to detect ~2000 ms PAI window
boundaries, where a few ms of jitter is irrelevant. The capture-mode pass
added a second consumer (`Recorder` → CSV) that inherited the same field
under that same "arrival time is fine" assumption, without checking whether
the training pipeline's needs differed — they do: `data_loader.py`'s
`merge_asof` alignment (per the user's report) needs true ~20 ms intra-packet
spacing, with a 15 ms tolerance.

**Confirmed only one construction site, only two consumers.**
`grep -rn "RawPressureSample|onRawSample"` across `src/ts/`: `DeviceManager.ts`
is the only place a `RawPressureSample` is built; `capture/recorder.ts` and
`gait.ts` are the only `onRawSample` subscribers. Nothing else needed
touching.

### Why mock-based testing never caught this

`MockDataSource.emitSample()` runs off its own real `setInterval` at 50 Hz
(`MockDataSource.ts:140`) — one sample per timer tick, not 8 emitted
synchronously per batch like a real BLE notification. Under mock, consecutive
`onSample` invocations really are ~20 ms apart in wall-clock arrival time, by
construction — `Date.now()` looks correctly spaced purely because mock never
simulates real hardware's packet-batching. Report 010 §3's rate measurement
was real and correct; rate alone can't detect a granularity collapse that
only manifests when 8 samples arrive in one synchronous burst, which only
real BLE notifications do. Same shape of gap as report 011's mock-masking
finding, different field.

## 2. Row ordering — unaffected; values only

Data is not scrambled. `Recorder.handleRaw()` pushes to its buffer in exactly
the order `onRawSample` fires, which is exactly the order
`WebBleDataSource`'s for-loop emits (i = 0..7, packet after packet) — true
temporal order survives the buffer, `IndexedDB.add()`'s autoIncrement key,
and `streamSamples()`'s cursor (ties on the `bySessionId` index key return in
primary-key/insertion order in practice). A reader trusting row *position*
within one side's CSV already had the right sequence. What was broken is
specifically the numeric `tUnixMs` *values* collapsing to near-duplicates
within a packet — which breaks a cross-stream, value-based join
(`merge_asof`) between independent L/R files, since several real
20–140 ms-apart samples in one packet all presented the same timestamp to
the joiner.

## 3. The fix: a new field, not a repurposed one

Per instruction, `RawPressureSample.tUnixMs` keeps its exact current
meaning and behavior — `gait.ts`'s PAI windowing depends on that semantics
staying arrival-time, and repurposing it would silently reintroduce a
clock-skew risk into staleness detection. Added a second field instead.

**`data/types.ts`** — `RawPressureSample` grows `deviceTUnixMs`, both fields
now documented to distinguish them explicitly:

```ts
export interface RawPressureSample {
  side: FootSide;
  /** Arrival time... Use for staleness/freshness checks... NOT evenly spaced within a packet. */
  tUnixMs: number;
  /** Device-timeline time: t0_ms + i×20... Evenly spaced within a packet, unlike tUnixMs above.
   *  Use for anything needing true intra-packet sample spacing — currently only CSV export /
   *  cross-stream (L/R) alignment. */
  deviceTUnixMs: number;
  pressure: FootPressure;
  accelG: [number, number, number];
  gyroDps: [number, number, number];
}
```

**`DeviceManager.ts`** — populated at the same call site, alongside the
existing field, no other change:

```ts
const raw: RawPressureSample = {
  side: source.side, tUnixMs: arrivedAt, deviceTUnixMs: s.tUnixMs, pressure: b.pressure,
  accelG: s.accelG, gyroDps: s.gyroDps,
};
```

**`capture/recorder.ts`** — the CSV column stays named `tUnixMs` (fixed
schema — `CSV_COLUMNS` unchanged, no rename, per the "don't touch the
schema without checking the pipeline owner" instruction already on that
file), but is now sourced from the new field:

```ts
tUnixMs: s.deviceTUnixMs,   // was s.tUnixMs
```

**`gait.ts` — untouched.** Still reads `s.tUnixMs`, still gets arrival time,
exactly as before.

## 4. Verification against a real (not mock) timing pattern

No physical BLE hardware or Bluetooth adapter is reachable from this
environment — I could not literally reconnect to your ESP32 simulator. What
I did instead, closest available to that: ran the actual, unmodified
`WebBleDataSource.handleSensorValue()` and `blePacketParser.ts` (copied only
to fix `.js`→`.ts` import extensions, plus one unavoidable, disclosed,
test-only patch — Node's plain `import.meta.env.DEV` doesn't exist outside
Vite, so the dev-only saturation-curve check's guard was pointed at a global
test flag instead; this is unrelated to timestamp logic and never on the
path being tested) against a synthetic-but-wire-format-accurate 200-byte
sensor packet (8-byte header + 8×24-byte sample blocks, matching
`bleProtocol.ts`'s real layout), via Node's TypeScript type-stripping
(`--experimental-transform-types`) — no reimplementation of the timestamp
math, the real class computed every value below.

**Step 1 — `WebBleDataSource`'s own per-sample output, two packets:**

```
Emitted SensorSample.tUnixMs values (2 packets x 8 samples):
1787415993351, 1787415993371, 1787415993391, 1787415993411, 1787415993431, 1787415993451, 1787415993471, 1787415993491,
1787415993511, 1787415993531, 1787415993551, 1787415993571, 1787415993591, 1787415993611, 1787415993631, 1787415993651

Intra-packet deltas (should be ~20ms each):
Packet 1: -, 20, 20, 20, 20, 20, 20, 20
Packet 2: -, 20, 20, 20, 20, 20, 20, 20
```

**Step 2 — those exact values fed through the real `capture/store.ts` +
`capture/csv.ts`** (same files, same copy-only-to-fix-imports approach as
reports 010/011's verification), built into `SampleRow`s the way the
now-fixed `recorder.ts` builds them (`tUnixMs: deviceTUnixMs`), exported to
an actual CSV:

```
subjectId,sessionId,tUnixMs,side,gaitLabel,isValid,fsr_hallux,fsr_meta1,fsr_meta3,fsr_meta5,fsr_midfoot,fsr_heel,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z
SI-009,sess-ts-check-001,1787415993351,L,normal,true,10,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993371,L,normal,true,11,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993391,L,normal,true,12,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993411,L,normal,true,13,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993431,L,normal,true,14,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993451,L,normal,true,15,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993471,L,normal,true,16,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993491,L,normal,true,17,20,30,40,5,60,0,0,1,0,0,0
SI-009,sess-ts-check-001,1787415993511,L,normal,true,18,20,30,40,5,60,0,0,1,0,0,0
...
```

```
tUnixMs deltas between consecutive rows: -, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20
```

Also confirmed:

- `npm run build` (`tsc --noEmit && vite build`) clean after all four edits.
- `DeviceManager.ts`'s new `deviceTUnixMs: s.tUnixMs` line and
  `capture/recorder.ts`'s changed `tUnixMs: s.deviceTUnixMs` line were read
  directly and diffed against the pre-fix versions — both are one-line
  pass-throughs with no computation of their own, so direct reading is as
  strong a check as re-running them in a harness.

**Still outstanding, and this synthetic test cannot substitute for it:**
real BLE notification jitter, real MTU/packet-loss retries, and the actual
ESP32's `t0_ms` clock behavior are unverified against genuine hardware. If
you want to confirm this against your simulator directly: repeat report
010 §8's steps, record ~5–10 s, export, and check that consecutive rows
within one packet (look for `fsr_*` values that stay identical or near-
identical across a short run of rows — those are one packet's 8 samples)
show `tUnixMs` increasing by ~20 ms each, not collapsing to near-duplicates.

## 5. On `data_loader.py`'s 15 ms `merge_asof` tolerance — a read, not a fix

Not asked to change the Python side, and `data_loader.py` isn't in this
repo, so this is architectural reasoning from this app's code, not a
measurement of real jitter. Flagging for you to weigh:

Each side's `timeOffsetMs` is established independently, from that side's
own **first** packet's arrival after connect (`toUnixMs()`'s fallback path:
`Date.now() - lastKnownDeviceMs` at the moment the first packet is
processed), and only refreshed every `RESYNC_INTERVAL_MS` (5 minutes)
thereafter via `SYNC_TIME`. L and R are two independent BLE GATT
connections — there is nothing in this design that correlates the two
sides' offset estimates to each other. Whatever latency exists between a
peripheral's true internal sample instant and the central's
`characteristicvaluechanged` event firing (BLE connection-interval
scheduling, ATT queuing, OS Bluetooth stack overhead) becomes baked into
that side's offset, independently of the other side's. Two independently-
estimated offsets, each with their own unmeasured jitter, means the
absolute alignment between an L timestamp and an R timestamp is only as
good as the worse of the two estimates — and nothing here bounds that to
under 15 ms; it's plausible for real BLE stacks to jitter by more than that
between connect and the first resync.

My honest read: 15 ms is a reasonable target, not a demonstrated
guarantee. Worth measuring empirically once real hardware is available
(e.g., recording a sharp simultaneous physical event both feet would sense
at close to the same true instant, or checking how much the computed ΔT
between the two sides' offset estimates actually drifts across a session)
before trusting it as a hard alignment tolerance rather than a starting
guess.

## 6. Scope

Four edits: `data/types.ts` (new field + doc comments on both), one line in
`DeviceManager.ts`, one line in `capture/recorder.ts`. `gait.ts`, `csv.ts`,
`store.ts`, `CSV_COLUMNS`, and every threshold/channel-order constant are
untouched.

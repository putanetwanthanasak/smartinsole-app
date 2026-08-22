# 011 — Temperature `quality` field: semantic inversion, four sites

Fixes a single root cause discovered while investigating a reported symptom
on the research-capture calibration screen (`#/capture`): after 4–6 minutes
connected to real BLE hardware, with pressure data confirmed healthy on both
sides, the calibration review showed `ΔT เริ่มต้น: ไม่มีข้อมูล` and
`อุณหภูมิ: — · —` for both feet. The user independently confirmed via the
standalone `ble-test/index.html` page (its own parser, unrelated to this
app's code) that the firmware sends valid temperature packets — live
`forefootC`/`heelC` values updating normally, alongside `quality=0`. That
ruled out the firmware and BLE transport before this investigation started.

## 1. Root cause

`data/types.ts`'s own doc comment on `TempReading.quality` was backwards
relative to the Data Contract:

```ts
/** 0 = unusable, 1 = degraded, 2 = good. */
quality: 0 | 1 | 2;
```

Per `docs/DATA-CONTRACT.md` line 148 and `docs/BLE-INTERFACE.md` line 112
(independently agreeing): **`0 = ปกติ` (normal/good), `1 = สัมผัสไม่ดี` (poor
contact), `2 = เซนเซอร์ผิดพลาด` (sensor error)**. `0` is the *good* value —
the comment had it exactly inverted.

Every consumer trusted the wrong comment and was wrong the same way:

| Site | Before | Effect |
|---|---|---|
| `capture.ts:341` | `if (s.temp && s.temp.quality !== 0)` | Calibration accumulator ran only on bad readings — the reported symptom |
| `DeviceManager.ts:151` (`pushHistory`) | `if (t.quality === 0) return;` | Temperature trend history discarded good readings, kept bad ones |
| `DeviceManager.ts:288` (`deltaT`) | `if (left.temp!.quality === 0 \|\| right.temp!.quality === 0) return null;` | ΔT nulled out on good data, computed from poor-contact/error data — see §2 |

`WebBleDataSource.ts`'s subscription and parsing of the temperature
characteristic were checked and are correct — this is not a wiring gap.
`DeviceManager.box()`'s handling of `onTemp` and inclusion of `temp` in
every `CombinedSnapshot` are also correct — `TempReading`s were never
dropped structurally. The defect is confined to the three `quality`
comparisons above, all downstream of the one wrong comment.

**Confirmed no fourth site.** `grep -rni quality` across the whole repo
(source, docs, everything) turned up only: the three call sites above, the
two type declarations (`data/types.ts`, `blePacketParser.ts` — plain
decode, no semantic judgment), `blePacketParser.ts`'s raw bitmask read
(correct, decodes the wire value as-is), `WebBleDataSource.ts:448`
(pass-through, no comparison), `MockDataSource.ts`'s two emit sites (§3),
and doc/contract text. No other conditional exists.

### Why mock-based testing never caught this

`MockDataSource.ts` hardcoded `quality: 2` on every emitted `TempReading`
(both `emitTemp()` and the 24 h backfill). `2 !== 0`, so none of the three
inverted checks above ever hit their "bad-data" branch under mock data —
mock and the wrong comment agreed with each other, just not with the real
firmware/contract. This includes every prior verification pass that used
`MockDataSource`, e.g. report 010 §3's calibration-accumulator
measurement — it exercised the accumulator successfully, but only because
mock's `quality: 2` accidentally satisfied `!== 0`, not because the gate's
logic was actually correct. This was the first time real hardware's
legitimate `quality: 0` reached this code, which is why it surfaced now
and not earlier.

## 2. Clinical-safety severity of `DeviceManager.ts:288` — separately, because it predates this session

`deltaT()` is not new code. Its `quality` check predates the capture-mode
pass and has been live, inverted, since before this session — this is not
something the capture-mode pass introduced, only something a new consumer
(`capture.ts`) happened to also get wrong the same way, which is what
exposed the whole family of sites.

This is the one that matters most: `deltaForefootC` (ΔT) is a real
clinical figure, rendered on the patient-facing Home tile and the
Temperature screen's ΔT hero, and is the exact case CLAUDE.md's "no
fabricated bilateral readings" section calls out by name. The inverted
check did the precise opposite of that rule's intent:

- With **both sides reporting normal contact** (`quality: 0`, the expected
  common case) — the inverted check nulled ΔT out. The patient-facing UI
  would show "no data" for ΔT under ordinary healthy operation.
- With **either side reporting poor contact or a sensor fault**
  (`quality: 1` or `2`) — the inverted check let ΔT compute anyway,
  producing a number from data the contract itself flags as unreliable,
  displayed with no indication anything was wrong. This is exactly the
  fabricated-bilateral-reading failure mode the safety rule exists to
  prevent, just reached via a different path (bad-quality input) than the
  two bugs the rule's section already documents (one-sided data,
  not-worn status).

Because `MockDataSource` never emitted `quality: 0` before this fix (§1),
this bug could not have been observed against mock data at any point in
this app's history — it required real hardware genuinely reporting normal
contact, which is what the capture-mode BLE testing finally did. Fixed the
same way as the other two sites: `deltaT()` now requires **both** sides
`quality === 0` to compute anything; either side non-zero returns `null`.
Verified directly (below).

## 3. The fix (5 edits, all on this branch)

1. `data/types.ts:45` — doc comment corrected to match the contract
   (Thai terms + English gloss), with a pointer to this report so a future
   reader doesn't have to rediscover why it matters.
2. `capture.ts:341` — flipped to `=== 0`; accumulates only on normal
   readings.
3. `DeviceManager.ts:151` (`pushHistory`) — flipped to `!== 0` early-return;
   keeps normal readings, discards poor-contact/error ones.
4. `DeviceManager.ts:288` (`deltaT`) — flipped to `!== 0` on either side ⇒
   `null`; computes ΔT only when both sides are `quality === 0`. Doc
   comment above the function rewritten to state the requirement and the
   history explicitly.
5. `MockDataSource.ts:219,231` — `quality: 2` → `quality: 0`. Mock now
   reports the value real hardware actually reports in the normal case,
   so all three consumers above are exercised on their real (correct)
   branch by every future mock-based test, not just their previously-taken
   accidental branch.

**Gap in mock coverage, worth remembering going forward:** mock data
existed to stand in for the wire format, but `quality: 2` was written to
satisfy whatever the *local type comment* said "good" meant, not to what
the contract's own document actually specifies. `MockDataSource` should
always be checked against `docs/DATA-CONTRACT.md` directly when adding a
new field, not against another file's comment about that field, however
authoritative that comment looks — a comment can be wrong and stay wrong
indefinitely if nothing round-trips it against a real device, which is
exactly what happened here for however many passes preceded this one.

## 4. Verification

- `npm run build` clean (`tsc --noEmit && vite build`) after all five
  edits.
- `deltaT()`'s fixed logic verified directly: the function body (copied
  verbatim from the post-fix `DeviceManager.ts`, diffed to confirm — the
  only differences are stripped TS type annotations/non-null assertions,
  zero logic changes) run under Node against four constructed cases:

  | Case | Result | Expected |
  |---|---|---|
  | Both sides `quality=0` | `1.0` | `1.0` (computes) |
  | Left `quality=1` | `null` | `null` |
  | Right `quality=2` | `null` | `null` |
  | Both `quality=2` | `null` | `null` |

  All four pass.
- Not yet re-verified against live BLE hardware in this pass — the Chrome
  extension used for browser automation wasn't connected in this
  environment. The user's own hardware check (report 010 §8) is the
  natural place to also confirm this fix: with real hardware reporting
  `quality=0`, the calibration screen should now populate
  `อุณหภูมิ`/`ΔT เริ่มต้น` instead of showing "ไม่มีข้อมูล", and the
  Home/Temperature ΔT tiles should show a live number under normal
  two-sided contact instead of blanking.

## 5. Scope

Touched exactly the five sites listed in §3, nothing else. No threshold,
channel order, or packet-parsing change — `blePacketParser.ts`'s raw
`quality` decode was already correct (a bare bitmask read, no semantic
interpretation) and is untouched.

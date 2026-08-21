# 006 — offset_adc resolved by the contract owner; hardware test checklist

Two items from `docs/reports/005-web-ble-datasource.md`'s open list.

---

## 1. `offset_adc` implemented

The contract owner resolved the gap flagged in report 005: `offset_adc` is
the zero-point ADC reading under no load — the stored result of a TARE
(control opcode `0x05`, "ปรับ zero-point ของ FSR"). The contract defines no
second zero-point mechanism, so TARE's result and this field are the same
concept.

**Implemented in `adcToKpa()` (`src/ts/data/blePacketParser.ts`):**

```
adc_corrected = max(0, adc_raw - offset_adc)
V_out = (adc_corrected / 4095) × 3.3
... rest of the documented chain unchanged
```

Clamped at 0, not left negative — a reading below the channel's own
recorded zero-point means drift or sensor noise, not negative pressure.

**Docs updated to show this explicitly, not just describe it:**
- `docs/DATA-CONTRACT.md` §5.1 — the formula block itself now includes the
  `adc_corrected` line, in the contract's own code-block style, plus a short
  Thai note on the 0-clamp. This is a direct edit to contract text on the
  owner's explicit instruction, not an annotation layered on top of it —
  worth flagging since the contract file's own banner otherwise says it
  "stays a straight copy of the contract text, not an annotated one."
- `docs/BLE-INTERFACE.md`'s "FSR scaling" section — same formula update,
  plus a paragraph explaining the TARE/offset_adc identity and (separately)
  a note that this changes measured values from before.
- `docs/BLE-INTERFACE.md`'s "What's still open" — the item removed, marked
  resolved by the contract owner, with a pointer to where the formula now
  lives.

**This changes measured kPa values.** Anything computed with report 005's
`adcToKpa()` (which didn't apply this subtraction at all) reads high by
whatever `offset_adc` was for that channel — flagged in three places
(`docs/BLE-INTERFACE.md`, the code comment, and `docs/BLE-TEST-CHECKLIST.md`
Check 4) so a discrepancy against old captured numbers isn't mistaken for a
new bug.

**Small side effect worth noting:** `WebBleDataSource.getDiagnostics()`
used to expose only `calibrationDeviceId: string | null`. Changed to expose
the full parsed `calibration: Calibration | null` object instead — needed
so `docs/BLE-TEST-CHECKLIST.md` Check 3 (confirm the calibration blob
parsed correctly) is actually followable from the console, not just
"a device_id showed up." `devBlePanel.ts`'s compact diagnostics line reads
`calibration?.deviceId` now instead of the old dedicated field — same
display, different source.

---

## 2. `docs/BLE-TEST-CHECKLIST.md`

A step-by-step checklist for the machine with the ESP32 simulator and USB
dongle — no Claude Code involvement, everything in it is something to type
or click. Covers, each with what to do / what correct looks like / what
failure means:

1. Loading `?ds=ble`, connecting the left side.
2. **8 samples per packet, 20 ms apart** — the one that can't be seen
   anywhere in the UI. Two console snippets: a rate check (`onSample`
   counted over 5s, expect ~250 → ~50 Hz; ~31 → ~6.25 Hz means only one
   sample is being emitted per packet, the exact bug hard requirement #3
   in report 005 was written to prevent) and a spacing check (log Δt
   between consecutive samples, expect seven ~20ms steps then one
   ~140–180ms jump, repeating). Includes a note on WHY the spacing is this
   precise regardless of real BLE jitter: `tUnixMs` is computed from the
   packet header's own `t0_ms + i×20`, a straight line through a value
   read off the wire — so this check is really confirming the unpacking
   loop reads `count`/`t0_ms` correctly, not measuring BLE timing
   precision.
3. Calibration read — exact console command
   (`getDiagnostics().calibration`) and the shape to expect **derived from
   the contract's own schema** (exactly 6 channels, indices `{0..5}` each
   exactly once, matching the FSR channel table), not from what the code
   produces.
4. kPa plausibility against the standalone test page (already verified
   correct — a discrepancy means this app's parser is wrong, not the
   device). Specifically calls out that resting/no-load readings should now
   be near-zero because of the `offset_adc` fix above, and that old
   pre-fix captures will read differently by design.
5. Sequence gaps / dropped packets — exact diagnostics field, what a
   healthy number is (near 0, and `totalPackets` should track `N × 6.25`
   for N seconds connected — both derived from the contract's packet rate,
   not from the implementation).
6. Truncation as the only available proxy for silent MTU failure (Web
   Bluetooth exposes no way to read negotiated MTU from JS) — what the
   exact console line looks like and what it means.
7. Disconnect/reconnect with no second device picker — and what it means
   if one *does* appear (distinguishing an intentional "Forget device"
   click from an actual reconnect-path bug).
8. Side mismatch, using the SAME simulator (`SMARTINSOLE-L`,
   `foot_side=0`) connected into the `right` slot as a free, repeatable
   test of that path without needing a second physical device — exact
   expected error message text, and what it means if this check instead
   shows `right` connecting successfully (flagged as the worst-case outcome
   this whole feature exists to prevent).

Closes with a "what to capture on any failure" section: which check
number, full console output (not a screenshot), both sides'
`getDiagnostics()` at the moment of failure, whether it reproduces on a
second attempt, and browser/OS/adapter details.

---

## Verify

`npm run build` clean (`tsc --noEmit && vite build`) after the `adcToKpa()`
change and the diagnostics-shape change. No screen touched;
`docs/BLE-TEST-CHECKLIST.md` requires no build step to use (it's a doc).

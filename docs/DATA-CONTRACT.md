# Data Contract v1.1

**STATUS: PLACEHOLDER — NOT YET FILLED IN.**

This file is a placeholder. The actual Data Contract v1.1 has not been pasted in
yet. Every threshold, type shape, channel order, and packet format currently
implemented in this codebase (`src/ts/constants.ts`, `src/ts/data/types.ts`,
`src/ts/data/*.ts`) was derived from that document during earlier sessions, but
the document itself has never lived in this repo — it existed only outside it,
referenced by name.

**Do not invent, reconstruct, or infer the contract's contents from the code.**
The code is downstream of the contract, not the other way around; if they ever
disagree, the contract wins and the code is what's wrong. Treat any threshold or
shape you find in `constants.ts` or `data/types.ts` as "what a past session
believed the contract said," not as a substitute for reading the contract
itself.

## To fill this in

Replace this entire file with the pasted contract text. Once that's done:

1. Re-check every constant in `src/ts/constants.ts` against it — the pressure
   tiers (`PRESSURE_WATCH_KPA`, `PRESSURE_ALERT_KPA`), `TEMP_DELTA_THRESHOLD`,
   and `FSR_CHANNEL_ORDER` were all typed from a remembered version of this
   contract and may not match v1.1 exactly.
2. Re-check `src/ts/data/types.ts` — `SensorSample`, `TempReading`,
   `DeviceStatus` — field names, types, and units against the contract's wire
   format.
3. Confirm the 30-minute per-code alert repeat-suppression window
   (`src/ts/data/AlertStore.ts`) and the packet/MTU details referenced in
   `docs/PROGRESS.md` still match.

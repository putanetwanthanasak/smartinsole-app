# 018 — Repository README

Adds a top-level `README.md` for the repository. Documentation only — no
source, config, or behaviour change.

## What changed

- **New file:** `README.md` at the repo root.

Nothing else. `npm run build` was not re-run because nothing under `src/ts/`,
`css/`, `public/`, or the build config was touched.

## What the README covers

Grounded entirely in the code, `package.json` / `tsconfig.json`, commit
history, and `docs/` — no feature or stack detail that isn't evidenced in the
repo.

1. **Name + one-line description** — the companion app for a two-insole
   pressure + skin-temperature fusion system for diabetic foot ulcer risk
   monitoring; this repo is the front-end only.
2. **Project status** — in development; human-subject data collection not
   started (protocol is a draft pending IRB); no PCB hardware yet. Includes a
   per-area Done / Partial / Not started table, each row citing a file or
   report.
3. **Implemented features** — SPA shell + router, offline bundling, the
   `IDataSource → DeviceManager` seam, `AlertStore` (3 of the contract's 9
   alert codes, with the walking gate and 2-consecutive-reading temp rule),
   runtime `thresholds.json` + validation, the four wired screens, Gait's
   PAI-only wiring, research-capture mode, and the dev-only `WebBleDataSource`.
4. **Tech stack** — read from `package.json` / `tsconfig.json` / `SETUP.md`:
   TypeScript 5.9, Vite 8, lucide 1.33, three `@fontsource` packages;
   IndexedDB, Web Bluetooth; no tests/linter; Node ≥ 20. The wider planned
   architecture (React Native, TFLite, Firebase, Capacitor) is described only
   under an explicit "not in this repository" heading, sourced from
   `docs/DATA-CONTRACT.md`.
5. **Setup / run** — install, `npm run dev`, routes, typecheck, build,
   preview, and the `?ds=ble` simulator flow. States plainly that the
   firmware/flashing is not in this repo rather than inventing commands.
6. **Folder structure** — annotated tree from `git ls-files`.
7. **Team + academic advisor** — from project documentation, corroborated by
   the git commit author.
8. **Disclaimer** — academic research project, not a certified medical device,
   not clinically validated, thresholds provisional; notes the absence of a
   LICENSE file.

## Notes for the next reader

- The repo previously had an untracked `README.md` draft (never committed). It
  described the app as React Native with an implemented CNN-LSTM model —
  neither is true of this repo (the classifier is explicitly out of scope per
  `docs/BACKLOG.md` items 8–9; `gaitPrediction.ts` is a stub seam). That draft
  carried its own note that it hadn't been checked against the source. This
  README replaces it and is written from the code.
- If the implementation status of `WebBleDataSource` or the research-capture
  hardware run changes, the status table in the README is the place to update.

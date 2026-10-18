# shared/

Files shared between the Flutter app (`mobile/`) and the new simulator
(`firmware/simulator/`). See `docs/FLUTTER-PLAN.md` section 3.

- **`thresholds.json`** — the source-of-truth threshold file for the Flutter
  app. It started as a byte-for-byte copy of `public/thresholds.json`.
- `sensor_layout.json`, `test_vectors/` — not yet created (planned for S2A).

## The web app still uses `public/thresholds.json`

The web app is **frozen** — do not edit it, and do not edit
`public/thresholds.json`. It keeps loading its own copy from `public/` at
runtime. The two copies are intentionally not linked (no symlink, no build
step), so a change to `shared/thresholds.json` does **not** reach the web app,
and the two files may diverge from here on.

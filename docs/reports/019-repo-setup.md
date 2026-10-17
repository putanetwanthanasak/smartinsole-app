# 019 — Repo setup for the Flutter app (S0B)

Session S0B from `docs/SESSIONS.md`. Prepares the repository for the Flutter
rewrite. Documentation and scaffolding only — no web-app source, config, or
behaviour change.

## What changed

- **Plan docs** (English editions supplied by the user, copied verbatim):
  - `docs/FLUTTER-PLAN.md`
  - `docs/SESSIONS.md`
  - `docs/design/DESIGN-SPEC.md`

  The first commit on this branch added the original Thai editions; they were
  replaced by the English editions in a later commit, so `main` will only
  ever see the English ones. Thai remains only in quoted UI strings in
  `DESIGN-SPEC.md` (19 lines: tab labels, status copy, foot-check copy,
  TalkBack labels), which matches the language rule in `docs/SESSIONS.md`
  section 0.
- **`shared/thresholds.json`** — byte-identical copy of
  `public/thresholds.json`.
- **`shared/README.md`** — explains that `shared/` is the Flutter app's
  source of truth, that the frozen web app keeps loading
  `public/thresholds.json`, and that the two copies are not linked and may
  diverge.
- **`firmware/simulator/README.md`** — placeholder until S2B.
- **`.gitignore`** — added `.pio/`, `mobile/build/`, `.dart_tool/`.
- **`CLAUDE.md`** — new "Flutter app (Oct 2026)" section near the top: web
  app frozen (edits only when the user asks for a data-collection bug),
  pointers to the three plan docs, where new work lives (`mobile/`,
  `shared/`, `firmware/simulator/`), English-only rule, and a note that the
  Flutter app replaces the Capacitor step in "Next phase". The rest of
  `CLAUDE.md` is unchanged and still describes the web app.

## Verification

| Check | Result |
|---|---|
| `npm ci && npm run build` passes | **Pass** — `tsc --noEmit` clean, Vite build OK (157 ms) |
| `git status` shows no build output after the build | **Pass** — clean; `dist/` and `node_modules/` ignored |
| Plan docs byte-identical to `~/Downloads` originals | **Pass** — `cmp` and SHA-256 match for all three |
| `shared/thresholds.json` identical to `public/thresholds.json` | **Pass** — `cmp` |
| No web files touched | **Pass** — `git diff main --name-only` has nothing under `src/`, `css/`, `public/`, `index.html`, `package*.json` |
| `CLAUDE.md` Flutter section and `shared/README.md` English only | **Pass** — no Thai characters |
| PR open | **Pass** — see the PR for this branch |

The 16 rules in `docs/FLUTTER-PLAN.md` section 6 are about app behaviour;
none apply to a docs/scaffolding change.

## Out of scope, noted

- **npm was not installed** on the machine at the start (only the Ubuntu
  `nodejs` package, Node v22.22.1). The user installed it (`npm` 9.2.0)
  so the build check could run.
- **`npm audit` reports 1 high-severity vulnerability** in the web app's
  dependencies. Not touched — the web app is frozen and this is outside S0B.
  The user should decide whether it matters for the frozen web build.
- The Thai Sessions plan expected the repo at
  `~/development/smartinsole-app`; the English edition corrects this to
  `~/smartinsole-app`, which is where it actually is.

## Decisions needed

- Whether to act on the `npm audit` finding for the frozen web app.

## Next session

S1B — `mobile/` scaffold + theme (requires this PR merged).

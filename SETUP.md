# Setup

How to get the Smart Insole app running on your machine, from a fresh clone to a page open in the browser.

## 1. Prerequisites

You need **Node.js** (version 20 or newer). Node ships with `npm`, which is the only tool you need to install by hand.

Check that both are installed:

```
node --version
npm --version
```

If either command isn't recognized, download the LTS installer from <https://nodejs.org> and run it.

## 2. Install dependencies

From the project folder (the one containing `package.json`):

```
npm install
```

This reads `package.json` and downloads everything into a `node_modules/` folder. You only need to run this once after cloning, or again if `package.json` changes.

The project uses **Vite** as its dev server and bundler, **TypeScript** for type checking, and pulls in **Lucide** (icons) and three **@fontsource** font packages at build time. Nothing is loaded from a CDN at runtime — the app works offline.

## 3. Run the app

```
npm run dev
```

That starts the Vite dev server and prints a URL, normally <http://localhost:5173>. Open it and the app loads at the Home screen.

Vite serves the TypeScript in `src/ts/` directly — there is no separate build step while developing. Save a file and the change appears in the browser immediately via hot module replacement; **no manual rebuild and no hard reload.** (This replaces the old `tsc` + static-server + `Ctrl+Shift+R` cycle, and the browser-cache workaround it needed.)

The app is a single page with hash routing, so every screen has its own address you can link to or reload directly:

- <http://localhost:5173/#/home> — dashboard with foot heatmap
- <http://localhost:5173/#/gait> — walking analysis
- <http://localhost:5173/#/temp> — foot temperature trends
- <http://localhost:5173/#/alerts> — alert timeline
- <http://localhost:5173/#/settings> — device & preferences

## 4. Type checking

Vite strips types without checking them, so type errors do **not** stop the dev server. To see them:

```
npm run typecheck      # once
npm run watch          # continuously, alongside npm run dev
```

`npm run build` runs the same check first and fails the build on any type error, so nothing broken can be released.

## 5. Production build

```
npm run build      # tsc --noEmit && vite build  → dist/
npm run preview    # serve dist/ to check the real bundle
```

`npm run build` writes a self-contained bundle to `dist/` (JS, CSS, and the font files). `dist/` is generated output — it is gitignored and should never be edited or committed.

## Project layout

```
smart-insole-app/
├── index.html        Entry point — the SPA shell (status bar, header, #view, tab bar)
├── src/ts/           TypeScript source (what you edit)
│   ├── main.ts       Entry module: imports fonts, starts the router
│   ├── router.ts     Hash router + each screen's section scaffolding
│   ├── icons.ts      The Lucide icon set this app bundles
│   └── …             One module per screen, plus shared modules
├── css/              Stylesheets — global + components + one per screen
├── pages.reference/  Dead markup from the original multi-page mockup (see its README)
├── dist/             Build output — generated, gitignored
├── package.json      Scripts and dependencies
└── tsconfig.json     TypeScript settings (type checking only; Vite does the transform)
```

You edit `index.html`, `css/`, and `src/ts/`. Never edit `dist/` — it is overwritten on every build. Never edit `pages.reference/` — nothing loads it.

## Available scripts

| Command             | What it does                                                     |
| ------------------- | ---------------------------------------------------------------- |
| `npm install`       | Install dependencies (run once after cloning).                   |
| `npm run dev`       | Start the Vite dev server with hot reload. **This is the one you want.** |
| `npm run build`     | Type-check, then bundle to `dist/`. Fails on any type error.     |
| `npm run preview`   | Serve the built `dist/` output locally.                          |
| `npm run typecheck` | Run `tsc --noEmit` once.                                         |
| `npm run watch`     | Run `tsc --noEmit` in watch mode.                                |

There is no test suite and no linter in this project.

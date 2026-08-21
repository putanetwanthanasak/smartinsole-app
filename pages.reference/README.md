# pages.reference/ — dead markup, kept for reference only

**These files do not run. Nothing loads them.** Opening one in a browser shows an
empty device frame: they still reference `../dist/js/<page>.js`, but those modules
no longer boot themselves — they export `mount()` / `unmount()` and are driven by
the router instead.

**The live scaffolding lives in `src/ts/router.ts`**, in the `*_TEMPLATE` constants.
That is the markup the app actually injects into `<div id="view">` on every route
change. The app's single entry point is `index.html` at the project root.

These files are kept only as a visual and markup reference for the original
multi-page mockup — what each screen's section scaffolding looked like before the
SPA refactor.

**Editing anything in this folder has no effect on the running app.** If you need to
change a screen's scaffolding, change the matching `*_TEMPLATE` in
`src/ts/router.ts`.

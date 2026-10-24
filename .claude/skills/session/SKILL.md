---
name: session
description: Run one session from docs/SESSIONS.md (Plan → Do → Verify → Report). Usage /session <ID> [extra notes], e.g. /session S6B part 2
argument-hint: <ID> [extra notes]
disable-model-invocation: true
---

# Session $ARGUMENTS

The first word(s) of the arguments name the session (e.g. `S6B`, `S8A`); anything after
is extra notes from the user ("part 2" = the next sub-session of that ID).

## 1. Read (link, never copy into chat or this skill)
- `docs/SESSIONS.md`: §0 (rules for every session), §2 (branch names, Note 10 checkpoints), and the session's entry in §3.
- Every doc and section that entry points to (`docs/design/DESIGN-SPEC.md` §…, `docs/DATA-CONTRACT.md`, `docs/BLE-INTERFACE.md`, `docs/FLUTTER-PLAN.md` §6 and §11, `docs/STUDY-CAPTURE.md`).
- `CLAUDE.md`, `mobile/CLAUDE.md`, `docs/BACKLOG.md`, and the highest-numbered `docs/reports/NNN-*.md` (its "Leftovers").

## 2. Plan (no code yet)
- Check the entry's **Requires** against `git log origin/main` and `gh pr list --state all`. If something is missing, stop and say what.
- Post the plan in chat: files to create/change, ordered steps, how each **Done when** item is verified, risks.
- Ask every open decision as numbered options with a recommended default. Never guess.
- **Stop and wait for the user's OK.** Nothing is created, branched or edited before it.

## 3. Do
- `git checkout main && git pull --ff-only && git checkout -b work/<topic>` (the §2 branch name if it has one; add a suffix for part 2+).
- Commit in small steps. Out-of-scope problems go into the report and `docs/BACKLOG.md`, not into code.

## 4. Standing rules (on top of SESSIONS §0 and the 16 rules)
- Never touch the web app (`index.html`, `src/`, `css/`, `public/`, web build config).
- Never touch Phumirapee's real firmware. Edit `firmware/simulator/` only when the session says so.
- Health advice and explanation copy stays draft: it must match DESIGN-SPEC Appendix A and keep its draft marking.
- No hardcoded thresholds: values come from `shared/thresholds.json` (bundled copy `mobile/assets/config/thresholds.json`).
- Research capture recording and timing must not change (STUDY-CAPTURE.md). Never delete capture data.
- Never delete or overwrite data on the phone (app data, capture folders, staged exports) or in the laptop export folders (`~/smartinsole-data/`) without asking first, naming exactly what would go.
- Never `adb uninstall`, `pm clear` or reinstall without `-r` on the Note 10: it holds study data.

## 5. Verify
- SESSIONS §0 Step 3: `flutter analyze`, `flutter test`, goldens, emulator + Dart MCP screenshots, each relevant rule of FLUTTER-PLAN §6, every **Done when** item.
- Then run the `spec-reviewer` agent on `git diff main...HEAD`, naming the spec sections this session implements. Fix blockers, or list why not.

## 6. Report
- `docs/reports/<highest + 1, zero-padded>-<topic>.md`: done / each check (pass, fail, waiting on user) / spec-reviewer findings table, copied as returned plus a "resolution" column / leftovers / decisions needed / next session.
- Update `docs/BACKLOG.md`; commit, push the branch, open a PR with `gh pr create`. Never merge.
- A Note 10 checkpoint is a numbered checklist in the report, marked **waiting on user**. Wait for the user's results. Never mark it passed yourself.
- Chat summary of at most 10 lines with the report path and PR link.

## 7. Hardware: say exactly what to plug in, before you need it
- **Note 10:** "Plug the Note 10 into the laptop by USB, unlock it, allow USB debugging." Confirm with `adb devices -l`.
- **ESP32 simulators:** name the board (left/right), which USB port, and what firmware it must run. Use only `/dev/serial/by-id/usb-Silicon_Labs_CP2102…`, never the Quectel modem's ttyUSB. If access is denied, ask the user to run `! sudo setfacl -m u:pumon:rw /dev/ttyUSBn`. Opening the port resets the board, so start serial logs before a phone connects.
- **Emulator / Dart MCP:** if not running, say which command to start (`flutter run -d emulator-…` in a separate terminal) and wait.

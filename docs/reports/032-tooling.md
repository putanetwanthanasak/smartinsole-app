# 032 — Tooling: /session skill, spec-reviewer agent, permissions, notifications

Branch `work/tooling` (from `main` at the PR #27 merge, `df1d192`) · 2026-10-24 ·
Tooling session, not in `docs/SESSIONS.md` §3. No app, firmware or web-app code
changed. Plan approved 2026-10-24 with the user's choices: A1 (the user runs the
`/session` test), B (merge this PR before the real S6B part 2), C (the Stop
notification fires only for turns of 30 s or more), and a narrower adb allowlist.

**Status: waiting for the user** to confirm the desktop notifications appeared
and to run `/session S6B part 2` in plan mode.

## What was done

| File | Committed | What |
|---|---|---|
| `.claude/skills/session/SKILL.md` | yes | `/session <ID> [notes]`, 50 lines, `disable-model-invocation: true`. Read (links only) → Plan (Requires check, options, wait for OK) → Do (branch from latest `main`) → standing rules → Verify (SESSIONS §0 Step 3 + `spec-reviewer`) → Report (next number, PR, phone checkpoint left for the user) → what to plug in. |
| `.claude/agents/spec-reviewer.md` | yes | Read-only reviewer (`Read, Grep, Glob, Bash`; Bash limited to git/ls/cat/grep/wc/jq by its prompt). Given a diff and spec sections, it returns one table: `# | Severity | File:line | Spec | Mismatch`, covering copy, sizes, colours, states, navigation, rules, thresholds, TalkBack, reduce motion and research-data safety. No style findings; spec ambiguities go in a separate "Spec gaps" list. |
| `.claude/settings.json` | yes | Permission allow/ask/deny lists and the `adb_guard.py` PreToolUse hook. |
| `.claude/hooks/adb_guard.py` | yes | See "Why a hook" below. |
| `.claude/settings.local.json` | **no** (gitignored) | `Notification` hook (always), `UserPromptSubmit` (writes a turn start time to `$XDG_RUNTIME_DIR/claude-turn-<session>`) and `Stop` (notifies only if the turn took 30 s or more), all using `notify-send`. |
| `mobile/CLAUDE.md` | yes | One line pointing to `/session`. |

### Standing rules in the skill
Web app untouched; Phumirapee's real firmware untouched, `firmware/simulator/`
only when the session says so; health copy stays draft (DESIGN-SPEC Appendix A);
thresholds only from `thresholds.json`; capture recording and timing unchanged;
never delete capture data; **never delete or overwrite data on the phone or in
`~/smartinsole-data/` without asking first**; no `adb uninstall`, `pm clear` or
reinstall without `-r` on the Note 10.

### Permissions

| List | Entries |
|---|---|
| allow | `flutter analyze`, `flutter test`, `flutter build apk`, `dart format`; `adb devices`, `adb install -r`, `adb exec-out`, `adb pull`, `adb logcat`; `adb shell` getprop, dumpsys, screencap, screenrecord, input, am start, am force-stop, settings get, ls, pm list, pm dump; `pio run`, `pio test`; `python3 tools/capture/*`, `python3 firmware/simulator/tools/*` |
| ask | `git push`, `gh pr merge`, `adb push`, `adb shell settings put` |
| deny | `adb uninstall`, `adb shell pm clear`, `adb shell pm uninstall`, `adb shell rm`, `adb shell run-as` |

### Why a hook as well as the lists
Claude Code checks rules **deny → ask → allow, and the first match wins**. That
causes three gaps:
1. A catch-all `ask: adb shell *` would also catch the allowed `adb shell getprop`
   etc., so "ask for any *other* adb shell command" can't be written as a rule.
2. "`adb install` without `-r`" can't be written as a prefix pattern.
3. Prefix rules miss `adb -s SERIAL shell rm …`, `adb shell 'sh -c "rm …"'` and
   `adb exec-out run-as …`. The `-s` form is how a specific phone is usually picked.

`adb_guard.py` parses each Bash command line, strips adb's global options, and
returns `deny` for uninstall, rm, run-as, pm clear and pm uninstall anywhere in a
shell or exec-out command, including nested quotes. It returns `ask` for any shell
or exec-out command not on the allow list (including redirects), install without
`-r`, push, and `export_capture.py --remove-staged`, which deletes the staged
export on the phone. Otherwise it gives no decision and the lists apply. This
means `adb exec-out` is allowed only for allowlisted commands (e.g. `screencap -p`),
not for anything. `--remove-staged` was not in your list. I added it because it
deletes data on the phone, which falls under your new rule.

## Checks

| Check | Result |
|---|---|
| Both settings files are valid JSON (`jq empty`) | pass |
| `adb_guard.py` with 37 sample commands | pass. Allowed ones give no decision; `adb shell`, `cat`, `settings put`, `install` without `-r`, `push`, a redirect inside shell and `--remove-staged` give ask; uninstall, `pm clear`, `-s X shell pm uninstall`, `rm`, `run-as`, `exec-out run-as`, `sh -c "rm …"`, and `… && adb -d shell rm x` give deny. `adb shell ls; rm -rf /sdcard` gives no decision: there the `rm` runs on the laptop and goes through the normal prompts. The first run found that `sh -c "rm …"` only asked. Fixed by re-splitting quoted arguments. |
| Notification hook command, fed a sample payload | sent (exit 0). **Waiting on user** to confirm it appeared. |
| Stop hook, turn of 45 s | sent "turn took 45s" (exit 0). **Waiting on user.** |
| Stop hook, turn under 30 s | no notification (correct) |
| Skill length | 50 lines (limit ~60) |
| `spec-reviewer` on this diff | not run: no app code or spec-covered UI in this diff |
| `/session S6B part 2` in plan mode | **waiting on user** (A1). If `/session` isn't listed, restart Claude Code; skills are found at startup on some versions. |

## Notes
- Hooks in `settings.local.json` and `settings.json` take effect in a new session,
  or after you review them in `/hooks`.
- The guard is a safety net, not a sandbox. A command built to dodge it (e.g.
  `adb shell $(echo cm0= | base64 -d)`) gets "ask", not "deny", because it isn't on
  the allow list.
- Merge this PR before starting the real S6B part 2. Its branch is cut from
  `main`, so it won't have the skill or agent otherwise.

## Leftovers
None for the backlog.

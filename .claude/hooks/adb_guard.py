#!/usr/bin/env python3
"""PreToolUse guard for Bash commands that reach the Note 10 (study data lives there).

Permission rules in settings.json are prefix matches evaluated deny > ask > allow,
so they cannot say "ask for every adb shell command except these" or "ask for
adb install without -r", and they miss forms like `adb -s SERIAL shell rm`.
This hook covers those cases; settings.json keeps the plain allow/ask/deny lists.

Decisions (deny wins over ask across the whole command line):
  deny: adb uninstall; shell/exec-out commands using rm, run-as, pm clear, pm uninstall
  ask:  any other shell/exec-out command not in SHELL_ALLOW (incl. settings put),
        adb install without -r, adb push, export_capture.py --remove-staged
Anything else gets no decision and falls through to the normal permission rules.
"""
import json
import os
import shlex
import sys

SHELL_ALLOW = [
    ["getprop"], ["dumpsys"], ["screencap"], ["screenrecord"], ["input"],
    ["am", "start"], ["am", "force-stop"], ["settings", "get"], ["ls"],
    ["pm", "list"], ["pm", "dump"],
]
OPERATORS = {";", "&", "&&", "|", "||", "(", ")", "<", ">", ">>", "|&", ";;"}
GLOBAL_OPTS_WITH_VALUE = {"-s", "-t", "-H", "-P", "-L"}


def split_commands(tokens):
    cmd = []
    for tok in tokens:
        if tok in OPERATORS or set(tok) <= set(";&|()<>"):
            if cmd:
                yield cmd
            cmd = []
        else:
            cmd.append(tok)
    if cmd:
        yield cmd


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    return list(lex)


def flatten(tokens, depth=0):
    """Re-split quoted arguments (e.g. `sh -c "rm x"`) so nested commands are seen."""
    out = []
    for tok in tokens:
        if depth < 4 and any(c.isspace() for c in tok):
            try:
                out.extend(flatten(tokenize(tok), depth + 1))
                continue
            except ValueError:
                pass
        out.append(tok)
    return out


def check_remote(args):
    """args: what follows `adb shell` / `adb exec-out`. Returns (decision, reason)."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] == "-e" else 1
    inner_text = " ".join(args[i:])
    if not inner_text.strip():
        return "ask", "interactive adb shell"
    try:
        inner = tokenize(inner_text)
    except ValueError:
        return "ask", "could not parse the remote command"
    flat = flatten(inner)
    for j, tok in enumerate(flat):
        base = os.path.basename(tok)
        if base in ("rm", "run-as"):
            return "deny", f"`{base}` on the phone is denied (study data)"
        if base == "pm" and j + 1 < len(flat) and flat[j + 1] in ("clear", "uninstall"):
            return "deny", f"`pm {flat[j + 1]}` is denied (study data)"
    cmds = list(split_commands(inner))
    if len(cmds) == 1 and any(cmds[0][:len(p)] == p for p in SHELL_ALLOW):
        if len(inner) == len(cmds[0]):  # no redirects or operators inside
            return None, None
    return "ask", f"adb shell `{inner_text}` is not on the allow list"


def check_adb(tokens):
    i = 0
    while i < len(tokens) and tokens[i].startswith("-"):
        i += 2 if tokens[i] in GLOBAL_OPTS_WITH_VALUE else 1
    if i >= len(tokens):
        return None, None
    sub, rest = tokens[i], tokens[i + 1:]
    if sub == "uninstall":
        return "deny", "adb uninstall is denied (study data on the phone)"
    if sub in ("shell", "exec-out"):
        return check_remote(rest)
    if sub in ("install", "install-multiple") and "-r" not in rest:
        return "ask", "adb install without -r replaces the app and its data"
    if sub == "push":
        return "ask", "adb push writes to the phone"
    return None, None


def decide(command):
    try:
        tokens = tokenize(command)
    except ValueError:
        return ("ask", "could not parse a command that mentions adb") if "adb" in command else (None, None)
    decisions = []
    for cmd in split_commands(tokens):
        for k, tok in enumerate(cmd):
            if os.path.basename(tok) == "adb":
                decisions.append(check_adb(cmd[k + 1:]))
                break
            if os.path.basename(tok) == "export_capture.py" and "--remove-staged" in cmd:
                decisions.append(("ask", "--remove-staged deletes the staged export on the phone"))
                break
    for wanted in ("deny", "ask"):
        for d, reason in decisions:
            if d == wanted:
                return d, reason
    return None, None


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    decision, reason = decide(data.get("tool_input", {}).get("command", ""))
    if decision:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": f"adb_guard: {reason}",
        }}))


if __name__ == "__main__":
    main()

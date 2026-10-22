#!/usr/bin/env python3
"""Pulls research-capture exports off the phone over USB (adb) and checks them.

On the phone: Settings -> Research capture -> open the session -> Summary ->
"Export for USB (adb)". That copies the session, with manifest.json
(size + SHA-256 per file), to the app-specific external folder
  /sdcard/Android/data/th.ac.kmutt.smartinsole/files/export/<sessionId>/
which adb can read on a release build (run-as can't) and other apps can't
(Android 11+). The private originals stay in the app until you delete them
there, after this script has passed and the data is backed up twice
(protocol: two copies).

For every staged session (or only --session), this script:
  1. adb pull into <dest>/.incoming/, then verifies every SHA-256;
  2. runs the load_capture.py checks and prints the report;
  3. moves it to <dest>/<sessionId>/ (never overwrites a different copy);
  4. asks before removing the staged copy from the phone (--remove-staged
     to skip the question; a failed check never removes anything).

  python3 tools/capture/export_capture.py --dest ~/smartinsole-data [--serial R58N...]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import load_capture  # noqa: E402

APP_ID = "th.ac.kmutt.smartinsole"
REMOTE = f"/sdcard/Android/data/{APP_ID}/files/export"


def adb(serial: str | None, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    cmd = ["adb"] + (["-s", serial] if serial else []) + list(args)
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def staged_sessions(serial: str | None) -> list[str]:
    r = adb(serial, "shell", "ls", "-1", REMOTE, check=False)
    if r.returncode != 0:
        if "No such file" in r.stdout + r.stderr:
            return []
        raise RuntimeError(f"adb ls failed: {(r.stderr or r.stdout).strip()}")
    return [line.strip() for line in r.stdout.splitlines() if line.strip()]


def same_files(a: Path, b: Path) -> bool:
    names = sorted(p.name for p in a.iterdir())
    if names != sorted(p.name for p in b.iterdir()):
        return False
    return all(load_capture.sha256(a / n) == load_capture.sha256(b / n) for n in names)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", type=Path, required=True, help="laptop folder for the sessions")
    ap.add_argument("--serial", help="adb device serial (adb devices -l)")
    ap.add_argument("--session", action="append", help="only this session id (repeatable)")
    ap.add_argument("--remove-staged", action="store_true",
                    help="remove the staged copy after a PASS without asking")
    args = ap.parse_args(argv)

    ids = staged_sessions(args.serial)
    if args.session:
        missing = set(args.session) - set(ids)
        if missing:
            print(f"not staged on the phone: {', '.join(sorted(missing))}")
            return 1
        ids = [i for i in ids if i in args.session]
    if not ids:
        print(f"nothing staged in {REMOTE} (tap Export in the app first)")
        return 1

    dest = args.dest.expanduser().resolve()
    incoming = dest / ".incoming"
    all_ok = True
    for sid in ids:
        print(f"\n## {sid}")
        if incoming.exists():
            shutil.rmtree(incoming)
        incoming.mkdir(parents=True)
        adb(args.serial, "pull", f"{REMOTE}/{sid}", str(incoming))
        pulled = incoming / sid
        problems = load_capture.verify_manifest(pulled)
        if problems:
            print("  FAIL  checksums: " + "; ".join(problems))
            all_ok = False
            continue
        print("  ok    every SHA-256 matches manifest.json")
        session = load_capture.load_session(pulled)
        passed = load_capture.print_report(session, load_capture.check_session(session))

        final = dest / sid
        if final.exists():
            if same_files(final, pulled):
                print(f"  ok    {final} already holds this exact export")
                shutil.rmtree(pulled)
            else:
                # A newer export of the same session (e.g. after a redo):
                # keep both, never overwrite.
                n = 2
                while (dest / f"{sid}.export{n}").exists():
                    n += 1
                final = dest / f"{sid}.export{n}"
                pulled.rename(final)
                print(f"  note  differs from the earlier copy; saved as {final}")
        else:
            pulled.rename(final)
            print(f"  saved {final}")

        if not passed:
            all_ok = False
            print("  kept on the phone (a check failed)")
            continue
        remove = args.remove_staged or input(
            f"  remove the staged copy {REMOTE}/{sid} from the phone? [y/N] "
        ).strip().lower() == "y"
        if remove:
            adb(args.serial, "shell", "rm", "-r", f"{REMOTE}/{sid}")
            print("  removed the staged copy (the app's private originals are untouched)")
    if incoming.exists():
        shutil.rmtree(incoming)
    print("\nNext: back up", dest, "to a second place, then delete the session in the app.")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

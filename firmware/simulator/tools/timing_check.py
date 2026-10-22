#!/usr/bin/env python3
"""Check the S4 Note 10 timing run: the phone app's timing log against both
simulator boards' serial logs.

The app (debug screen -> Timing check) writes one line per event:

  SYNC t=<phone ms> side=L session=2 U=<unix ms sent> A=<offset ms> ...
  FOOT t=<phone ms> side=L state=streaming session=2 pkts= lost= ... \
       stepMin= stepMax= clamps= ...

and the simulator logs every SYNC_TIME it handles as
`[ctl] conn N: SYNC_TIME unix U ms at device D ms`.

L/R alignment (contract section 4, +-10 ms), without a shared clock. For
one foot the app maps device time to unix time with offset A = theta + n,
where theta is the true offset and n >= 0 the least notification latency
its minimum filter found (mobile/lib/device/device_clock.dart). A SYNC_TIME
sent at phone time U and handled at device time D gives U - D = theta - w,
where w >= 0 is the write's latency. So B = A - (U - D) = n + w >= n: each
bracket B bounds that foot's mapping error n from above (and 0 from
below). The L/R alignment error n_L - n_R therefore lies in [-B_R, B_L].
w varies from write to write (up to a connection interval) while n moves
slowly, so the bound used is the smallest B in each --window-s window (a
window with fewer than 6 writes is folded into the one before); the run
passes when, in every window, both feet's bound is <= --max-ms. U is
the key that joins the two logs (the app writes it, the board echoes it).

Other checks, per foot, over the run:
- lost packets 0 (seq gaps and a lost start of stream), no new parser
  rejections, no new rule-9 drops before START or out of order;
- every step between consecutive sample times within 20 +- --step-tol-ms;
- clock clamps 0;
- the board's own counters: notify failures and mtu-drops unchanged.

Exits non-zero on FAIL.

    /usr/bin/python3 tools/timing_check.py --selftest
    /usr/bin/python3 tools/timing_check.py timing-20261022-....log \\
        --serial-left left.log --serial-right right.log
    /usr/bin/python3 tools/timing_check.py timing-....log --app-only
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
from dataclasses import dataclass, field

SYNC_RE = re.compile(r"SYNC_TIME unix (\d+) ms at device (\d+) ms")
SESS_CONN_RE = re.compile(r"\[sess\] conn \d+ .* sent (\d+) mtu-drops (\d+)")
SESS_ALL_RE = re.compile(r"\[sess\] \d+ connected, .*notify failures (\d+)")


def fields(line: str) -> dict[str, str]:
    return dict(kv.split("=", 1) for kv in line.split()[1:] if "=" in kv)


def num(v: str | None) -> float | None:
    if v is None or v == "na":
        return None
    return float(v)


@dataclass
class Serial:
    sync: dict[int, int] = field(default_factory=dict)  # U -> D
    notify_failures: list[int] = field(default_factory=list)
    mtu_drops: list[int] = field(default_factory=list)
    sent: list[int] = field(default_factory=list)


def parse_serial(lines: list[str]) -> Serial:
    s = Serial()
    for line in lines:
        if m := SYNC_RE.search(line):
            s.sync[int(m.group(1))] = int(m.group(2))
        elif m := SESS_CONN_RE.search(line):
            s.sent.append(int(m.group(1)))
            s.mtu_drops.append(int(m.group(2)))
        elif m := SESS_ALL_RE.search(line):
            s.notify_failures.append(int(m.group(1)))
    return s


@dataclass
class FootResult:
    side: str
    lines: list[str] = field(default_factory=list)
    fails: list[str] = field(default_factory=list)
    window_bounds: dict[int, float] = field(default_factory=dict)

    def ok(self) -> bool:
        return not self.fails


def check(
    app_lines: list[str],
    serial: dict[str, Serial | None],
    max_ms: float = 10.0,
    step_tol_ms: float = 1.0,
    window_s: float = 120.0,
    min_minutes: float = 0.0,
    min_brackets: int = 6,
    app_only: bool = False,
) -> tuple[bool, list[str]]:
    out: list[str] = []
    syncs = [fields(l) for l in app_lines if l.startswith("SYNC ")]
    feet = [fields(l) for l in app_lines if l.startswith("FOOT ")]
    start = next((fields(l) for l in app_lines if l.startswith("START ")), None)
    stop = next((fields(l) for l in app_lines if l.startswith("STOP ")), None)
    ok = True
    if start is None or stop is None:
        out.append("FAIL: the log has no START or no STOP line")
        return False, out
    t0, t1 = int(start["t"]), int(stop["t"])
    minutes = (t1 - t0) / 60000
    out.append(f"run: {minutes:.1f} min")
    if minutes < min_minutes:
        out.append(f"FAIL: run shorter than {min_minutes} min")
        ok = False

    results: dict[str, FootResult] = {}
    for side in ("L", "R"):
        r = FootResult(side)
        results[side] = r
        mine = [f for f in feet if f["side"] == side]
        if not mine:
            r.fails.append("no FOOT lines")
            continue
        first, last = mine[0], mine[-1]

        # Continuity and drops, as deltas over the run.
        sessions = sorted({f["session"] for f in mine})
        lost = sum(
            int([f for f in mine if f["session"] == s][-1]["lost"])
            for s in sessions
        )
        if lost:
            r.fails.append(f"{lost} packets lost")
        for key, label in (
            ("gaps", "seq gaps"),
            ("missingAtStart", "missing at start"),
            ("rejects", "parser rejections"),
            ("beforeStart", "dropped before START"),
            ("notForward", "t0 not forward"),
            ("oldConn", "from an old connection"),
            ("linkLosses", "link losses"),
        ):
            d = int(last[key]) - int(first[key])
            if d:
                r.fails.append(f"{label} +{d}")
        not_streaming = [f for f in mine if f["state"] != "streaming"]
        if not_streaming:
            r.fails.append(
                f"{len(not_streaming)} FOOT lines not streaming "
                f"({sorted({f['state'] for f in not_streaming})})"
            )
        clamps = max(int(f["clamps"]) for f in mine)
        if clamps:
            r.fails.append(f"clock clamps {clamps}")
        lo = [num(f["stepMin"]) for f in mine if num(f["stepMin"]) is not None]
        hi = [num(f["stepMax"]) for f in mine if num(f["stepMax"]) is not None]
        if lo and hi:
            step_lo, step_hi = min(lo), max(hi)
            if step_lo < 20 - step_tol_ms or step_hi > 20 + step_tol_ms:
                r.fails.append(
                    f"sample step {step_lo:.3f}-{step_hi:.3f} ms outside "
                    f"20 +- {step_tol_ms}"
                )
        else:
            step_lo = step_hi = float("nan")
        pkts = sum(
            int([f for f in mine if f["session"] == s][-1]["pkts"])
            for s in sessions
        )
        r.lines.append(
            f"{side}: sessions {','.join(sessions)} · pkts {pkts} · lost {lost}"
            f" · step {step_lo:.3f}-{step_hi:.3f} ms · clamps {clamps} · "
            f"admitted before START ack {last['admittedBeforeAck']}"
        )

        # The board's side.
        s = serial.get(side)
        if s is None:
            if app_only:
                r.lines.append(f"{side}: no serial log, bracket not checked")
            else:
                r.fails.append("no serial log (--app-only to check the app side alone)")
            continue
        if s.notify_failures and s.notify_failures[-1] != s.notify_failures[0]:
            r.fails.append(
                f"board notify failures {s.notify_failures[0]} -> "
                f"{s.notify_failures[-1]}"
            )
        if s.mtu_drops and max(s.mtu_drops):
            r.fails.append(f"board mtu-drops {max(s.mtu_drops)}")
        if s.sent:
            r.lines.append(f"{side}: board sent (last [sess] line) {s.sent[-1]}")

        # Brackets.
        brackets: list[tuple[int, float]] = []
        unmatched = 0
        for f in syncs:
            if f["side"] != side or f.get("clock_session") != f["session"]:
                continue
            a = num(f["A"])
            if a is None:
                continue
            u = int(f["U"])
            d = s.sync.get(u)
            if d is None:
                unmatched += 1
                continue
            brackets.append((int(f["t"]), a - (u - d)))
        if unmatched:
            r.lines.append(f"{side}: {unmatched} SYNC lines not in the serial log")
        if not brackets:
            r.fails.append("no SYNC_TIME bracket (serial log matched nothing)")
            continue
        bs = [b for _, b in brackets]
        if min(bs) < -1:
            r.fails.append(
                f"bracket {min(bs):.3f} ms < 0: the offset is earlier than "
                "the true one, which the method rules out; check the logs"
            )
        groups: dict[int, list[float]] = {}
        for t, b in brackets:
            groups.setdefault(int((t - t0) // (window_s * 1000)), []).append(b)
        # A window with too few writes can't find one with a short w: fold
        # it into the window before.
        for w in sorted(groups):
            if len(groups[w]) < min_brackets and w - 1 in groups:
                groups[w - 1] += groups.pop(w)
        r.window_bounds = {w: min(v) for w, v in groups.items()}
        worst = max(r.window_bounds.values())
        r.lines.append(
            f"{side}: {len(bs)} brackets B = A - (U - D): min {min(bs):.2f} · "
            f"median {statistics.median(bs):.2f} · max {max(bs):.2f} ms; "
            f"per-{window_s:.0f}-s-window bound: worst {worst:.2f} ms"
        )
        if worst > max_ms:
            r.fails.append(f"clock error bound {worst:.2f} ms > {max_ms} ms")

    for r in results.values():
        out.extend(r.lines)
        for f in r.fails:
            out.append(f"FAIL {r.side}: {f}")
        ok &= r.ok()

    lb, rb = results["L"].window_bounds, results["R"].window_bounds
    common = sorted(set(lb) & set(rb))
    if common:
        out.append(
            "L/R alignment error bound per window (ms): "
            + " ".join(f"{max(lb[w], rb[w]):.1f}" for w in common)
        )
        worst = max(max(lb[w], rb[w]) for w in common)
        out.append(
            f"L/R alignment: |error| <= {worst:.2f} ms "
            f"({'within' if worst <= max_ms else 'OUTSIDE'} +-{max_ms} ms)"
        )
    out.append("PASS" if ok else "FAIL")
    return ok, out


# --- self-test -------------------------------------------------------------


def _synth(
    n_ms: float = 3.0,
    w_ms: tuple[float, float] = (1.0, 11.0),
    lost: int = 0,
    step_max: float = 20.25,
    minutes: int = 10,
    drift: float = 0.0,
):
    """An app log and two serial logs with known theta, n and w."""
    import random

    rnd = random.Random(7)
    base = 1792605700000  # phone unix ms at START
    app = ["# smartinsole timing log v1", f"START t={base} probe_s=10 line_s=10"]
    serial = {"L": [], "R": []}
    theta = {"L": 1792605000000.0, "R": 1792601000000.0}
    for k in range(1, minutes * 6 + 1):
        t = base + k * 10000
        for side in ("L", "R"):
            th = theta[side] + drift * k
            a = th + n_ms
            u = t + (0 if side == "L" else 3)
            w = rnd.uniform(*w_ms)
            d = int(u + w - th)
            serial[side].append(
                f"10:00:00.000 [ctl] conn 0: SYNC_TIME unix {u} ms at device "
                f"{d} ms"
            )
            app.append(
                f"SYNC t={u} side={side} session=1 U={u} A={a:.3f} "
                f"target={a:.3f} clock_session=1"
            )
        for side in ("L", "R"):
            app.append(
                f"FOOT t={t} side={side} state=streaming session=1 "
                f"pkts={k * 62} lost={lost if k > 3 else 0} seq={k * 62 - 1} "
                "missingAtStart=0 gaps=0 gapMissing=0 beforeStart=0 "
                "admittedBeforeAck=1 oldConn=0 notForward=0 rejects=0 "
                f"A=1.0 target=1.0 excess=2.0 stepMin=19.75 "
                f"stepMax={step_max} clamps=0 sessions=1 linkLosses=0"
            )
    app.append(f"STOP t={base + minutes * 60000 + 1}")
    for side in ("L", "R"):
        serial[side] += [
            "10:00:10.000 [sess] conn 0 mtu 247 (8/pkt) streaming "
            "sub[s1 t1 st1] sent 62 mtu-drops 0 synced",
            "10:00:10.005 [sess] 1 connected, battery 96%, notify failures 0,"
            " heap 1",
        ]
    return app, {s: parse_serial(v) for s, v in serial.items()}


def selftest() -> int:
    cases = [
        ("clean run passes", {}, True),
        ("a large n fails the bound", {"n_ms": 12.0}, False),
        ("write latency jitter alone doesn't fail it (window minimum)",
         {"w_ms": (0.5, 15.0)}, True),
        ("40 ppm drift on both boards passes", {"drift": 0.4}, True),
        ("a lost packet fails", {"lost": 1}, False),
        ("a step outside 20 +- 1 fails", {"step_max": 21.5}, False),
        ("too short fails with --min-minutes", {"minutes": 2}, False),
    ]
    failed = 0
    for name, kw, expect in cases:
        app, serial = _synth(**kw)
        ok, out = check(app, serial, min_minutes=5)
        good = ok == expect
        failed += not good
        print(f"{'ok  ' if good else 'BAD '} {name}")
        if not good:
            print("\n".join("     " + l for l in out))
    # A U the board never logged is reported, not silently bracketed.
    app, serial = _synth()
    serial["L"].sync.clear()
    ok, out = check(app, serial)
    good = not ok and any("not in the serial log" in l for l in out)
    failed += not good
    print(f"{'ok  ' if good else 'BAD '} unmatched SYNC lines are reported")
    # No serial log is a FAIL unless asked for the app side only.
    app, _ = _synth()
    ok_missing, _ = check(app, {"L": None, "R": None})
    ok_app_only, _ = check(app, {"L": None, "R": None}, app_only=True)
    good = not ok_missing and ok_app_only
    failed += not good
    print(f"{'ok  ' if good else 'BAD '} a missing serial log fails unless --app-only")
    print(f"selftest: {'PASS' if not failed else f'{failed} FAILED'}")
    return 1 if failed else 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("app_log", nargs="?")
    p.add_argument("--serial-left")
    p.add_argument("--serial-right")
    p.add_argument("--max-ms", type=float, default=10.0)
    p.add_argument("--step-tol-ms", type=float, default=1.0)
    p.add_argument("--window-s", type=float, default=120.0)
    p.add_argument("--min-minutes", type=float, default=10.0)
    p.add_argument(
        "--app-only",
        action="store_true",
        help="check the app log alone (no L/R bound; never the checkpoint)",
    )
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        return selftest()
    if not a.app_log:
        p.error("app_log is required")

    def read(path: str | None) -> list[str] | None:
        if path is None:
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()

    serial = {
        side: (parse_serial(lines) if (lines := read(path)) is not None else None)
        for side, path in (("L", a.serial_left), ("R", a.serial_right))
    }
    ok, out = check(
        read(a.app_log) or [],
        serial,
        max_ms=a.max_ms,
        step_tol_ms=a.step_tol_ms,
        window_s=a.window_s,
        min_minutes=a.min_minutes,
        app_only=a.app_only,
    )
    print("\n".join(out))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

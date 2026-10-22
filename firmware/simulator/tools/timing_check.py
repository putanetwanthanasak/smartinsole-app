#!/usr/bin/env python3
"""Check the S4 Note 10 timing run: the phone app's timing log against both
simulator boards' serial logs.

The app (debug screen -> Timing check) writes one line per event:

  SYNC t=<phone ms> side=L session=2 U=<unix ms sent> A=<offset ms> ...
  FOOT t=<phone ms> side=L state=streaming session=2 pkts= lost= ... \
       stepMin= stepMax= clamps= ...

and the simulator logs every SYNC_TIME it handles as
`[ctl] conn N: SYNC_TIME unix U ms at device D ms`.

L/R alignment (contract section 4, +-10 ms), primary check: the laptop
clock. Both boards' serial logs are stamped by one laptop clock
(serial_log.py, HH:MM:SS.mmm), so each SYNC_TIME line gives that board's
offset phi = laptop - D, plus a print/USB delay >= 0. Per board, phi's
linear drift (the board's crystal against the laptop) is fitted through
the --window-s minima and removed, and the floor over +-window/2 is taken
(the minimum delay). For the same instant, the app's unix times of the two
feet then differ by

    e = (phi_R - phi_L) + A_L - A_R

where A is each foot's offset (unix - device) from the app log; the right
foot's phi and A are interpolated to each left SYNC time. The run passes
when |e| <= --max-ms in every window. Uncertainty (printed): +-1 ms each
for the integer D (millis), the laptop stamp and USB frame, and the
board's sample stamps (t0 + 20 k) against millis(), plus the difference in
SYNC line length at 115200 baud; summed as a worst case, about +-3 ms.

Secondary figure, not part of the verdict: the write-latency bound. For one
foot the app's offset is A = theta + n (theta the true offset, n >= 0 the
least notification latency the minimum filter found,
mobile/lib/device/device_clock.dart). A SYNC_TIME sent at phone time U and
handled at device time D gives U - D = theta - w (w >= 0 the write's
latency), so B = A - (U - D) = n + w bounds n from above. It needs no
laptop clock, but it can't go below the write latency: on the Note 10 at
the S4 checkpoint the write took 29-139 ms, so B never got near 10 ms
(docs/reports/026-*.md). It was the primary check until that run.

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
LAPTOP_RE = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d{3}) ")
DAY_MS = 86_400_000
BAUD_MS_PER_BYTE = 10 / 115200 * 1000  # 8N1 at 115200
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
    laptop: dict[int, int] = field(default_factory=dict)  # U -> laptop ms
    line_len: dict[int, int] = field(default_factory=dict)  # U -> bytes
    notify_failures: list[int] = field(default_factory=list)
    mtu_drops: list[int] = field(default_factory=list)
    sent: list[int] = field(default_factory=list)


def parse_serial(lines: list[str]) -> Serial:
    s = Serial()
    day = 0
    prev = None
    for line in lines:
        lap = None
        if t := LAPTOP_RE.match(line):
            h, mi, sec, ms = (int(g) for g in t.groups())
            lap = ((h * 60 + mi) * 60 + sec) * 1000 + ms
            if prev is not None and lap + day < prev - DAY_MS // 2:
                day += DAY_MS  # past midnight
            lap += day
            prev = lap
        if m := SYNC_RE.search(line):
            u = int(m.group(1))
            s.sync[u] = int(m.group(2))
            if lap is not None:
                s.laptop[u] = lap
                s.line_len[u] = len(line) - LAPTOP_RE.match(line).end()
        elif m := SESS_CONN_RE.search(line):
            s.sent.append(int(m.group(1)))
            s.mtu_drops.append(int(m.group(2)))
        elif m := SESS_ALL_RE.search(line):
            s.notify_failures.append(int(m.group(1)))
    return s


def _interp(xs: list[float], ys: list[float], x: float) -> float | None:
    if not xs or x < xs[0] or x > xs[-1]:
        return None
    for i in range(1, len(xs)):
        if x <= xs[i]:
            x0, x1 = xs[i - 1], xs[i]
            f = 0 if x1 == x0 else (x - x0) / (x1 - x0)
            return ys[i - 1] + f * (ys[i] - ys[i - 1])
    return ys[-1]


def board_floor(ts: list[float], phis: list[float], window_s: float):
    """Per event: the board's phi with the print/USB delay removed (a drift-
    corrected floor), plus the fitted drift in ppm."""
    win = window_s * 1000
    t0 = ts[0]
    # Drift: a line through each window's minimum.
    mins: dict[int, tuple[float, float]] = {}
    for t, p in zip(ts, phis):
        k = int((t - t0) // win)
        if k not in mins or p < mins[k][1]:
            mins[k] = (t, p)
    pts = list(mins.values())
    slope = 0.0
    if len(pts) >= 2:
        mt = statistics.fmean(t for t, _ in pts)
        mp = statistics.fmean(p for _, p in pts)
        den = sum((t - mt) ** 2 for t, _ in pts)
        if den:
            slope = sum((t - mt) * (p - mp) for t, p in pts) / den
    resid = [p - slope * (t - t0) for t, p in zip(ts, phis)]
    floor = []
    for t in ts:
        near = [r for tt, r in zip(ts, resid) if abs(tt - t) <= win / 2]
        floor.append(min(near) + slope * (t - t0))
    return floor, slope * 1e6


def laptop_alignment(
    syncs: list[dict[str, str]],
    serial: dict[str, Serial | None],
    t0: int,
    window_s: float,
    max_ms: float,
) -> tuple[bool, list[str]]:
    out: list[str] = []
    per: dict[str, tuple[list[float], list[float], list[float]]] = {}
    jitter: dict[str, list[float]] = {}
    lens: dict[str, list[int]] = {}
    for side in ("L", "R"):
        s = serial.get(side)
        if s is None:
            return False, [f"L/R (laptop clock): no {side} serial log"]
        rows = []
        for f in syncs:
            if f["side"] != side or f.get("clock_session") != f["session"]:
                continue
            a, u = num(f["A"]), int(f["U"])
            if a is None or u not in s.laptop or u not in s.sync:
                continue
            rows.append((u, a, s.laptop[u] - s.sync[u]))
        if len(rows) < 6:
            return False, [
                f"L/R (laptop clock): only {len(rows)} {side} SYNC_TIME lines "
                "with a laptop timestamp (serial_log.py output needed)"
            ]
        ts = [float(u) for u, _, _ in rows]
        phis = [float(p) for _, _, p in rows]
        floor, ppm = board_floor(ts, phis, window_s)
        per[side] = (ts, [a for _, a, _ in rows], floor)
        jitter[side] = sorted(p - fl for p, fl in zip(phis, floor))
        lens[side] = [s.line_len[u] for u, _, _ in rows]
        j = jitter[side]
        out.append(
            f"{side}: {len(rows)} SYNC_TIME lines on the laptop clock; drift "
            f"{ppm:+.1f} ppm vs laptop; delay above floor median "
            f"{statistics.median(j):.1f}, p90 {j[int(0.9 * (len(j) - 1))]:.1f} ms"
        )

    tl, al, fl = per["L"]
    tr, ar, fr = per["R"]
    errs: list[tuple[float, float]] = []
    for t, a, f in zip(tl, al, fl):
        a_r, f_r = _interp(tr, ar, t), _interp(tr, fr, t)
        if a_r is None or f_r is None:
            continue
        errs.append((t, (f_r - f) + a - a_r))
    if not errs:
        return False, out + ["L/R (laptop clock): the two feet's SYNC times don't overlap"]
    win = window_s * 1000
    windows: dict[int, list[float]] = {}
    for t, e in errs:
        windows.setdefault(int((t - t0) // win), []).append(e)
    worst = max(abs(e) for _, e in errs)
    es = sorted(e for _, e in errs)
    line_ms = abs(statistics.fmean(lens["L"]) - statistics.fmean(lens["R"])) * BAUD_MS_PER_BYTE
    unc = 3.0 + line_ms
    out.append(
        f"L/R error e = unix_L - unix_R for one instant, {len(errs)} points: "
        f"min {es[0]:+.2f} · median {statistics.median(es):+.2f} · "
        f"max {es[-1]:+.2f} ms"
    )
    out.append(
        f"per-{window_s:.0f}-s window, max |e| (ms): "
        + " ".join(f"{max(abs(e) for e in v):.1f}" for _, v in sorted(windows.items()))
    )
    out.append(
        f"uncertainty +-{unc:.1f} ms (worst-case sum: D 1 + laptop stamp/USB "
        f"1 + sample stamp 1 + line length {line_ms:.2f})"
    )
    ok = worst <= max_ms
    out.append(
        f"L/R alignment (laptop clock): |e| <= {worst:.2f} ms, "
        f"{'within' if ok else 'OUTSIDE'} +-{max_ms} ms; with the uncertainty "
        f"<= {worst + unc:.2f} ms"
        + ("" if worst + unc <= max_ms else " (above the limit at the edge of the uncertainty)")
    )
    return ok, out


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
            r.fails.append("no SYNC_TIME matched in the serial log")
            continue
        bs = [b for _, b in brackets]
        if min(bs) < -1:
            r.lines.append(
                f"{side}: WARNING bracket {min(bs):.3f} ms < 0: the offset is "
                "earlier than the true one, which the method rules out"
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
            f"{side}: (secondary) {len(bs)} brackets B = A - (U - D) = n + w: "
            f"min {min(bs):.2f} · median {statistics.median(bs):.2f} · "
            f"max {max(bs):.2f} ms; per-{window_s:.0f}-s-window bound: worst "
            f"{worst:.2f} ms"
        )

    for r in results.values():
        out.extend(r.lines)
        for f in r.fails:
            out.append(f"FAIL {r.side}: {f}")
        ok &= r.ok()

    lb, rb = results["L"].window_bounds, results["R"].window_bounds
    common = sorted(set(lb) & set(rb))
    if common:
        worst = max(max(lb[w], rb[w]) for w in common)
        out.append(
            "(secondary) write-latency bound on |L/R error| per window (ms): "
            + " ".join(f"{max(lb[w], rb[w]):.1f}" for w in common)
            + f"; worst {worst:.2f} (not part of the verdict: it can't go "
            "below the write latency)"
        )
    if not app_only or all(serial.get(s) is not None for s in ("L", "R")):
        lr_ok, lr = laptop_alignment(syncs, serial, t0, window_s, max_ms)
        out.extend(lr)
        if not lr_ok:
            out.append("FAIL L/R: alignment (laptop clock)")
        ok &= lr_ok
    out.append("PASS" if ok else "FAIL")
    return ok, out


# --- self-test -------------------------------------------------------------


def _synth(
    n_ms: tuple[float, float] = (3.0, 3.0),
    w_ms: tuple[float, float] = (1.0, 11.0),
    lost: int = 0,
    step_max: float = 20.25,
    minutes: int = 10,
    ppm: tuple[float, float] = (0.0, 0.0),
    usb_ms: tuple[float, float] = (6.0, 9.0),
):
    """An app log and two serial logs with known theta, n, w, drift and
    print/USB delay. Phone and laptop clocks are ideal; the boards drift."""
    import random

    rnd = random.Random(7)
    base = 1792605700000  # phone unix ms at START
    lap0 = 36_000_000 - base  # laptop ms of day = phone ms + lap0 (10:00)
    app = ["# smartinsole timing log v1", f"START t={base} probe_s=10 line_s=10"]
    serial = {"L": [], "R": []}
    theta0 = {"L": 1792605000000.0, "R": 1792601000000.0}
    n = dict(zip("LR", n_ms))
    drift = dict(zip("LR", ppm))

    def theta(side: str, t: float) -> float:
        return theta0[side] + drift[side] * 1e-6 * (t - base)

    def stamp(ms: float) -> str:
        ms = int(ms) % DAY_MS
        return (
            f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:"
            f"{ms // 1000 % 60:02d}.{ms % 1000:03d}"
        )

    for k in range(1, minutes * 6 + 1):
        t = base + k * 10000
        for side in ("L", "R"):
            u = t + (0 if side == "L" else 1)
            a = theta(side, u) + n[side]
            th = u + rnd.uniform(*w_ms)  # handled on the board
            d = int(th - theta(side, th))
            lap = th + lap0 + rnd.uniform(*usb_ms)
            serial[side].append(
                f"{stamp(lap)} [ctl] conn 0: SYNC_TIME unix {u} ms at device "
                f"{d} ms"
            )
            app.append(
                f"SYNC t={u + 30} side={side} session=1 U={u} A={a:.3f} "
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
        ("feet 13 ms apart fail", {"n_ms": (3.0, 16.0)}, False),
        ("feet 6 ms apart pass", {"n_ms": (3.0, 9.0)}, True),
        ("the same large n on both feet passes (it cancels)",
         {"n_ms": (12.0, 12.0)}, True),
        ("Note 10 write latency (29-139 ms) alone doesn't fail it",
         {"w_ms": (29.0, 139.0)}, True),
        ("boards drifting +30 / -10 ppm vs the laptop pass",
         {"ppm": (30.0, -10.0)}, True),
        ("drift with feet 13 ms apart still fails",
         {"ppm": (30.0, -10.0), "n_ms": (3.0, 16.0)}, False),
        ("USB delay jitter 1-25 ms alone doesn't fail it",
         {"usb_ms": (1.0, 25.0)}, True),
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
    # Serial logs without laptop timestamps can't give the primary check.
    app, _ = _synth()
    bare = {
        side: parse_serial(
            [f"[ctl] conn 0: SYNC_TIME unix {u} ms at device {d} ms"
             for u, d in serial_s.sync.items()]
        )
        for side, serial_s in _synth()[1].items()
    }
    ok, out = check(app, bare)
    good = not ok and any("laptop timestamp" in l for l in out)
    failed += not good
    print(f"{'ok  ' if good else 'BAD '} serial lines without laptop time fail")
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
        help="check the app log alone (no L/R check; never the checkpoint)",
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

#!/usr/bin/env python3
"""Check a research-capture CSV exported by the (frozen) laptop web app.

The web app's CSV schema is fixed and has no `seq` column, so missing
packets are inferred from the `tUnixMs` timeline instead. `tUnixMs` is the
device time of each sample (t0_ms + i x 20, contract rule 1) plus one clock
offset per connection, so between offset changes consecutive rows of one
foot are exactly 20 ms apart, and a lost 8-sample packet shows up as a
20 + 160 ms step.

The web app also re-estimates its offset with SYNC_TIME every 5 minutes
(RESYNC_INTERVAL_MS in src/ts/data/bleProtocol.ts) as "send time - device
time of the last sample received". The first re-estimate of a connection
puts a step of any size into `tUnixMs`. Every later one is exactly
20 + 160 k ms: Chrome's timer sends exactly 300 000 ms apart, which is
exactly 1 875 packets, so the step only counts how many more (k > 0) or
fewer (k < 0, time goes backwards) packets had arrived at send time than
5 minutes earlier (docs/reports/025-*.md). No data is lost by such a step,
but it looks exactly like a lost packet. The simulator logs each SYNC_TIME
it receives as `unix <ms>`, so with --serial-left/--serial-right every
non-20 ms step is matched against a logged SYNC_TIME instead of being
guessed at. A matched step of 20 + 160 k ms is reported AMBIGUOUS: settle
it with the web app dev panel (no loss on the connection when
`pkts` = `seq` + 1 and `dropped=0`).

--write-corrected OUT writes the same CSV with those steps undone within
each take, so each foot keeps the offset it had at the start of the take
and every step inside a take is 20 ms. Breaks are not touched, and a
resync that fell between two takes can't be seen or undone. Steps of
20 + 160 k ms are undone only with --assume-no-loss (dev panel checked).

Verdict per foot, FAIL on any of: no rows, an inferred packet loss, a step
<= 0 (time order broken), a non-20 ms step with no SYNC_TIME match (only
judged when that foot's serial log is given), a rate outside 50 Hz +- 1 %.
Both feet must cover the same span (start and end within --span-tol-s).
Steps longer than --break-s are listed as breaks (a take boundary or a
link gap: the CSV can't tell which); --single-take turns them into FAILs.
Exits non-zero on FAIL.

    /usr/bin/python3 tools/webapp_csv_check.py --selftest
    /usr/bin/python3 tools/webapp_csv_check.py ~/Downloads/TEST-S3B_....csv \
        --serial-left left.log --serial-right right.log --single-take
    /usr/bin/python3 tools/webapp_csv_check.py IN.csv --assume-no-loss \
        --write-corrected OUT.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

SAMPLE_PERIOD_MS = 20  # contract rule 1: sample i = t0 + i x 20 ms
RATE_HZ = 1000 / SAMPLE_PERIOD_MS
RATE_TOL = 0.01
SYNC_MATCH_MS = 2000

# src/ts/capture/types.ts CSV_COLUMNS, in order.
CSV_COLUMNS = [
    "subjectId", "sessionId", "tUnixMs", "side", "gaitLabel", "isValid",
    "fsr_hallux", "fsr_meta1", "fsr_meta3", "fsr_meta5", "fsr_midfoot", "fsr_heel",
    "accel_x", "accel_y", "accel_z", "gyro_x", "gyro_y", "gyro_z",
]
SIDES = {"L": "left", "R": "right"}

SERIAL_LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d{3}) (.*)$")
SYNC_RE = re.compile(r"\[ctl\] conn (\d+): SYNC_TIME unix (\d+) ms at device (\d+) ms")
CONN_RE = re.compile(r"\[ble\] conn (\d+): (connected \S+|disconnected.*)")
SENT_RE = re.compile(r"\[sess\] conn (\d+) .*\b(streaming|idle)\b.* sent (\d+) mtu-drops (\d+)")
NOTIFY_RE = re.compile(r"notify failures (\d+)")


@dataclass
class Serial:
    syncs: list[tuple[str, int, int]] = field(default_factory=list)  # (time, conn, unix ms)
    conn_events: list[str] = field(default_factory=list)
    last_sent: dict[int, tuple[str, str, int, int]] = field(default_factory=dict)
    notify_failures_max: int = 0


def parse_serial(lines: list[str]) -> Serial:
    s = Serial()
    for raw in lines:
        m = SERIAL_LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        t, text = m.groups()
        if (g := SYNC_RE.search(text)):
            s.syncs.append((t, int(g[1]), int(g[2])))
        if (g := CONN_RE.search(text)):
            s.conn_events.append(f"{t} conn {g[1]}: {g[2]}")
        if (g := SENT_RE.search(text)):
            s.last_sent[int(g[1])] = (t, g[2], int(g[3]), int(g[4]))
        if (g := NOTIFY_RE.search(text)):
            s.notify_failures_max = max(s.notify_failures_max, int(g[1]))
    return s


@dataclass
class Event:
    row: int          # index of the row AFTER the step, within this foot
    t_ms: float
    step_ms: float
    kind: str         # 'lost', 'backwards', 'offset', 'break'
    lost_packets: int = 0
    sync: tuple[str, int, int] | None = None
    verdict: str = ""  # 'ok', 'AMBIGUOUS', 'FAIL', 'break'


@dataclass
class FootResult:
    side: str
    rows: int
    first_ms: float | None = None
    last_ms: float | None = None
    rate_hz: float | None = None
    steps: Counter = field(default_factory=Counter)
    events: list[Event] = field(default_factory=list)
    win_min: int | None = None
    win_max: int | None = None
    labels: Counter = field(default_factory=Counter)
    invalid_rows: int = 0
    fails: list[str] = field(default_factory=list)


def analyse_foot(side: str, times: list[float], labels: list[str], valid: list[bool],
                 serial: Serial | None, samples_per_packet: int, break_ms: float,
                 single_take: bool) -> FootResult:
    r = FootResult(side=side, rows=len(times))
    r.labels = Counter(labels)
    r.invalid_rows = valid.count(False)
    if not times:
        r.fails.append("no rows")
        return r
    r.first_ms, r.last_ms = times[0], times[-1]
    packet_ms = samples_per_packet * SAMPLE_PERIOD_MS
    syncs = serial.syncs if serial else []

    active_ms = 0.0  # time covered by the stream, breaks excluded
    for i in range(1, len(times)):
        step = times[i] - times[i - 1]
        r.steps[round(step, 1)] += 1
        if step == SAMPLE_PERIOD_MS:
            active_ms += step
            continue
        ev = Event(row=i, t_ms=times[i], step_ms=step, kind="offset")
        if step > break_ms:
            ev.kind = "break"
        else:
            active_ms += step
            if step <= 0:
                ev.kind = "backwards"
            elif (step - SAMPLE_PERIOD_MS) % packet_ms == 0:
                ev.kind = "lost"
                ev.lost_packets = int((step - SAMPLE_PERIOD_MS) // packet_ms)
        if syncs and ev.kind != "break":
            near = min(syncs, key=lambda s: abs(s[2] - ev.t_ms))
            if abs(near[2] - ev.t_ms) <= SYNC_MATCH_MS:
                ev.sync = near
        if ev.kind == "break":
            ev.verdict = "FAIL" if single_take else "break"
        elif ev.kind == "backwards":
            ev.verdict = "FAIL"
        elif ev.kind == "lost":
            ev.verdict = "AMBIGUOUS" if ev.sync else "FAIL"
        elif serial is not None:
            ev.verdict = "ok" if ev.sync else "FAIL"
        else:
            ev.verdict = "ok"  # no serial log: an offset step can't be judged
        r.events.append(ev)

    span_s = (active_ms + SAMPLE_PERIOD_MS) / 1000
    r.rate_hz = len(times) / span_s
    if abs(r.rate_hz - RATE_HZ) > RATE_HZ * RATE_TOL:
        r.fails.append(f"rate {r.rate_hz:.2f} Hz outside {RATE_HZ:g} Hz +- {RATE_TOL:.0%}")

    buckets = Counter(int((t - times[0]) // 10_000) for t in times)
    full = [buckets[k] for k in sorted(buckets)][1:-1]  # drop the partial first and last
    if full:
        r.win_min, r.win_max = min(full), max(full)

    for ev in r.events:
        if ev.verdict == "FAIL":
            what = {"lost": f"{ev.lost_packets} packet(s) lost (step {ev.step_ms:g} ms, no SYNC_TIME near)",
                    "backwards": f"time went backwards (step {ev.step_ms:g} ms)",
                    "offset": f"step {ev.step_ms:g} ms with no SYNC_TIME within {SYNC_MATCH_MS} ms",
                    "break": f"break of {ev.step_ms / 1000:.1f} s inside a single take"}[ev.kind]
            r.fails.append(f"row {ev.row}: {what}")
    return r


def analyse(rows: list[dict], serials: dict[str, Serial | None], samples_per_packet: int,
            break_s: float, single_take: bool, span_tol_s: float) -> tuple[dict[str, FootResult], list[str]]:
    per_side: dict[str, tuple[list[float], list[str], list[bool]]] = {k: ([], [], []) for k in SIDES}
    global_fails: list[str] = []
    for row in rows:
        side = row["side"]
        if side not in per_side:
            global_fails.append(f"unknown side value {side!r}")
            continue
        per_side[side][0].append(float(row["tUnixMs"]))
        per_side[side][1].append(row["gaitLabel"])
        per_side[side][2].append(row["isValid"] == "true")

    results = {
        k: analyse_foot(k, *per_side[k], serials.get(k), samples_per_packet, break_s * 1000, single_take)
        for k in SIDES
    }
    left, right = results["L"], results["R"]
    if left.rows and right.rows:
        d_first = abs(left.first_ms - right.first_ms) / 1000
        d_last = abs(left.last_ms - right.last_ms) / 1000
        if d_first > span_tol_s or d_last > span_tol_s:
            global_fails.append(f"feet don't cover the same span: start differs {d_first:.2f} s, "
                                f"end differs {d_last:.2f} s (tolerance {span_tol_s:g} s)")
    sessions = {row["sessionId"] for row in rows}
    if len(sessions) > 1:
        global_fails.append(f"{len(sessions)} sessionIds in one file")
    return results, global_fails


def report(results: dict[str, FootResult], global_fails: list[str], serials: dict[str, Serial | None],
           out=sys.stdout) -> bool:
    ok = not global_fails
    for k, r in results.items():
        print(f"\n== {SIDES[k]} foot ({k}) ==", file=out)
        print(f"rows {r.rows}", file=out)
        if r.rows:
            print(f"span {(r.last_ms - r.first_ms) / 1000:.2f} s, rate {r.rate_hz:.3f} Hz", file=out)
            n20 = r.steps.get(float(SAMPLE_PERIOD_MS), 0)
            print(f"steps: {n20} of {r.rows - 1} exactly {SAMPLE_PERIOD_MS} ms; "
                  f"others: {dict((s, c) for s, c in r.steps.items() if s != SAMPLE_PERIOD_MS) or 'none'}",
                  file=out)
            if r.win_min is not None:
                print(f"rows per full 10 s window: min {r.win_min}, max {r.win_max}", file=out)
            print(f"gaitLabel {dict(r.labels)}, isValid=false rows {r.invalid_rows}", file=out)
            for ev in r.events:
                sync = (f"SYNC_TIME conn {ev.sync[1]} at {ev.sync[0]} (unix {ev.sync[2]}, "
                        f"{ev.t_ms - ev.sync[2]:+.0f} ms)") if ev.sync else "no SYNC_TIME match"
                print(f"  event row {ev.row}: step {ev.step_ms:g} ms, {ev.kind}, {sync} -> {ev.verdict}", file=out)
        s = serials.get(k)
        if s:
            print("serial:", file=out)
            for e in s.conn_events:
                print(f"  {e}", file=out)
            for c, (t, state, sent, drops) in sorted(s.last_sent.items()):
                print(f"  last [sess] conn {c} at {t}: {state}, sent {sent}, mtu-drops {drops}", file=out)
            print(f"  SYNC_TIME received: {len(s.syncs)}; notify failures (max seen) {s.notify_failures_max}",
                  file=out)
        for f_ in r.fails:
            print(f"FAIL: {f_}", file=out)
        ok = ok and not r.fails
        if any(ev.verdict == "AMBIGUOUS" for ev in r.events):
            print("AMBIGUOUS: a later web-app resync step is always 20 + 160 k ms; no packet was lost if "
                  "the dev panel showed pkts = seq + 1 and dropped=0 for this connection", file=out)
    if results["L"].rows and results["R"].rows:
        print(f"\nL/R start difference {results['L'].first_ms - results['R'].first_ms:+.0f} ms, "
              f"end difference {results['L'].last_ms - results['R'].last_ms:+.0f} ms (reported only)", file=out)
    for f_ in global_fails:
        print(f"FAIL: {f_}", file=out)
    print(f"\nRESULT: {'PASS' if ok else 'FAIL'}", file=out)
    return ok


def correct(rows: list[dict], results: dict[str, FootResult],
            assume_no_loss: bool) -> tuple[list[dict], dict[str, tuple[int, int]]]:
    """Undo the web app's offset steps within each take (see the module doc).

    Returns the corrected rows (same order) and, per side, (steps undone,
    lost-sized steps left alone because --assume-no-loss was not given).
    """
    out = [dict(r) for r in rows]
    summary = {}
    for side, r in results.items():
        idx = [i for i, row in enumerate(rows) if row["side"] == side]
        events = {ev.row: ev for ev in r.events}
        shift, undone, left = 0.0, 0, 0
        for n, i in enumerate(idx):
            ev = events.get(n)
            if ev is not None:
                if ev.kind == "break":
                    shift = 0.0  # a new take keeps its own offset
                elif ev.kind == "lost" and not assume_no_loss:
                    left += 1
                else:
                    shift += ev.step_ms - SAMPLE_PERIOD_MS
                    undone += 1
            if shift:
                out[i]["tUnixMs"] = f"{float(rows[i]['tUnixMs']) - shift:.0f}"
        summary[side] = (undone, left)
    return out, summary


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != CSV_COLUMNS:
            raise SystemExit(f"unexpected header: {reader.fieldnames}")
        return list(reader)


# ─── selftest ────────────────────────────────────────────────────

def _rows(side: str, times: list[float]) -> list[dict]:
    base = {c: "0" for c in CSV_COLUMNS}
    return [dict(base, subjectId="T", sessionId="S", side=side, tUnixMs=f"{t:.0f}",
                 gaitLabel="normal", isValid="true") for t in times]


def _stream(start: float, n: int, steps: dict[int, float] | None = None) -> list[float]:
    """n samples 20 ms apart; steps[i] replaces the step into row i."""
    out, t = [], start
    for i in range(n):
        if i:
            t += (steps or {}).get(i, SAMPLE_PERIOD_MS)
        out.append(t)
    return out


def _serial(syncs: list[int]) -> Serial:
    return parse_serial([f"12:00:00.000 [ctl] conn 0: SYNC_TIME unix {u} ms at device 5 ms" for u in syncs])


def selftest() -> bool:
    T0 = 1_792_600_000_000
    N = 50 * 360  # 6 minutes
    resync_row = 50 * 300
    resync_t = T0 + resync_row * 20 + 87

    cases = []

    def case(name, rows, serials, expect_pass, expect_kinds=None, **kw):
        cases.append((name, rows, serials, expect_pass, expect_kinds or {}, kw))

    clean = _stream(T0, N)
    case("clean, no serial", _rows("L", clean) + _rows("R", clean), {}, True)
    resynced = _stream(T0, N, {resync_row: 20 + 87})
    case("resync step matched to SYNC_TIME",
         _rows("L", resynced) + _rows("R", resynced),
         {"L": _serial([resync_t - 40]), "R": _serial([resync_t - 40])}, True,
         {"L": [("offset", "ok")]})
    case("resync step with no SYNC_TIME in the log",
         _rows("L", resynced) + _rows("R", clean), {"L": _serial([T0 - 100_000]), "R": _serial([])}, False,
         {"L": [("offset", "FAIL")]})
    lost = _stream(T0, N - 8, {9000: 180})
    case("one lost packet, no sync near", _rows("L", clean) + _rows("R", lost),
         {"L": _serial([]), "R": _serial([])}, False, {"R": [("lost", "FAIL")]})
    case("lost-sized step at a resync is AMBIGUOUS, not FAIL",
         _rows("L", clean) + _rows("R", lost),
         {"L": _serial([]), "R": _serial([T0 + 9000 * 20 + 160 - 50])}, True, {"R": [("lost", "AMBIGUOUS")]})
    lost4 = _stream(T0, N - 4, {9000: 100})
    case("4/pkt loss (20 + 80)", _rows("L", clean) + _rows("R", lost4), {}, False,
         {"R": [("lost", "FAIL")]}, samples_per_packet=4)
    back = _stream(T0, N, {7000: -40})
    case("backwards step", _rows("L", back) + _rows("R", clean),
         {"L": _serial([T0 + 7000 * 20]), "R": _serial([])}, False, {"L": [("backwards", "FAIL")]})
    case("right foot missing", _rows("L", clean), {}, False)
    case("right foot stops 60 s early", _rows("L", clean) + _rows("R", _stream(T0, N - 3000)), {}, False)
    broken = _stream(T0, N, {9000: 45_000})
    case("45 s break, single take", _rows("L", broken) + _rows("R", broken), {}, False,
         {"L": [("break", "FAIL")]}, single_take=True)
    case("45 s break, several takes allowed", _rows("L", broken) + _rows("R", broken), {}, True,
         {"L": [("break", "break")]})
    slow = [T0 + i * 20 for i in range(N)][::2]  # every other sample: steps of 40
    case("25 Hz stream", _rows("L", slow) + _rows("R", clean), {}, False)

    import io
    all_ok = True
    for name, rows, serials, expect_pass, expect_kinds, kw in cases:
        results, gfails = analyse(rows, serials, kw.get("samples_per_packet", 8), 5.0,
                                  kw.get("single_take", False), 2.0)
        passed = report(results, gfails, serials, out=io.StringIO())
        good = passed == expect_pass
        for side, kinds in expect_kinds.items():
            got = [(e.kind, e.verdict) for e in results[side].events]
            if got != kinds:
                good = False
                name += f" (events {got[:4]}{' ...' if len(got) > 4 else ''}, expected {kinds})"
        print(f"{'ok  ' if good else 'BAD '} {name}: {'PASS' if passed else 'FAIL'}")
        all_ok = all_ok and good
    # --write-corrected: (name, L times, R times, assume_no_loss, expected (undone, left) for L,
    # expected L steps after correction)
    take2 = _stream(T0, N, {4000: 180, 6000: -140, 9000: 45_000, 9500: 20 + 63, 12000: 180})
    corr_cases = [
        ("undo a +160 resync step (dev panel: no loss)", lost, clean[: N - 8], True, (1, 0), {20.0: N - 9}),
        ("leave a +160 step without --assume-no-loss", lost, clean[: N - 8], False, (0, 1), {20.0: N - 10, 180.0: 1}),
        ("undo +160, -140 and an arbitrary step; break kept, shift reset after it", take2, take2, True, (4, 0),
         {20.0: N - 2, 45000.0: 1}),
    ]
    for name, lt, rt, assume, expect_summary, expect_steps in corr_cases:
        rows = _rows("L", lt) + _rows("R", rt)
        results, _ = analyse(rows, {}, 8, 5.0, False, 2.0)
        fixed, summary = correct(rows, results, assume)
        times = [float(r["tUnixMs"]) for r in fixed if r["side"] == "L"]
        got_steps = dict(Counter(round(b - a, 1) for a, b in zip(times, times[1:])))
        # The break itself is never altered (a shift carried over it would change it).
        break_kept = lt is not take2 or times[9000] - times[8999] == 45_000
        good = summary["L"] == expect_summary and got_steps == expect_steps and break_kept
        print(f"{'ok  ' if good else 'BAD '} corrected: {name}"
              + ("" if good else f" (summary {summary['L']}, steps {got_steps})"))
        all_ok = all_ok and good
    n_cases = len(cases) + len(corr_cases)
    print(f"selftest: {'all cases as expected' if all_ok else 'SOME CASES WRONG'} ({n_cases} cases)")
    return all_ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", nargs="?", type=Path)
    ap.add_argument("--serial-left", type=Path, help="serial_log.py output of the left board")
    ap.add_argument("--serial-right", type=Path, help="serial_log.py output of the right board")
    ap.add_argument("--samples-per-packet", type=int, default=8, choices=[4, 8],
                    help="8 at MTU >= 203, 4 at the contract's MTU fallback")
    ap.add_argument("--break-s", type=float, default=5.0, help="a step longer than this is a break")
    ap.add_argument("--single-take", action="store_true", help="any break is a FAIL")
    ap.add_argument("--span-tol-s", type=float, default=2.0,
                    help="max start/end difference between the feet")
    ap.add_argument("--write-corrected", type=Path, metavar="OUT",
                    help="write the CSV with the web app's resync steps undone within each take")
    ap.add_argument("--assume-no-loss", action="store_true",
                    help="the dev panel showed pkts = seq + 1 and dropped=0: undo 20 + 160 k steps too")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return 0 if selftest() else 1
    if not args.csv:
        ap.error("csv is required unless --selftest")
    rows = read_csv(args.csv)
    serials = {
        "L": parse_serial(args.serial_left.read_text(errors="replace").splitlines()) if args.serial_left else None,
        "R": parse_serial(args.serial_right.read_text(errors="replace").splitlines()) if args.serial_right else None,
    }
    print(f"{args.csv}: {len(rows)} rows")
    results, gfails = analyse(rows, serials, args.samples_per_packet, args.break_s,
                              args.single_take, args.span_tol_s)
    ok = report(results, gfails, serials)
    if args.write_corrected:
        fixed, summary = correct(rows, results, args.assume_no_loss)
        write_csv(args.write_corrected, fixed)
        print(f"\nwrote {args.write_corrected}")
        for side, (undone, left) in summary.items():
            print(f"  {SIDES[side]}: {undone} step(s) undone"
                  + (f", {left} lost-sized step(s) left (no --assume-no-loss)" if left else ""))
        print("  a resync between two takes is not visible in the CSV and is not undone")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

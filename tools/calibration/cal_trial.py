#!/usr/bin/env python3
"""Static-load trial of one Velostat sensor with a coin and a water bottle
(FW-1 report 043, "trial calibration"). Reads only the serial log that
tools/board_check/serial_read.py is already writing; never opens the port.

  guide    1. live check: you press the sensor by hand and see which channel
              responds; nothing is recorded unless one does and you confirm it;
           2. rest, coin alone, then the bottle placed alone on the coin at
              each fill going up (500, 1000, 1500 ml) and down (1000, 500),
              lifted off between loads (coin-alone reading while you refill);
              every refill waits for Enter, every hold is timed;
           3. bottle off, coin off, rest; then the second round.
           Each instruction beeps, says what to do and is timestamped into
           session.json (same clock as the serial log).
  analyse  per load: mean of the last 5 s, drift and settle time in the
           hold, return time after each lift, up vs down, round 1 vs 2, kPa
           on the coin's area, and the log(F) vs log(R) straight-line fit.

The self-test sketch's raw C3 ADC is treated as 4095 = 2.5 V with no eFuse
calibration: every mV, ohm and fit number from it is APPROXIMATE. Masses are
approximate too unless weighed (the bottle's are fill volume + bottle).

  cal_trial.py guide   --log LOG --out NEW_DIR [--sensor hallux --site 0 ...]
  cal_trial.py analyse --session NEW_DIR/session.json [--channel N]
"""
import argparse
import datetime as dt
import json
import math
import os
import re
import select
import statistics as st
import sys
import time

G = 9.80665
R_PULLDOWN = 1000.0  # ohm (hardware team, 2026-11-09)
SUPPLY_MV = 3300.0
SELFTEST_MV_PER_RAW = 2500.0 / 4095  # approximate: C3 at 12 dB, uncalibrated
FW1_MV_PER_COUNT = SUPPLY_MV / 4095  # contract v1.6 addendum 2
LAST_S = 5.0  # seconds averaged at the end of each hold
CHECK_MIN_COUNTS = 60  # a hand press must move a channel at least this much
STALE_S = 5.0
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d+)\s*(.*)$")


# ---- log parsing -------------------------------------------------------------

def parse(lines):
    """(HH:MM:SS.mmm, {channel: value}, source) per complete reading."""
    out, cur, t0 = [], {}, None
    for line in lines:
        m = LINE.match(line.rstrip("\n"))
        if not m:
            continue
        ts, body = m.groups()
        if body.startswith("[raw] "):  # FW-1: 1 s means in counts of 3.3 V
            f = body.split()
            k = f.index("mean")
            out.append((ts, dict(enumerate(int(x) for x in f[k + 1:k + 9])), "fw1"))
        elif body.startswith("MUX raw ADC"):
            cur, t0 = {}, ts
        else:
            for ch, v in re.findall(r"C(\d\d)=\s*(\d+)", body):
                cur[int(ch)] = int(v)
            if len(cur) == 16 and t0:
                out.append((t0, dict(cur), "selftest"))
                cur, t0 = {}, None
    return out


def tail(path, n=3):
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 600 * (n + 1)))
        return parse(f.read().decode("utf-8", "replace").splitlines())[-n:]


def secs(ts):
    h, m, s = ts.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def now_ts():
    return dt.datetime.now().strftime("%H:%M:%S.%f")[:-3]


class Live:
    """New readings from the log as they arrive."""

    def __init__(self, path):
        # Start after the newest reading already in the log: the baseline
        # uses only readings taken after the guide asked for hands off.
        self.path = path
        old = tail(path, 1)
        self.last = old[-1][0] if old else None
        self.started = time.time()

    def poll(self):
        rows = [r for r in tail(self.path, 5) if self.last is None or secs(r[0]) > secs(self.last)]
        if rows:
            self.last = rows[-1][0]
        return [(t, row) for t, row, _ in rows]

    def stale(self):
        if self.last is None:
            return time.time() - self.started > STALE_S
        return (secs(now_ts()) - secs(self.last)) % 86400 > STALE_S


# ---- guide -------------------------------------------------------------------

def beep(text):
    print(f"\a\n[{now_ts()}] {text}", flush=True)


class Keys:
    """Lines typed on stdin without blocking the live display. Reads the file
    descriptor directly: Python's buffered stdin can hold typed-ahead lines
    that select() no longer sees."""

    def __init__(self):
        self.buf = b""

    def line(self, timeout):
        if b"\n" not in self.buf:
            r, _, _ = select.select([sys.stdin.fileno()], [], [], timeout)
            if r:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data:
                    raise EOFError
                self.buf += data
        if b"\n" in self.buf:
            ln, self.buf = self.buf.split(b"\n", 1)
            return ln.decode("utf-8", "replace").strip()
        return None

    def ask(self, prompt):
        print(prompt, end="", flush=True)
        while (ln := self.line(None)) is None:
            pass
        return ln.lower()


KEYS = Keys()


def enter_pressed(timeout):
    return KEYS.line(timeout) is not None


def status(msg):
    print(f"\r{msg:<100}", end="", flush=True)


def live_text(live, base, ch, latest):
    if live.stale():
        return "no new readings from the log: is serial_read.py still running?"
    if latest is None or base is None:
        return "waiting for readings..."
    if ch is None:
        d = sorted(((latest[c] - base[c], c) for c in latest), key=lambda x: -abs(x[0]))[:3]
        return "biggest change from baseline: " + ", ".join(f"C{c:02d} {v:+.0f}" for v, c in d)
    others = max(((abs(latest[c] - base[c]), c) for c in latest if c != ch), default=(0, 0))
    return (f"C{ch:02d} {latest[ch]:4d} ({latest[ch] - base[ch]:+.0f} from rest) | "
            f"largest other C{others[1]:02d} {others[0]:+.0f}")


def check(a, live):
    """Hand-press check. Returns (channel, baseline, summary) or exits."""
    while True:
        beep("Hands OFF the insole for 5 s while I take a baseline.")
        rows, t0 = [], time.time()
        while time.time() - t0 < 5:
            rows += live.poll()
            status(f"  baseline: {len(rows)} readings")
            time.sleep(0.2)
        if not rows or live.stale():
            print()
            sys.exit("No readings arriving in the log. Is serial_read.py running? Nothing recorded.")
        base = {c: st.fmean(r[c] for _, r in rows) for c in rows[0][1]}
        beep(f"PRESS the {a.sensor} sensor firmly with a fingertip for about 3 s, release, "
             "then press Enter.")
        peak = {c: 0.0 for c in base}
        latest = rows[-1][1]
        while True:
            for _, r in live.poll():
                latest = r
                for c in r:
                    if abs(r[c] - base[c]) > abs(peak[c]):
                        peak[c] = r[c] - base[c]
            status("  " + live_text(live, base, None, latest) + " | Enter when done")
            if enter_pressed(0.3):
                break
        top = sorted(peak, key=lambda c: -abs(peak[c]))
        c0, c1 = top[0], top[1]
        print(f"\n  Largest changes during the press: "
              + ", ".join(f"C{c:02d} {peak[c]:+.0f}" for c in top[:4]))
        if abs(peak[c0]) < CHECK_MIN_COUNTS:
            print(f"\a  No channel moved {CHECK_MIN_COUNTS} counts or more. The {a.sensor} sensor is "
                  "not reaching any channel this sketch prints.")
            ans = KEYS.ask("  r = press again, anything else = stop (nothing recorded): ")
            if ans == "r":
                continue
            sys.exit("Stopped: no channel responded. Nothing recorded. Tell Claude.")
        together = abs(peak[c1]) >= 0.5 * abs(peak[c0])
        if together:
            print(f"  NOTE: C{c1:02d} moved {abs(peak[c1]) / abs(peak[c0]):.0%} as much as C{c0:02d}: "
                  "two channels respond together.")
        ans = KEYS.ask(f"  C{c0:02d} responded ({peak[c0]:+.0f}). Record the trial on C{c0:02d}? "
                       "y = yes / r = press again / n = stop: ")
        if ans == "y":
            return c0, base, {"channel": c0, "peak_change": {f"C{c:02d}": round(peak[c]) for c in top[:4]},
                              "together": together}
        if ans != "r":
            sys.exit("Stopped at the check. Nothing recorded.")


def build_plan(a):
    """Steps: (kind, text, load_kg, ml, round, phase, mode, seconds)."""
    coin, fills, masses = a.coin_kg, a.fills, a.bottle_kg
    seq = list(range(len(fills))) + list(range(len(fills) - 2, -1, -1))  # up, then down
    on_coin = "Steady it with one fingertip on the side; do not push down."
    plan = [("rest", "Nothing on the sensor. Hands off the insole.", 0.0, 0, 0, "rest", "timed", a.rest)]
    for rnd in range(1, a.rounds + 1):
        plan.append(("coin", f"Round {rnd}: PLACE the coin flat, centred on the {a.sensor} sensor. "
                     "Hands off.", coin, 0, rnd, "coin", "timed", a.hold))
        plan.append(("off", f"Make sure the bottle holds {fills[seq[0]]} ml. The coin stays; hands off "
                     "the insole. Press Enter when ready.", coin, 0, rnd, "up", "enter", a.min_off))
        for k, idx in enumerate(seq):
            phase = "up" if k < len(fills) else "down"
            plan.append(("load", f"PLACE the bottle ({fills[idx]} ml) upright on the coin, centred. "
                         + on_coin, coin + masses[idx], fills[idx], rnd, phase, "timed", a.hold))
            if k + 1 < len(seq):
                nxt = fills[seq[k + 1]]
                verb = "REFILL it" if nxt > fills[idx] else "POUR it out"
                plan.append(("off", f"LIFT the bottle straight off (the coin stays). {verb} to {nxt} ml, "
                             "then press Enter.", coin, 0, rnd, "up" if k + 1 < len(fills) else "down",
                             "enter", a.min_off))
        plan.append(("off", "LIFT the bottle straight off (the coin stays). Hands off.", coin, 0, rnd,
                     "down", "timed", a.hold))
        plan.append(("rest", "REMOVE the coin. Hands off the insole.", 0.0, 0, rnd, "rest", "timed", a.rest))
    return plan


def guide(a):
    if not os.path.exists(a.log):
        sys.exit(f"no log at {a.log}: start serial_read.py first")
    path = os.path.join(a.out, "session.json")
    if os.path.exists(path):
        sys.exit(f"{path} exists: choose a new --out (sessions are never overwritten)")
    if len(a.fills) != len(a.bottle_kg) or len(a.fills) < 2:
        sys.exit("--fills and --bottle-kg need the same number of values (at least 2)")
    plan = build_plan(a)
    print(f"Trial on the {a.sensor} sensor: coin {a.coin_mm:g} mm ~{a.coin_kg:g} kg; bottle fills "
          f"{a.fills} ml ~{a.bottle_kg} kg (approximate, not weighed); {a.rounds} rounds, holds "
          f"{a.hold:g} s, rests {a.rest:g} s. Each refill waits for Enter.")
    live = Live(a.log)
    ch, base, chk = check(a, live)

    os.makedirs(a.out, exist_ok=True)
    session = {"log": os.path.abspath(a.log), "day": dt.date.today().isoformat(), "sensor": a.sensor,
               "site": a.site, "coin_mm": a.coin_mm, "coin_kg": a.coin_kg, "fills_ml": a.fills,
               "bottle_kg": a.bottle_kg, "masses_approximate": True, "hold_s": a.hold, "rest_s": a.rest,
               "min_off_s": a.min_off, "rounds": a.rounds, "check": chk, "steps": []}

    def save():
        with open(path, "w") as f:
            json.dump(session, f, indent=1)

    try:
        for i, (kind, text, load, ml, rnd, phase, mode, secs_) in enumerate(plan):
            stamp = now_ts()
            session["steps"].append({"i": i, "t": stamp, "kind": kind, "text": text, "load_kg": round(load, 4),
                                     "ml": ml, "round": rnd, "phase": phase, "mode": mode})
            save()
            beep(f"step {i + 1}/{len(plan)}: {text}")
            t0, latest, done = time.time(), None, False
            while not done:
                for _, r in live.poll():
                    latest = r
                left = secs_ - (time.time() - t0)
                if mode == "timed":
                    status(f"  {max(0, left):3.0f} s | " + live_text(live, base, ch, latest))
                    done = left <= 0
                    time.sleep(min(0.3, max(0.05, left)))
                else:
                    status(f"  waiting for Enter | " + live_text(live, base, ch, latest))
                    if enter_pressed(0.3):
                        while (left := secs_ - (time.time() - t0)) > 0:  # coin-alone reading
                            for _, r in live.poll():
                                latest = r
                            status(f"  recording the coin alone {left:3.0f} s more | "
                                   + live_text(live, base, ch, latest))
                            time.sleep(0.3)
                        done = True
    except (KeyboardInterrupt, EOFError):
        session["aborted_at"] = now_ts()
        save()
        print(f"\nStopped. Partial session saved to {path}")
        return
    session["end"] = now_ts()
    save()
    beep(f"Done. Session saved to {path}")
    print(f"Analyse with:\n  python3 {os.path.abspath(__file__)} analyse --session {path}")


# ---- analyse -----------------------------------------------------------------

def fit_loglog(xs, ys):
    lx = [math.log10(x) for x in xs]
    ly = [math.log10(y) for y in ys]
    mx, my = st.fmean(lx), st.fmean(ly)
    sxx = sum((x - mx) ** 2 for x in lx)
    b = sum((x - mx) * (y - my) for x, y in zip(lx, ly)) / sxx
    a = 10 ** (my - b * mx)
    ss_res = sum((y - (math.log10(a) + b * x)) ** 2 for x, y in zip(lx, ly))
    ss_tot = sum((y - my) ** 2 for y in ly)
    return a, b, (1 - ss_res / ss_tot) if ss_tot > 0 else float("nan")


def resistance(mv):
    return R_PULLDOWN * (SUPPLY_MV - mv) / mv if 0 < mv < SUPPLY_MV else float("nan")


def thresholds():
    try:
        p = json.load(open(os.path.join(REPO, "shared", "thresholds.json")))["pressure"]
        return p["watchKpa"], p["alertKpa"]
    except (OSError, KeyError, ValueError):
        return None, None


def kpa(load_kg, area_m2):
    return load_kg * G / area_m2 / 1000


def settle_time(vals, start, final, tol):
    """Seconds from `start` until every later value stays within tol of final."""
    for k, (t, _) in enumerate(vals):
        if all(abs(v - final) <= tol for _, v in vals[k:]):
            return (t - start).total_seconds()
    return None


def analyse(a):
    s = json.load(open(a.session))
    day = dt.date.fromisoformat(s["day"])
    when = lambda ts: dt.datetime.combine(day, dt.time.fromisoformat(ts))
    with open(s["log"], encoding="utf-8", errors="replace") as f:
        rows = [(when(t), r, src) for t, r, src in parse(f)]
    approx = any(src == "selftest" for _, _, src in rows)
    mv_per = SELFTEST_MV_PER_RAW if approx else FW1_MV_PER_COUNT
    steps = s["steps"]
    ends = [when(x["t"]) for x in steps[1:]] + [when(s.get("end") or s["aborted_at"])]
    for x, e in zip(steps, ends):
        x["start"], x["stop"] = when(x["t"]), e
    ch = a.channel if a.channel is not None else s["check"]["channel"]
    for x in steps:
        x["vals"] = [(t, r[ch]) for t, r, _ in rows if x["start"] <= t < x["stop"]]
        last = [v for t, v in x["vals"] if t >= x["stop"] - dt.timedelta(seconds=LAST_S)]
        x["mean"] = st.fmean(last) if last else None
    area = math.pi * (s["coin_mm"] / 2000) ** 2
    rest0 = steps[0]["mean"]
    coin_ref = {x["round"]: x["mean"] for x in steps if x["kind"] == "coin"}
    loads = [x for x in steps if x["kind"] == "load" and x["mean"] is not None]
    top_change = max((abs(x["mean"] - coin_ref[x["round"]]) for x in loads), default=1) or 1
    watch, alert = thresholds()

    out = []
    p = out.append
    p(f"# Trial calibration: {s['sensor']} (site {s['site']}), channel C{ch:02d}\n")
    p(f"- Session `{a.session}`; log `{s['log']}`.")
    p(f"- Source: {'self-test raw C3 ADC treated as 4095 = 2.5 V, **APPROXIMATE** (no eFuse calibration)' if approx else 'FW-1 counts of 3.3 V (calibrated mV)'}; "
      f"pull-down {R_PULLDOWN:.0f} Ω, supply 3.3 V.")
    p(f"- Coin {s['coin_mm']:g} mm (area {area * 1e6:.0f} mm²), ~{s['coin_kg']:g} kg; bottle fills {s['fills_ml']} ml "
      f"≈ {s['bottle_kg']} kg with the bottle. **Masses approximate (no scale).** Load on the sensor = bottle + coin.")
    p(f"- Holds {s['hold_s']:g} s, rests {s['rest_s']:g} s, coin-alone at least {s['min_off_s']:g} s after each lift; "
      f"value per hold = mean of the last {LAST_S:g} s (1 reading a second).")
    chk = s["check"]
    p(f"- Hand-press check: largest changes {chk['peak_change']}"
      f"{' — two channels responded together' if chk.get('together') else ''}.")
    if "aborted_at" in s:
        p(f"- **Stopped early at {s['aborted_at']}**: later steps missing.")
    p("")

    p("| step | round | phase | load | load kg (approx) | kPa on coin | mean | mV (approx) | R Ω (approx) | drift in hold | settle s |")
    p("|---|---|---|---|---|---|---|---|---|---|---|")
    for x in steps:
        if x["kind"] not in ("load", "coin", "rest"):
            continue
        if x["mean"] is None:
            p(f"| {x['i'] + 1} | {x['round']} | {x['phase']} | {x['kind']} | {x['load_kg']:g} | | no readings | | | | |")
            continue
        prev = [v for t, v in x["vals"]
                if x["stop"] - dt.timedelta(seconds=2 * LAST_S) <= t < x["stop"] - dt.timedelta(seconds=LAST_S)]
        drift = x["mean"] - st.fmean(prev) if prev else float("nan")
        ref = coin_ref.get(x["round"], rest0) if x["kind"] == "load" else rest0
        settle = settle_time(x["vals"], x["start"], x["mean"], max(5.0, 0.03 * abs(x["mean"] - ref)))
        mv = x["mean"] * mv_per
        x["drift"], x["settle"], x["mv"] = drift, settle, mv
        label = f"{x['ml']} ml" if x["kind"] == "load" else x["kind"]
        p(f"| {x['i'] + 1} | {x['round']} | {x['phase']} | {label} | {x['load_kg']:g} | {kpa(x['load_kg'], area):.1f} | "
          f"{x['mean']:.0f} | {mv:.0f} | {resistance(mv):.0f} | {drift:+.0f} | "
          f"{f'{settle:.0f}' if settle is not None else 'not settled'} |")
    p("\nSettle: seconds from the beep until every later reading in the hold stays within max(5 counts, 3 % of the "
      "change from the coin-alone reading) of the final 5-s mean; includes the time to place the bottle. "
      "Drift: final 5-s mean minus the 5 s before it.\n")

    p("**After each lift (coin alone; reference = that round's coin-alone reading):**\n")
    p("| step | round | after | coin-alone time s | back within 10 % s | back within max(5, 3 %) s | residual at end |")
    p("|---|---|---|---|---|---|---|")
    for k, x in enumerate(steps):
        if x["kind"] != "off" or k == 0 or steps[k - 1]["kind"] != "load" or x["mean"] is None:
            continue
        before = steps[k - 1]
        ref = coin_ref[x["round"]]
        change = abs((before["mean"] or ref) - ref)
        dur = (x["stop"] - x["start"]).total_seconds()
        t10 = settle_time(x["vals"], x["start"], ref, max(5.0, 0.10 * change))
        t3 = settle_time(x["vals"], x["start"], ref, max(5.0, 0.03 * change))
        fmt = lambda t: f"{t:.0f}" if t is not None else f"not within {dur:.0f}"
        p(f"| {x['i'] + 1} | {x['round']} | {before['ml']} ml | {dur:.0f} | {fmt(t10)} | {fmt(t3)} | {x['mean'] - ref:+.0f} |")
    p("")

    p("**Same load, going up vs coming down** (the bottle is lifted between loads, so this is the memory of the "
      "previous load, not a continuous loading/unloading loop):\n")
    p("| round | fill | up | down | down − up | % of the largest change |")
    p("|---|---|---|---|---|---|")
    for rnd in sorted({x["round"] for x in loads}):
        up = {x["ml"]: x["mean"] for x in loads if x["round"] == rnd and x["phase"] == "up"}
        dn = {x["ml"]: x["mean"] for x in loads if x["round"] == rnd and x["phase"] == "down"}
        for ml in sorted(set(up) & set(dn)):
            p(f"| {rnd} | {ml} ml | {up[ml]:.0f} | {dn[ml]:.0f} | {dn[ml] - up[ml]:+.0f} | {100 * (dn[ml] - up[ml]) / top_change:+.1f} % |")
    p("")
    p("**Round 1 vs round 2:**\n")
    p("| phase | fill | round 1 | round 2 | 2 − 1 |")
    p("|---|---|---|---|---|")
    for x in loads:
        if x["round"] != 1:
            continue
        y = [z for z in loads if z["round"] == 2 and z["phase"] == x["phase"] and z["ml"] == x["ml"]]
        if y:
            p(f"| {x['phase']} | {x['ml']} ml | {x['mean']:.0f} | {y[0]['mean']:.0f} | {y[0]['mean'] - x['mean']:+.0f} |")
    rests = [x["mean"] for x in steps if x["kind"] == "rest" and x["mean"] is not None]
    coins = [f"{v:.0f}" for v in coin_ref.values() if v is not None]
    p(f"\nUnloaded (rest) readings in order: {', '.join(f'{v:.0f}' for v in rests)}; coin alone per round: {', '.join(coins)}.\n")

    p("**log(F) vs log(R) straight line** (bottle loads only; F = load × g in N, approximate):\n")
    levels = sorted({x["load_kg"] for x in loads})
    for label, rfun in (("R from the reading itself (no tare)", lambda x: resistance(x["mv"])),
                        ("R from reading − rest, as the app's §5.1 formula computes it after TARE",
                         lambda x: resistance((x["mean"] - rest0) * mv_per))):
        pts = [(rfun(x), x["load_kg"] * G) for x in loads if "mv" in x]
        pts = [(r, f) for r, f in pts if math.isfinite(r) and r > 0]
        if len({f for _, f in pts}) >= 2 and len(pts) >= 3:
            fa, fb, r2 = fit_loglog([r for r, _ in pts], [f for _, f in pts])
            p(f"- {label}: F = {fa:.4g} · R^{fb:.3f}, R² = {r2:.4f} ({len(pts)} holds).")
        else:
            p(f"- {label}: not enough usable holds.")
    if levels:
        p(f"- Only {len(levels)} load levels spanning ×{levels[-1] / levels[0]:.1f} in force: R² says little about the "
          "curve's shape. The real calibration needs 6–8 levels.")
    if approx:
        p("- All mV, Ω and fit numbers are APPROXIMATE (raw C3 ADC, no eFuse calibration).")
    p("")

    top_kpa = kpa(max(levels), area) if levels else 0
    p("**Range:**\n")
    if watch and alert:
        p(f"- The largest load is about {top_kpa:.0f} kPa on the {s['coin_mm']:g} mm coin, below the app's watch "
          f"({watch} kPa) and alert ({alert} kPa) thresholds (shared/thresholds.json): this trial does not test the "
          f"sensor where alerts happen. On this coin, {alert} kPa needs about {alert * 1000 * area / G:.1f} kg.")
    p("\n**For the real calibration, get:**\n")
    a12 = math.pi * 0.006 ** 2
    p("- Weights up to about 5 kg in 6–8 steps (e.g. 0.25, 0.5, 1, 1.5, 2, 3, 4, 5 kg), each weighed on a kitchen "
      "scale (±1 g), the scale itself too.")
    p(f"- A rigid, flat puck about the sensor's size (measure the sensor's active area first). On a 12 mm puck "
      f"({a12 * 1e6:.0f} mm², the contract's example area), {alert or 200} kPa is {(alert or 200) * 1000 * a12 / G:.1f} kg "
      f"and 5 kg is {kpa(5, a12):.0f} kPa.")
    p("- Something that holds the weight upright on the puck without a hand (a guide tube or a small stand): a "
      "steadying finger adds or takes away force.")
    text = "\n".join(out) + "\n"
    md = os.path.join(os.path.dirname(os.path.abspath(a.session)), "analysis.md")
    if os.path.exists(md):
        md = md[:-3] + time.strftime("-%Y%m%d-%H%M%S") + ".md"
    with open(md, "w") as f:
        f.write(text)
    print(text)
    print(f"written to {md}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("guide")
    g.add_argument("--log", required=True)
    g.add_argument("--out", required=True)
    g.add_argument("--sensor", default="hallux")
    g.add_argument("--site", type=int, default=0)
    g.add_argument("--coin-mm", type=float, default=20)
    g.add_argument("--coin-kg", type=float, default=0.003)
    g.add_argument("--fills", type=lambda v: [int(x) for x in v.split(",")], default=[500, 1000, 1500])
    g.add_argument("--bottle-kg", type=lambda v: [float(x) for x in v.split(",")], default=[0.53, 1.03, 1.53])
    g.add_argument("--hold", type=float, default=15)
    g.add_argument("--rest", type=float, default=30)
    g.add_argument("--min-off", type=float, default=10, help="least coin-alone seconds after each lift")
    g.add_argument("--rounds", type=int, default=2)
    n = sub.add_parser("analyse")
    n.add_argument("--session", required=True)
    n.add_argument("--channel", type=int)
    a = ap.parse_args()
    try:
        guide(a) if a.cmd == "guide" else analyse(a)
    except (KeyboardInterrupt, EOFError):
        print("\nStopped before recording started. Nothing recorded.")
        sys.exit(1)


if __name__ == "__main__":
    main()

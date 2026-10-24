#!/usr/bin/env python3
"""Loads and checks SmartInsole research-capture sessions (S4C).

A session folder (as exported by the app, see docs/STUDY-CAPTURE.md) holds:
  session.json               subject code + coded data, trial order, trials
  <code>_<nn>_<label>_a<k>.csv   one per attempt: one row per sample per foot
  <code>_<nn>_<label>_a<k>.json  its sidecar: timing, gaps, calibration, ...
  alerts.csv                 alerts raised while the session screen was
                             open (S7, export only; older exports lack it)
  manifest.json              size + SHA-256 of every file (from the export)

Standard library only; numpy is used for model_matrix(as_numpy=True) if
present. Units are already final in the CSV (kPa, g, deg/s, from the app's
parser, checked against shared/test_vectors): this loader never converts.

  python3 tools/capture/load_capture.py check <session-dir>...
  python3 tools/capture/load_capture.py --selftest

`check` exits non-zero when any check FAILs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA = 1
REPO = Path(__file__).resolve().parents[2]
MODEL_INPUT = REPO / "shared" / "model_input.json"
FIXTURE = REPO / "shared" / "capture_fixture"

SAMPLE_MS = 20.0
STEP_TOLERANCE_MS = 1.0  # 50 Hz: every step 20 +- 1 ms
SIDES = ("L", "R")

INT_COLUMNS = {
    "device_ms", "conn_session", "seq", "i", "missing_before",
    "saturated", "calibrating", "valid",
}
TEXT_COLUMNS = {"side", "temp_quality"}
TEMP_COLUMNS = ("temp_unix_ms", "temp_forefoot_c", "temp_heel_c", "temp_quality")

# alerts.csv (mobile/lib/capture/alerts_csv.dart). The levels are the
# contract §8.3 level column (mobile/lib/rules/alert_code.dart); zones are
# the foot layout's ids in FSR channel order.
ALERTS_CSV = "alerts.csv"
ALERT_COLUMNS = [
    "at_ms", "code", "level", "patient_status", "side", "zone", "site",
    "measured_value", "threshold", "gait_class", "gait_confidence",
    "read_at_ms", "details",
]
ALERT_LEVELS = {
    "TEMP_DELTA": 4, "PRESSURE_WATCH": 2, "PRESSURE_PEAK": 3,
    "PRESSURE_PTI": 3, "ASYMMETRY_PEAK": 2, "LOAD_CONCENTRATION": 3,
    "DEVICE_LOST": 1, "BATTERY_LOW": 1,
}
ZONE_CODES = {"PRESSURE_WATCH", "PRESSURE_PEAK", "PRESSURE_PTI", "LOAD_CONCENTRATION"}
ZONES = ("hallux", "meta1", "meta3", "meta5", "midfoot", "heel")
SITES = ("forefoot", "heel")
PATIENT_STATUSES = ("noData", "safe", "careful", "rest")


def load_model_input(path: Path = MODEL_INPUT) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify_manifest(session_dir: Path) -> list[str]:
    """Problems with manifest.json vs the files; empty when all match."""
    m = session_dir / "manifest.json"
    if not m.exists():
        return ["manifest.json missing"]
    manifest = json.loads(m.read_text(encoding="utf-8"))
    problems = []
    listed = set()
    for entry in manifest["files"]:
        name = entry["name"]
        listed.add(name)
        f = session_dir / name
        if not f.exists():
            problems.append(f"{name}: missing")
        elif f.stat().st_size != entry["size"]:
            problems.append(f"{name}: size {f.stat().st_size} != {entry['size']}")
        elif sha256(f) != entry["sha256"]:
            problems.append(f"{name}: SHA-256 mismatch")
    for f in session_dir.iterdir():
        if f.is_file() and f.name != "manifest.json" and f.name not in listed:
            problems.append(f"{f.name}: not in manifest")
    return problems


@dataclass
class Trial:
    name: str
    sidecar: dict
    columns: list[str]
    # Per side, rows as dicts in file order (unix_ms ascending per side).
    rows: dict[str, list[dict]] = field(default_factory=dict)

    @property
    def valid(self) -> bool:
        return bool(self.sidecar["valid"])

    @property
    def label(self) -> str:
        return self.sidecar["label"]


@dataclass
class Session:
    path: Path
    meta: dict
    trials: list[Trial]
    # alerts.csv rows as dicts (text values), or None when the export has
    # no alerts.csv (exports from before S7).
    alerts: list[dict] | None = None
    alert_columns: list[str] | None = None


def _parse(column: str, text: str):
    if text == "":
        return None
    if column in TEXT_COLUMNS:
        return text
    if column in INT_COLUMNS:
        return int(text)
    return float(text)


def load_trial(csv_path: Path) -> Trial:
    sidecar = json.loads(csv_path.with_suffix(".json").read_text(encoding="utf-8"))
    if sidecar.get("schema") != SCHEMA:
        raise ValueError(f"{csv_path.name}: schema {sidecar.get('schema')} != {SCHEMA}")
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        columns = next(reader)
        if columns != sidecar["columns"]:
            raise ValueError(f"{csv_path.name}: header differs from its sidecar")
        rows: dict[str, list[dict]] = {s: [] for s in SIDES}
        last_temp: dict[str, dict] = {s: {} for s in SIDES}
        for raw in reader:
            row = {c: _parse(c, v) for c, v in zip(columns, raw)}
            side = row["side"]
            # Temperatures are written once per reading: forward-fill.
            if row["temp_unix_ms"] is not None:
                last_temp[side] = {c: row[c] for c in TEMP_COLUMNS}
            else:
                row.update({c: last_temp[side].get(c) for c in TEMP_COLUMNS})
            rows[side].append(row)
    return Trial(csv_path.stem, sidecar, columns, rows)


def load_session(session_dir: Path, verify: bool = True) -> Session:
    session_dir = Path(session_dir)
    if verify:
        problems = verify_manifest(session_dir)
        if problems:
            raise ValueError(f"{session_dir.name}: " + "; ".join(problems))
    meta = json.loads((session_dir / "session.json").read_text(encoding="utf-8"))
    trials = [load_trial(p) for p in sorted(session_dir.glob("*.csv"))
              if p.name != ALERTS_CSV]
    session = Session(session_dir, meta, trials)
    alerts_path = session_dir / ALERTS_CSV
    if alerts_path.exists():
        with alerts_path.open(newline="", encoding="utf-8") as f:
            reader = csv.reader(f)
            session.alert_columns = next(reader, [])
            session.alerts = [dict(zip(session.alert_columns, r)) for r in reader]
    return session


def pair_feet(left: list[dict], right: list[dict], tolerance_ms: float) -> list[tuple[dict, dict]]:
    """The pairing rule of shared/model_input.json (`pairing`), as the app's
    pairFeet(): left is the time base; each left row takes the right row
    nearest in unix_ms within +-tolerance (inclusive, ties to the earlier),
    each right row used at most once, in order."""
    out = []
    j = 0
    for l in left:
        t = l["unix_ms"]
        while j < len(right) and right[j]["unix_ms"] < t - tolerance_ms:
            j += 1
        best, best_d = None, float("inf")
        k = j
        while k < len(right) and right[k]["unix_ms"] <= t + tolerance_ms:
            d = abs(right[k]["unix_ms"] - t)
            if d < best_d:
                best, best_d = k, d
            k += 1
        if best is not None:
            out.append((l, right[best]))
            j = best + 1
    return out


def model_matrix(trial: Trial, model_input: dict | None = None,
                 valid_only: bool = True, as_numpy: bool = False):
    """[n, 24] rows in shared/model_input.json channel order, the feet
    paired by its `pairing` rule. Rows marked invalid are dropped before
    pairing when valid_only. Returns (rows, pairs) where pairs holds the
    (left unix_ms, right unix_ms) of each row."""
    mi = model_input or load_model_input()
    pairing = mi["pairing"]
    if pairing["timeBase"] != "L":
        raise ValueError("only a left time base is implemented")
    keep = (lambda r: r["valid"] == 1) if valid_only else (lambda r: True)
    left = [r for r in trial.rows["L"] if keep(r)]
    right = [r for r in trial.rows["R"] if keep(r)]
    pairs = pair_feet(left, right, float(pairing["toleranceMs"]))
    channels = mi["channels"]
    # "L_fsr0_kpa" -> side "L", column "fsr0_kpa".
    split = [(c[0], c[2:]) for c in channels]
    rows = []
    for l, r in pairs:
        foot = {"L": l, "R": r}
        rows.append([foot[s][col] for s, col in split])
    times = [(l["unix_ms"], r["unix_ms"]) for l, r in pairs]
    if as_numpy:
        import numpy as np  # optional
        return np.asarray(rows, dtype=np.float64), np.asarray(times)
    return rows, times


# --- Checks ------------------------------------------------------------------

def check_trial(trial: Trial, meta: dict) -> list[tuple[str, str]]:
    """(level, message) with level FAIL / WARN / OK."""
    out: list[tuple[str, str]] = []
    sc = trial.sidecar
    strict = trial.valid  # an invalid attempt's problems are only reported

    def bad(msg: str):
        out.append(("FAIL" if strict else "INFO", msg))

    # Labels.
    if sc["subject"] != meta["subject"]["code"]:
        bad(f"subject {sc['subject']} != session {meta['subject']['code']}")
    if not trial.name.startswith(f"{sc['subject']}_{sc['trial']:02d}_{sc['label']}_a{sc['attempt']}"):
        bad("file name does not match its sidecar")
    if sc["gait"] is not None and sc["gait"]["id"] != sc["label"]:
        bad("gait id != label")
    number = int(sc["subject"].split("-")[1])
    want_pain = "L" if number % 2 == 1 else "R"
    if sc["label"] == "antalgic" and sc["painSide"] != want_pain:
        bad(f"pain side {sc['painSide']} != {want_pain} for {sc['subject']}")
    if sc["label"] == "rotated_foot" and sc["rotation"] not in ("in_toeing", "out_toeing"):
        bad("rotated foot without in/out-toeing")
    if sc["endReason"] is None:
        bad("never finished (no endReason)")
        return out

    # 50 Hz and gaps.
    for side in SIDES:
        rows = trial.rows[side]
        if not rows:
            bad(f"{side}: no samples")
            continue
        worst = 0.0
        for a, b in zip(rows, rows[1:]):
            if b["conn_session"] != a["conn_session"] or b["missing_before"] > 0:
                continue  # a gap, reported below
            step = b["unix_ms"] - a["unix_ms"]
            worst = max(worst, abs(step - SAMPLE_MS))
        if worst > STEP_TOLERANCE_MS:
            bad(f"{side}: a step is {worst:.2f} ms off 20 ms")
        else:
            out.append(("OK", f"{side}: {len(rows)} samples, steps 20 +- {worst:.2f} ms"))
        missing = sum(r["missing_before"] for r in rows)
        sessions = sorted({r["conn_session"] for r in rows})
        if missing:
            bad(f"{side}: {missing} packet(s) missing")
        if len(sessions) > 1:
            bad(f"{side}: link lost (connection sessions {sessions})")
    for g in sc["gaps"]:
        bad(f"gap {g['side']} {g['kind']}"
            + (f" ({g['missingPackets']} packets)" if g["missingPackets"] else ""))

    # Duration.
    if sc["endReason"] == "completed":
        if abs(sc["durationS"] - sc["plannedS"]) > 0.001:
            bad(f"duration {sc['durationS']} s != planned {sc['plannedS']} s")
        need = 0.98 * sc["plannedS"] * 1000 / SAMPLE_MS
        for side in SIDES:
            if len(trial.rows[side]) < need:
                bad(f"{side}: {len(trial.rows[side])} samples < {need:.0f}")
    elif sc["endReason"] == "stopped_early":
        out.append(("WARN", f"stopped early at {sc['durationS']:.1f} of {sc['plannedS']} s"))
    else:
        bad(f"ended {sc['endReason']}")
    if trial.valid and sc["invalidSegments"]:
        out.append(("WARN", f"{len(sc['invalidSegments'])} segment(s) marked invalid (rows valid=0)"))
    return out


def check_alerts(session: Session) -> list[tuple[str, str]]:
    """(level, message) for alerts.csv."""
    if session.alerts is None:
        return [("WARN", "no alerts.csv (exported before S7?)")]
    if session.alert_columns != ALERT_COLUMNS:
        return [("FAIL", f"header {session.alert_columns} != {ALERT_COLUMNS}")]
    out: list[tuple[str, str]] = []
    created = session.meta["createdUnixMs"]
    last = None
    for n, a in enumerate(session.alerts, start=1):
        def bad(msg: str):
            out.append(("FAIL", f"row {n} ({a.get('code')}): {msg}"))
        code = a["code"]
        if code not in ALERT_LEVELS:
            bad("unknown code")
            continue
        try:
            at = int(a["at_ms"])
            level = int(a["level"])
        except ValueError:
            bad("at_ms / level not integers")
            continue
        if level != ALERT_LEVELS[code]:
            bad(f"level {level} != {ALERT_LEVELS[code]}")
        if at < created:
            bad(f"at_ms {at} before the session was created ({created})")
        if last is not None and at < last:
            bad("not sorted by at_ms")
        last = at
        if a["patient_status"] not in PATIENT_STATUSES:
            bad(f"patient_status {a['patient_status']!r}")
        if a["side"] not in SIDES:
            bad(f"side {a['side']!r}")
        if code in ZONE_CODES:
            if a["zone"] not in ZONES:
                bad(f"zone {a['zone']!r}")
        elif a["zone"]:
            bad("a zone on a code without one")
        if code == "TEMP_DELTA":
            if a["site"] not in SITES:
                bad(f"site {a['site']!r}")
        elif a["site"]:
            bad("a site on a code without one")
        for col in ("measured_value", "threshold", "gait_confidence"):
            if a[col]:
                try:
                    float(a[col])
                except ValueError:
                    bad(f"{col} {a[col]!r} is not a number")
        if a["details"]:
            try:
                if not isinstance(json.loads(a["details"]), dict):
                    bad("details is not a JSON object")
            except json.JSONDecodeError:
                bad("details is not JSON")
    if not out:
        kinds = sorted({a["code"] for a in session.alerts})
        out.append(("OK", f"{len(session.alerts)} alert(s)"
                    + (f": {', '.join(kinds)}" if kinds else "")))
    return out


def check_session(session: Session) -> list[tuple[str, str, str]]:
    """(trial, level, message)."""
    out = []
    meta = session.meta
    for t in session.trials:
        for level, msg in check_trial(t, meta):
            out.append((t.name, level, msg))
    # One valid attempt per planned trial.
    labels = ["calibration"] + meta["order"]
    for n, label in enumerate(labels):
        valid = [t for t in session.trials
                 if t.sidecar["trial"] == n and t.label == label and t.valid]
        if len(valid) == 0:
            level = "FAIL" if meta["status"] == "done" else "WARN"
            out.append((f"trial {n} {label}", level, "no valid attempt"))
        elif len(valid) > 1:
            out.append((f"trial {n} {label}", "FAIL", f"{len(valid)} valid attempts"))
    for level, msg in check_alerts(session):
        out.append((ALERTS_CSV, level, msg))
    return out


def print_report(session: Session, report) -> bool:
    print(f"== {session.path.name}  ({session.meta['subject']['code']}, "
          f"{'rehearsal' if session.meta['rehearsal'] else 'study'}, "
          f"{session.meta['status']})")
    for name, level, msg in report:
        print(f"  {level:4}  {name}: {msg}")
    fails = sum(1 for _, level, _ in report if level == "FAIL")
    print(f"  -> {'PASS' if fails == 0 else f'FAIL ({fails})'}")
    return fails == 0


# --- Self-test ---------------------------------------------------------------

def selftest() -> bool:
    ok = True

    def expect(cond: bool, what: str):
        nonlocal ok
        print(f"  {'ok  ' if cond else 'FAIL'}  {what}")
        ok = ok and cond

    print("selftest: shared/capture_fixture (written by the app's code)")
    session_dir = next(p for p in FIXTURE.iterdir() if p.is_dir())
    expected = json.loads((FIXTURE / "expected.json").read_text(encoding="utf-8"))
    mi = load_model_input()

    expect(verify_manifest(session_dir) == [], "manifest checksums match")
    session = load_session(session_dir)
    trial = next(t for t in session.trials if t.name == expected["trial"])
    expect(expected["channels"] == mi["channels"], "fixture channels == model_input.json")
    rows, times = model_matrix(trial, mi)
    expect(len(rows) == len(expected["rows"]) > 0,
           f"{len(rows)} paired rows (app: {len(expected['rows'])})")
    expect(all(abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3
               for a, b in zip(times, expected["pairs"])),
           "same L/R pairs as the app's pairFeet()")
    worst = max((abs(x - y) for r, e in zip(rows, expected["rows"]) for x, y in zip(r, e)),
                default=0.0)
    expect(worst < 1e-9, f"same 24 values per row as the app (max diff {worst:g})")

    report = check_session(session)
    fails = [m for _, level, m in report if level == "FAIL"]
    expect(any("R: 1 packet(s) missing" in m for m in fails), "the fixture's seq gap is a FAIL")
    expect(any("gap R seq_gap" in m for m in fails), "the sidecar's seq gap is reported")
    expect(not any(m.startswith("L:") for m in fails), "the left foot passes 50 Hz with no gaps")
    alerts = [(level, m) for name, level, m in report if name == ALERTS_CSV]
    expect(alerts == [("OK", "1 alert(s): PRESSURE_PEAK")],
           f"alerts.csv: one PRESSURE_PEAK, no problems ({alerts})")
    expect(session.alerts[0]["zone"] == "meta1" and session.alerts[0]["side"] == "L",
           "alerts.csv row: left meta1")

    def alert_problems(rows: list[dict]) -> list[str]:
        s2 = Session(session.path, session.meta, [], rows, ALERT_COLUMNS)
        return [m for level, m in check_alerts(s2) if level == "FAIL"]
    good = dict(session.alerts[0])
    expect(alert_problems([{**good, "level": "4"}]) != [], "alerts.csv: a wrong level fails")
    expect(alert_problems([{**good, "code": "PRESSURE_HIGH"}]) != [], "alerts.csv: an unknown code fails")
    expect(alert_problems([{**good, "zone": "toe"}]) != [], "alerts.csv: an unknown zone fails")
    expect(alert_problems([{**good, "at_ms": str(session.meta["createdUnixMs"] - 1)}]) != [],
           "alerts.csv: an alert before the session fails")
    expect(alert_problems([good, {**good, "at_ms": str(int(good["at_ms"]) - 1)}]) != [],
           "alerts.csv: unsorted rows fail")
    expect(alert_problems([{**good, "code": "TEMP_DELTA", "level": "4", "zone": "",
                            "site": "forefoot"}]) == [],
           "alerts.csv: a TEMP_DELTA row with a site passes")
    # Since S6B a pressure alert's details also hold both feet's foot map.
    with_map = json.dumps({"walking": True, "map": {
        "left": {"kpa": [20.0, 236.5, 85.0, 20.0, 20.0, 60.0],
                 "levels": ["low", "high", "medium", "low", "low", "low"]},
        "right": None}})
    expect(alert_problems([{**good, "details": with_map}]) == [],
           "alerts.csv: details with a nested foot map passes")
    old = Session(session.path, session.meta, [], None, None)
    expect(check_alerts(old)[0][0] == "WARN", "alerts.csv missing (pre-S7 export) is a WARN")

    # Pairing rule edge cases (same as model_channels_test.dart).
    def times_of(l, r):
        return [(a["unix_ms"], b["unix_ms"]) for a, b in
                pair_feet([{"unix_ms": t} for t in l], [{"unix_ms": t} for t in r], 10.0)]
    expect(times_of([0, 20, 40, 60], [7, 26, 52, 75]) == [(0, 7), (20, 26), (60, 52)],
           "pairing: nearest within 10 ms")
    expect(times_of([100], [90, 110]) == [(100, 90)], "pairing: tie to the earlier")
    expect(times_of([100], [110.5]) == [], "pairing: 10 ms inclusive, no further")
    expect(times_of([10, 30], [20]) == [(10, 20)], "pairing: each right row once")

    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / session_dir.name
        shutil.copytree(session_dir, bad)
        csv_file = next(bad.glob("*.csv"))
        data = bytearray(csv_file.read_bytes())
        data[-5] = ord("9") if data[-5] != ord("9") else ord("8")
        csv_file.write_bytes(bytes(data))
        expect(any("SHA-256" in p for p in verify_manifest(bad)), "a changed byte fails the checksum")
        csv_file.write_bytes((session_dir / csv_file.name).read_bytes())
        alerts_file = bad / ALERTS_CSV
        data = bytearray(alerts_file.read_bytes())
        data[-5] = ord("9") if data[-5] != ord("9") else ord("8")
        alerts_file.write_bytes(bytes(data))
        expect(verify_manifest(bad) == [f"{ALERTS_CSV}: SHA-256 mismatch"],
               "a changed byte in alerts.csv fails the checksum")
        try:
            load_session(bad)
            expect(False, "load_session refuses a bad checksum")
        except ValueError:
            expect(True, "load_session refuses a bad checksum")
    print("selftest:", "PASS" if ok else "FAIL")
    return ok


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    c = sub.add_parser("check", help="verify and check session folders")
    c.add_argument("sessions", nargs="+", type=Path)
    args = ap.parse_args(argv)
    if args.selftest:
        return 0 if selftest() else 1
    if args.cmd != "check":
        ap.print_help()
        return 2
    all_ok = True
    for d in args.sessions:
        try:
            session = load_session(d)
        except (ValueError, OSError, KeyError) as e:
            print(f"== {d}\n  FAIL  {e}")
            all_ok = False
            continue
        all_ok = print_report(session, check_session(session)) and all_ok
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

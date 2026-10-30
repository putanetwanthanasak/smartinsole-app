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

Two capture schemas, read per trial (each sidecar names its own, so a
session started before the 8-sensor update and finished after it loads):
  1  6 FSR per foot; temperature temp_forefoot_c / temp_heel_c /
     temp_quality; model rows are the 24-channel v1 layout
  2  8 FSR per foot (DATA-CONTRACT v1.6); temperature temp0_c..temp7_c and
     temp0_q..temp7_q (site i = FSR i); model rows are the 28 channels of
     shared/model_input.json version 2
A schema-1 trial is never padded to 28 channels.

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

SCHEMA = 2  # what the app writes now
SCHEMAS = (1, 2)  # what this loader reads
REPO = Path(__file__).resolve().parents[2]
MODEL_INPUT = REPO / "shared" / "model_input.json"
SENSOR_LAYOUT = REPO / "shared" / "sensor_layout.json"
FIXTURES = REPO / "shared" / "capture_fixture"

SAMPLE_MS = 20.0
STEP_TOLERANCE_MS = 1.0  # 50 Hz: every step 20 +- 1 ms
SIDES = ("L", "R")

INT_COLUMNS = {
    "device_ms", "conn_session", "seq", "i", "missing_before",
    "saturated", "calibrating", "valid",
}
TEMP_SITES = 8
# Per schema: FSR channels per foot, temperature columns (forward-filled).
FSR_COUNT = {1: 6, 2: 8}
TEMP_COLUMNS = {
    1: ("temp_unix_ms", "temp_forefoot_c", "temp_heel_c", "temp_quality"),
    2: ("temp_unix_ms",
        *(f"temp{i}_c" for i in range(TEMP_SITES)),
        *(f"temp{i}_q" for i in range(TEMP_SITES))),
}
TEXT_COLUMNS = {"side", "temp_quality", *(f"temp{i}_q" for i in range(TEMP_SITES))}
TEMP_QUALITIES = ("normal", "poorContact", "sensorFault")


def model_channels(schema: int, model_input: dict | None = None) -> list[str]:
    """Model channel names of a trial of [schema]: schema 2 is
    shared/model_input.json (version 2); schema 1 is the 24-channel v1
    layout it was recorded for, kept here because model_input.json moved on."""
    if schema == 2:
        mi = model_input or load_model_input()
        if mi["version"] != 2:
            raise ValueError(f"model_input.json version {mi['version']}, schema 2 needs 2")
        return list(mi["channels"])
    n = FSR_COUNT[schema]
    return [c for side in SIDES for c in (
        *(f"{side}_fsr{i}_kpa" for i in range(n)),
        *(f"{side}_accel_{a}_g" for a in "xyz"),
        *(f"{side}_gyro_{a}_dps" for a in "xyz"))]

# alerts.csv (mobile/lib/capture/alerts_csv.dart). The levels are the
# contract §8.3 level column (mobile/lib/rules/alert_code.dart); zones are
# the foot layout's ids in FSR channel order (shared/sensor_layout.json).
# The header is checked as either version: an app with the 8-sensor update
# writes the new one, also when it exports a session started before.
ALERTS_CSV = "alerts.csv"
ALERT_COLUMNS_V1 = [
    "at_ms", "code", "level", "patient_status", "side", "zone", "site",
    "measured_value", "threshold", "gait_class", "gait_confidence",
    "read_at_ms", "details",
]
# Since the 8-sensor update: TEMP_DELTA's site with the largest |dT| is in
# `zone`; `site` is only for alerts stored before; `temp_sites` lists every
# qualifying site as zone:deltaC:unix_ms;...
ALERT_COLUMNS = [
    "at_ms", "code", "level", "patient_status", "side", "zone", "site",
    "temp_sites", "measured_value", "threshold", "gait_class",
    "gait_confidence", "read_at_ms", "details",
]
ALERT_LEVELS = {
    "TEMP_DELTA": 4, "PRESSURE_WATCH": 2, "PRESSURE_PEAK": 3,
    "PRESSURE_PTI": 3, "ASYMMETRY_PEAK": 2, "LOAD_CONCENTRATION": 3,
    "DEVICE_LOST": 1, "BATTERY_LOW": 1,
}
ZONE_CODES = {"PRESSURE_WATCH", "PRESSURE_PEAK", "PRESSURE_PTI", "LOAD_CONCENTRATION"}
# Zone / temperature-site ids in channel order (DATA-CONTRACT v1.6 §3.1).
ZONES = tuple(s["id"] for s in json.loads(
    SENSOR_LAYOUT.read_text(encoding="utf-8"))["sites"])
SITES = ("forefoot", "heel")  # TEMP_DELTA stored before the update
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
    schema: int
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
    schema = sidecar.get("schema")
    if schema not in SCHEMAS:
        raise ValueError(f"{csv_path.name}: schema {schema} not in {SCHEMAS}")
    temp_columns = TEMP_COLUMNS[schema]
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        columns = next(reader)
        if columns != sidecar["columns"]:
            raise ValueError(f"{csv_path.name}: header differs from its sidecar")
        n = FSR_COUNT[schema]
        if (f"fsr{n - 1}_kpa" not in columns or f"fsr{n}_kpa" in columns
                or not set(temp_columns) <= set(columns)):
            raise ValueError(f"{csv_path.name}: columns are not schema {schema}'s")
        rows: dict[str, list[dict]] = {s: [] for s in SIDES}
        last_temp: dict[str, dict] = {s: {} for s in SIDES}
        for raw in reader:
            row = {c: _parse(c, v) for c, v in zip(columns, raw)}
            side = row["side"]
            # Temperatures are written once per reading: forward-fill.
            if row["temp_unix_ms"] is not None:
                last_temp[side] = {c: row[c] for c in temp_columns}
            else:
                row.update({c: last_temp[side].get(c) for c in temp_columns})
            rows[side].append(row)
    return Trial(csv_path.stem, sidecar, columns, schema, rows)


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
    """[n, 28] rows (schema 2) in shared/model_input.json channel order, or
    [n, 24] rows (schema 1) in the v1 order ([model_channels]), the feet
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
    channels = model_channels(trial.schema, mi)
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
    # Temperature quality names (schema 2 per site).
    if trial.schema == 2:
        q_cols = [f"temp{i}_q" for i in range(TEMP_SITES)]
        odd = {r[c] for side in SIDES for r in trial.rows[side] for c in q_cols
               if r[c] is not None and r[c] not in TEMP_QUALITIES}
        if odd:
            bad(f"temperature quality {sorted(odd)} not in {TEMP_QUALITIES}")
    if trial.valid and sc["invalidSegments"]:
        out.append(("WARN", f"{len(sc['invalidSegments'])} segment(s) marked invalid (rows valid=0)"))
    return out


def check_alerts(session: Session) -> list[tuple[str, str]]:
    """(level, message) for alerts.csv."""
    if session.alerts is None:
        return [("WARN", "no alerts.csv (exported before S7?)")]
    if session.alert_columns not in (ALERT_COLUMNS, ALERT_COLUMNS_V1):
        return [("FAIL", f"header {session.alert_columns} != {ALERT_COLUMNS}")]
    v2 = session.alert_columns == ALERT_COLUMNS
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
        zones = ZONES if v2 else ZONES[:6]
        if code in ZONE_CODES:
            if a["zone"] not in zones:
                bad(f"zone {a['zone']!r}")
        elif code == "TEMP_DELTA":
            # Since the update: the zone, every site in temp_sites, no
            # `site`. Stored before: `site`, nothing else.
            if a["zone"] or (v2 and a["temp_sites"]):
                if a["site"]:
                    bad("both a zone and a site")
                if a["zone"] not in zones:
                    bad(f"zone {a['zone']!r}")
                for problem in _temp_sites_problems(a.get("temp_sites", ""), a["zone"]):
                    bad(problem)
            elif a["site"] not in SITES:
                bad(f"site {a['site']!r}")
        elif a["zone"]:
            bad("a zone on a code without one")
        if code != "TEMP_DELTA" and (a["site"] or a.get("temp_sites")):
            bad("a temperature site on a code without one")
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


def _temp_sites_problems(cell: str, zone: str) -> list[str]:
    """Problems with a TEMP_DELTA row's temp_sites (zone:deltaC:unix_ms;...):
    known zones, no zone twice, the named zone first."""
    if not cell:
        return ["no temp_sites"]
    out, seen = [], []
    for part in cell.split(";"):
        bits = part.split(":")
        if len(bits) != 3 or bits[0] not in ZONES:
            out.append(f"temp_sites entry {part!r}")
            continue
        try:
            float(bits[1]), int(bits[2])
        except ValueError:
            out.append(f"temp_sites entry {part!r}")
            continue
        if bits[0] in seen:
            out.append(f"temp_sites lists {bits[0]} twice")
        seen.append(bits[0])
    if seen and seen[0] != zone:
        out.append(f"temp_sites starts with {seen[0]}, the zone is {zone}")
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

    mi = load_model_input()
    expect(mi["version"] == 2 and len(mi["channels"]) == 28
           and model_channels(2, mi) == mi["channels"],
           "model_input.json is version 2, 28 channels")
    expect(len(model_channels(1)) == 24 and model_channels(1)[6] == "L_accel_x_g",
           "schema 1 keeps its 24-channel v1 layout")

    sessions = {}
    for schema in SCHEMAS:
        fixture = FIXTURES / f"schema{schema}"
        print(f"selftest: shared/capture_fixture/schema{schema} "
              f"({'frozen, 6 FSR' if schema == 1 else 'written by the app, 8 FSR'})")
        session_dir = next(p for p in fixture.iterdir() if p.is_dir())
        expected = json.loads((fixture / "expected.json").read_text(encoding="utf-8"))
        expect(verify_manifest(session_dir) == [], "manifest checksums match")
        session = load_session(session_dir)
        sessions[schema] = session
        trial = next(t for t in session.trials if t.name == expected["trial"])
        expect(trial.schema == schema, f"trial read as schema {trial.schema}")
        channels = model_channels(schema, mi)
        expect(expected["channels"] == channels,
               f"fixture channels == schema {schema}'s {len(channels)} model channels")
        rows, times = model_matrix(trial, mi)
        expect(len(rows) == len(expected["rows"]) > 0
               and all(len(r) == len(channels) for r in rows),
               f"{len(rows)} paired rows of {len(channels)} (app: {len(expected['rows'])})")
        expect(all(abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3
                   for a, b in zip(times, expected["pairs"])),
               "same L/R pairs as the app's pairFeet()")
        worst = max((abs(x - y) for r, e in zip(rows, expected["rows"]) for x, y in zip(r, e)),
                    default=0.0)
        expect(worst < 1e-9, f"same {len(channels)} values per row as the app (max diff {worst:g})")

        report = check_session(session)
        fails = [m for _, level, m in report if level == "FAIL"]
        expect(any("R: 1 packet(s) missing" in m for m in fails), "the fixture's seq gap is a FAIL")
        expect(any("gap R seq_gap" in m for m in fails), "the sidecar's seq gap is reported")
        expect(not any(m.startswith("L:") for m in fails), "the left foot passes 50 Hz with no gaps")
        expect(not any("temperature quality" in m for m in fails), "temperature qualities are known")
        alerts = [(level, m) for name, level, m in report if name == ALERTS_CSV]
        want = ("1 alert(s): PRESSURE_PEAK" if schema == 1
                else "2 alert(s): PRESSURE_PEAK, TEMP_DELTA")
        expect(alerts == [("OK", want)], f"alerts.csv: {want}, no problems ({alerts})")
        expect(session.alerts[0]["zone"] == "meta1" and session.alerts[0]["side"] == "L",
               "alerts.csv row: left meta1")

    # Schema 2 temperatures: 8 sites, forward-filled, an unread site empty.
    s2 = sessions[2]
    t2 = s2.trials[0]
    first = next(r for r in t2.rows["L"] if r["temp_unix_ms"] is not None)
    expect(first["temp0_c"] == 31.0 and first["temp6_c"] is None
           and first["temp0_q"] == "normal",
           "schema 2: left reading has 8 sites, site 6 unread")
    right = next(r for r in t2.rows["R"] if r["temp_unix_ms"] is not None)
    expect(right["temp2_q"] == "poorContact", "schema 2: right site 2 in poor contact")
    expect(t2.rows["L"][-1]["temp7_c"] is not None, "schema 2: readings forward-fill")
    s1 = sessions[1]
    expect("temp_forefoot_c" in s1.trials[0].columns
           and "fsr6_kpa" not in s1.trials[0].columns,
           "schema 1: 6 FSR, forefoot/heel temperature columns")

    temp = next(a for a in s2.alerts if a["code"] == "TEMP_DELTA")
    expect(temp["zone"] == "heel" and temp["site"] == ""
           and temp["temp_sites"].split(";")[1].startswith("lateralHeel:"),
           "alerts.csv TEMP_DELTA: zone heel, temp_sites heel then lateralHeel")

    def alert_problems(session: Session, rows: list[dict]) -> list[str]:
        s = Session(session.path, session.meta, [], rows, session.alert_columns)
        return [m for level, m in check_alerts(s) if level == "FAIL"]
    for schema, session in sessions.items():
        good = dict(session.alerts[0])
        tag = f"alerts.csv v{1 if schema == 1 else 2}"
        expect(alert_problems(session, [{**good, "level": "4"}]) != [], f"{tag}: a wrong level fails")
        expect(alert_problems(session, [{**good, "code": "PRESSURE_HIGH"}]) != [],
               f"{tag}: an unknown code fails")
        expect(alert_problems(session, [{**good, "zone": "toe"}]) != [], f"{tag}: an unknown zone fails")
        expect(alert_problems(session, [{**good, "at_ms": str(session.meta["createdUnixMs"] - 1)}]) != [],
               f"{tag}: an alert before the session fails")
        expect(alert_problems(session, [good, {**good, "at_ms": str(int(good["at_ms"]) - 1)}]) != [],
               f"{tag}: unsorted rows fail")
        legacy = {**good, "code": "TEMP_DELTA", "level": "4", "zone": "", "site": "forefoot"}
        expect(alert_problems(session, [legacy]) == [],
               f"{tag}: a TEMP_DELTA row stored before the update (site forefoot) passes")
        # Since S6B a pressure alert's details also hold both feet's foot map.
        n = 6 if schema == 1 else 8
        with_map = json.dumps({"walking": True, "map": {
            "left": {"kpa": [20.0, 236.5] + [20.0] * (n - 2),
                     "levels": ["low", "high"] + ["low"] * (n - 2)},
            "right": None}})
        expect(alert_problems(session, [{**good, "details": with_map}]) == [],
               f"{tag}: details with a nested foot map passes")
    expect(alert_problems(s1, [{**dict(s1.alerts[0]), "zone": "lateralHeel"}]) != [],
           "alerts.csv v1: an 8-sensor zone fails")
    expect(alert_problems(s2, [{**dict(s2.alerts[0]), "zone": "lateralHeel"}]) == [],
           "alerts.csv v2: zone lateralHeel passes")
    for cell, what in (("", "no temp_sites"), ("heel:2.6:1;heel:2.4:2", "a zone twice"),
                       ("lateralHeel:2.3:1;heel:2.6:1", "the named zone not first"),
                       ("toe:2.6:1", "an unknown zone"), ("heel:x:1", "a bad number")):
        expect(alert_problems(s2, [{**temp, "temp_sites": cell}]) != [],
               f"alerts.csv v2 TEMP_DELTA: {what} fails")
    expect(alert_problems(s2, [{**temp, "site": "heel"}]) != [],
           "alerts.csv v2 TEMP_DELTA: both a zone and a site fails")
    expect(alert_problems(s2, [{**dict(s2.alerts[0]), "temp_sites": "heel:2.6:1"}]) != [],
           "alerts.csv v2: temp_sites on a pressure alert fails")
    old = Session(s2.path, s2.meta, [], None, None)
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

    session_dir = s2.path
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / session_dir.name
        shutil.copytree(session_dir, bad)
        csv_file = next(p for p in bad.glob("*.csv") if p.name != ALERTS_CSV)
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
        # A session continued after the update: a schema-1 trial next to
        # schema-2 ones loads, each by its own schema.
        mixed = Path(tmp) / "mixed"
        shutil.copytree(session_dir, mixed)
        old_trial = s1.trials[0]
        for ext in (".csv", ".json"):
            src = s1.path / f"{old_trial.name}{ext}"
            shutil.copy(src, mixed / f"OLD_{old_trial.name}{ext}")
        m = load_session(mixed, verify=False)
        expect(sorted(t.schema for t in m.trials) == [1, 2]
               and all(len(model_matrix(t, mi)[0][0]) == len(model_channels(t.schema, mi))
                       for t in m.trials),
               "a session with schema-1 and schema-2 trials loads each by its own schema")
        # A trial whose columns do not match its schema is refused.
        lie = Path(tmp) / "lie"
        shutil.copytree(s1.path, lie)
        side = next(lie.glob("*_a1.json"))
        j = json.loads(side.read_text(encoding="utf-8"))
        j["schema"] = 2
        side.write_text(json.dumps(j), encoding="utf-8")
        try:
            load_session(lie, verify=False)
            expect(False, "a schema-1 CSV labelled schema 2 is refused")
        except ValueError:
            expect(True, "a schema-1 CSV labelled schema 2 is refused")
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

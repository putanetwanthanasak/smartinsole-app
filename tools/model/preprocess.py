#!/usr/bin/env python3
"""Model A preprocessing "ทางเอ": the Python reference (S9).

DATA-CONTRACT v1.6 §7.1 and shared/model_preprocess.json. Two steps, the
same in the app (mobile/lib/gait/preprocess.dart) and in training:

1. Personal baseline. Per foot and channel, the median of that foot's
   samples over the 30 s quiet-standing calibration recorded before the
   trials (capture trial 00). It is subtracted from every model channel
   (all 28: 8 FSR kPa + accel g + gyro deg/s per foot). The window and
   its rejection rules are the app's one baseline function
   (foot_baseline_window here, FootBaselineWindow in
   mobile/lib/gait/baseline_window.dart, BACKLOG 74): the first
   baselineSeconds x 50 Hz rows that pass; shared/test_vectors/baseline/
   checks both.
2. Min-Max to 0-1: (x - baseline - min) / (max - min), with min/max per
   channel from the training subjects only (per LOSO fold), shipped in
   normalization.json (method "baseline-minmax"). No clipping.

Arithmetic is float64 in a fixed order, then rounded to float32 (round to
nearest even, as numpy's astype(float32) and Dart's Float32List). The
median of an even count is (a + b) * 0.5 of the two middle values. With
the same order the app gives the same float32 bits:
shared/test_vectors/model_preprocess/vectors.json checks both.

Standard library only (numpy is not needed).

  python3 tools/model/preprocess.py --selftest       check the vectors
  python3 tools/model/preprocess.py --make-vectors   regenerate them
  python3 tools/model/preprocess.py baseline <session-dir>...
      each session's trial-00 baseline, or why it has none
  python3 tools/model/preprocess.py fit <session-dir>...
      LOSO folds over the sessions (one subject each): prints each fold's
      min/max; --out DIR writes DIR/<held-out code>/normalization.json
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "shared" / "model_preprocess.json"
MODEL_INPUT = ROOT / "shared" / "model_input.json"
VECTORS = ROOT / "shared" / "test_vectors" / "model_preprocess" / "vectors.json"
THRESHOLDS = ROOT / "shared" / "thresholds.json"
BASELINE_VECTORS = ROOT / "shared" / "test_vectors" / "baseline"
SAMPLE_MS = 20  # rule 1: sample i at t0 + 20 i
SIDES = ("L", "R")
METHOD = "baseline-minmax"
# Capture trial 00 is the 30 s standing calibration (docs/STUDY-CAPTURE.md).
CALIBRATION_LABEL = "calibration"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_spec(path: Path = SPEC) -> dict:
    """shared/model_preprocess.json, refused unless it says what this code
    does (the app refuses the same way)."""
    spec = load_json(path)
    expected = {"version": 1, "baselineStatistic": "median", "baselineChannels": "all",
                "scale": "minmax", "clip": False, "normalizationMethod": METHOD}
    for key, value in expected.items():
        if spec.get(key) != value:
            raise ValueError(f"model_preprocess.json {key} is {spec.get(key)!r}, "
                             f"this code does {value!r}")
    tol = spec.get("baselineToleranceSamples")
    if type(tol) is not int or not 0 <= tol < window_samples(spec):
        raise ValueError(f"model_preprocess.json baselineToleranceSamples is {tol!r}, not a "
                         f"whole number from 0 to below the window")
    return spec


def foot_columns(model_input: dict, side: str) -> list[str]:
    """The model channels of one foot, without the side prefix, in model
    order: "fsr0_kpa" ... "gyro_z_dps" (the capture CSV's column names)."""
    return [c[2:] for c in model_input["channels"] if c.startswith(side + "_")]


def f32(v: float) -> float:
    return struct.unpack("<f", struct.pack("<f", v))[0]


def f32_bits(v: float) -> str:
    return struct.pack("<f", v)[::-1].hex()


def median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    if n == 0:
        raise ValueError("median of no values")
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) * 0.5


def foot_baseline(rows: list[list[float]]) -> list[float]:
    """Per channel median of one foot's calibration rows (n x 14)."""
    if not rows:
        raise ValueError("no calibration rows")
    return [median([r[c] for r in rows]) for c in range(len(rows[0]))]


def model_baseline(left: list[float], right: list[float], model_input: dict) -> list[float]:
    """The two feet's baselines (14 each, foot order) as 28 values in
    model channel order."""
    per_side = {"L": list(left), "R": list(right)}
    out = []
    used = {"L": 0, "R": 0}
    for c in model_input["channels"]:
        side = c[0]
        out.append(per_side[side][used[side]])
        used[side] += 1
    return out


def subtract(rows: list[list[float]], baseline: list[float]) -> list[list[float]]:
    return [[x - b for x, b in zip(r, baseline)] for r in rows]


def apply(rows: list[list[float]], baseline: list[float], mins: list[float],
          maxs: list[float]) -> list[list[float]]:
    """The model input: ((x - b) - min) / (max - min) in float64, then
    float32. No clipping."""
    return [[f32(((x - b) - lo) / (hi - lo)) for x, b, lo, hi in zip(r, baseline, mins, maxs)]
            for r in rows]


def fit_minmax(subject_rows: list[list[list[float]]]) -> tuple[list[float], list[float]]:
    """Min and max per channel over the training subjects' rows, each
    already baseline-subtracted (one list of rows per subject)."""
    rows = [r for subject in subject_rows for r in subject]
    if not rows:
        raise ValueError("no training rows")
    n = len(rows[0])
    mins = [min(r[c] for r in rows) for c in range(n)]
    maxs = [max(r[c] for r in rows) for c in range(n)]
    for c in range(n):
        if not maxs[c] > mins[c]:
            raise ValueError(f"channel {c}: max {maxs[c]} is not above min {mins[c]}")
    return mins, maxs


def normalization_json(mins: list[float], maxs: list[float], model_input: dict,
                       about: str) -> dict:
    return {"version": model_input["version"], "method": METHOD, "about": about,
            "channels": list(model_input["channels"]), "min": mins, "max": maxs}


# --- The one baseline function (BACKLOG 74) ------------------------------------
#
# A port of mobile/lib/gait/baseline_window.dart, row by row and in the same
# float64 order. The failure ids are the Dart enum names.

def dart_round(x: float) -> int:
    """Dart's num.round() for x >= 0: half away from zero (Python's round()
    is half to even, which differs at exactly .5). The gate only rounds
    non-negative values."""
    if x < 0:
        raise ValueError("dart_round is for non-negative values")
    i = math.floor(x)
    return i + 1 if x - i >= 0.5 else i


class WalkingGate:
    """Contract §8.3.2's walking gate (mobile/lib/rules/walking_gate.dart):
    walking while the mean of |‖a‖ − 1 g| over the last walkingWindowMs of
    samples is at or above walkingAccelG, compared in whole mg."""

    def __init__(self, window_ms: int, accel_g: float):
        self.window_ms = window_ms
        self.accel_g = accel_g
        self.devs: list[tuple[float, float]] = []

    def add(self, unix_ms: float, accel: list[float]) -> bool:
        sq = 0.0
        for a in accel:
            sq += a * a
        self.devs.append((unix_ms, abs(math.sqrt(sq) - 1)))
        while self.devs[0][0] <= unix_ms - self.window_ms:
            self.devs.pop(0)
        total = 0.0
        for _, d in self.devs:
            total += d
        return dart_round(total / len(self.devs) * 1000) >= dart_round(self.accel_g * 1000)


def load_thresholds(path: Path = THRESHOLDS) -> dict:
    """The keys the baseline rules read from shared/thresholds.json."""
    t = load_json(path)
    return {"windowMs": t["motion"]["walkingWindowMs"],
            "accelG": t["motion"]["walkingAccelG"],
            "contactKpa": t["steps"]["contactKpa"]}


def window_samples(spec: dict) -> int:
    """baselineSeconds at 50 Hz."""
    return spec["baselineSeconds"] * 1000 // SAMPLE_MS


def min_samples(spec: dict) -> int:
    """The fewest rows a trial may end with and still give a baseline."""
    return window_samples(spec) - spec["baselineToleranceSamples"]


FSR_COLUMNS = [f"fsr{i}_kpa" for i in range(8)]
ACCEL_COLUMNS = ["accel_x_g", "accel_y_g", "accel_z_g"]


def foot_baseline_window(rows: list[dict], cols: list[str], n: int, thresholds: dict,
                         min_n: int | None = None
                         ) -> tuple[list[float] | None, str | None, int]:
    """One foot's baseline from its rows in order (capture CSV row dicts):
    (values, None, n) once the first n rows pass, else (None, failure id,
    rows kept). Rules, in order: a new conn_session or missing_before > 0
    after the first row, calibrating, valid 0, not 8 FSR, the walking gate,
    summed kPa at or below steps.contactKpa. Rows that end with every rule
    passed give a baseline from the k rows kept when k >= min_n (default
    n; baselineToleranceSamples below it), else tooShort."""
    gate = WalkingGate(thresholds["windowMs"], thresholds["accelG"])
    kept: list[list[float]] = []
    session = None
    for r in rows:
        if len(kept) >= n:
            break
        if session is not None and r["conn_session"] != session:
            return None, "reconnected", len(kept)
        if session is not None and r["missing_before"] > 0:
            return None, "lostPackets", len(kept)
        if r["calibrating"]:
            return None, "calibrating", len(kept)
        if r["valid"] != 1:
            return None, "markedInvalid", len(kept)
        if any(r.get(c) is None for c in cols):
            return None, "wrongInsole", len(kept)
        session = r["conn_session"]
        if gate.add(r["unix_ms"], [r[c] for c in ACCEL_COLUMNS]):
            return None, "moved", len(kept)
        load = 0.0
        for c in FSR_COLUMNS:
            load += r[c]
        if load <= thresholds["contactKpa"]:
            return None, "notLoaded", len(kept)
        kept.append([r[c] for c in cols])
    if len(kept) < (n if min_n is None else min_n):
        return None, "tooShort", len(kept)
    return foot_baseline(kept), None, len(kept)


def trial_baseline(trial, model_input: dict | None = None, spec: dict | None = None,
                   thresholds: dict | None = None) -> dict:
    """A capture trial's baseline per foot: {"L": (values, failure, count),
    "R": ...}, through foot_baseline_window."""
    model_input = model_input or load_json(MODEL_INPUT)
    spec = spec or load_spec()
    thresholds = thresholds or load_thresholds()
    return {side: foot_baseline_window(trial.rows[side], foot_columns(model_input, side),
                                       window_samples(spec), thresholds, min_samples(spec))
            for side in SIDES}


def read_trial_csv(path: Path) -> dict:
    """{"L": [row dicts], "R": [...]} from a capture trial CSV, parsed as
    tools/capture/load_capture.py parses it."""
    lc = _load_capture()
    out = {s: [] for s in SIDES}
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        columns = next(reader)
        for raw in reader:
            row = {c: lc._parse(c, v) for c, v in zip(columns, raw)}
            out[row["side"]].append(row)
    return out


# --- Capture sessions ----------------------------------------------------------

def _load_capture():
    sys.path.insert(0, str(ROOT / "tools" / "capture"))
    import load_capture  # noqa: E402
    return load_capture


def session_baseline(session, model_input: dict) -> list[float]:
    """The subject's baseline (28, model order) from the newest valid
    calibration attempt (trial 00) whose two feet pass the baseline rules
    (user decision 2026-11-02); else ValueError naming each attempt's
    reason."""
    cal = [t for t in session.trials if t.label == CALIBRATION_LABEL and t.valid]
    if not cal:
        raise ValueError(f"{session.path.name}: no valid calibration trial")
    spec, thresholds = load_spec(), load_thresholds()
    reasons = []
    for trial in reversed(cal):
        feet = trial_baseline(trial, model_input, spec, thresholds)
        failed = [f"{side} {feet[side][1]}" for side in SIDES if feet[side][1]]
        if not failed:
            return model_baseline(feet["L"][0], feet["R"][0], model_input)
        reasons.append(f"{trial.name}: {', '.join(failed)}")
    raise ValueError(f"{session.path.name}: no calibration attempt gives a baseline ("
                     + "; ".join(reasons) + ")")


def session_gait_rows(session, model_input: dict) -> list[list[float]]:
    """Baseline-subtracted 28-channel rows of the session's valid gait
    trials (01-05), paired as the app pairs them."""
    lc = _load_capture()
    baseline = session_baseline(session, model_input)
    out = []
    for t in session.trials:
        if t.label == CALIBRATION_LABEL or not t.valid or t.schema != 2:
            continue
        rows, _ = lc.model_matrix(t, model_input)
        out.extend(subtract(rows, baseline))
    return out


def loso(session_dirs: list[Path], model_input: dict):
    """(held-out code, mins, maxs) per fold: min/max from every other
    subject only."""
    lc = _load_capture()
    subjects = {}
    for d in session_dirs:
        s = lc.load_session(Path(d))
        subjects.setdefault(s.meta["subject"]["code"], []).extend(session_gait_rows(s, model_input))
    for code in sorted(subjects):
        train = [rows for c, rows in subjects.items() if c != code]
        mins, maxs = fit_minmax(train)
        yield code, mins, maxs


# --- Test vectors --------------------------------------------------------------

def _case(rng: random.Random, name: str, n_cal: int, n_rows: int, model_input: dict) -> dict:
    per_foot = len(foot_columns(model_input, "L"))
    channels = len(model_input["channels"])

    def value(c: int) -> float:
        # FSR-like kPa, accel-like g, gyro-like deg/s, with ties and negatives.
        k = c % per_foot
        if k < 8:
            return rng.choice([0.01, 12.5, 12.5, rng.uniform(0, 300)])
        if k < 11:
            return rng.uniform(-2, 2)
        return rng.uniform(-250, 250)

    cal = {s: [[value(c) for c in range(per_foot)] for _ in range(n_cal)] for s in SIDES}
    rows = [[value(c % per_foot) for c in range(channels)] for _ in range(n_rows)]
    left, right = foot_baseline(cal["L"]), foot_baseline(cal["R"])
    baseline = model_baseline(left, right, model_input)
    sub = subtract(rows, baseline)
    mins = [min(r[c] for r in sub) - 1.0 for c in range(channels)]
    maxs = [max(r[c] for r in sub) * 0.5 + 0.25 for c in range(channels)]
    # Keep max above min; some values then fall outside 0-1 (no clipping).
    maxs = [hi if hi > lo else lo + 3.0 for lo, hi in zip(mins, maxs)]
    out = apply(rows, baseline, mins, maxs)
    return {
        "name": name,
        "calibration": cal,
        "rows": rows,
        "min": mins,
        "max": maxs,
        "expected": {
            "footBaseline": {"L": left, "R": right},
            "baseline": baseline,
            "windowF32Bits": [[f32_bits(v) for v in r] for r in out],
        },
    }


def make_vectors(path: Path = VECTORS) -> dict:
    model_input = load_json(MODEL_INPUT)
    load_spec()
    rng = random.Random(20261101)
    doc = {
        "about": "Model A preprocessing vectors (S9, shared/model_preprocess.json). "
                 "Made by tools/model/preprocess.py --make-vectors; never hand-edited. "
                 "calibration: per foot, n x 14 rows in the foot's model channel order; "
                 "rows: raw 28-channel model rows; expected.windowF32Bits: "
                 "((x - baseline) - min) / (max - min) as float32 bits (big-endian hex).",
        "modelInputVersion": model_input["version"],
        "preprocessVersion": 1,
        "cases": [
            _case(rng, "odd calibration count", 7, 5, model_input),
            _case(rng, "even calibration count", 8, 5, model_input),
            _case(rng, "one calibration sample", 1, 3, model_input),
            _case(rng, "12 s at 50 Hz (even count)", 600, 100, model_input),
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc) + "\n", encoding="utf-8")
    return doc


def check_vectors(path: Path = VECTORS) -> list[str]:
    model_input = load_json(MODEL_INPUT)
    doc = load_json(path)
    problems = []
    if doc["modelInputVersion"] != model_input["version"]:
        problems.append("vectors were made for another model_input.json version")
    for case in doc["cases"]:
        exp = case["expected"]
        left = foot_baseline(case["calibration"]["L"])
        right = foot_baseline(case["calibration"]["R"])
        if left != exp["footBaseline"]["L"] or right != exp["footBaseline"]["R"]:
            problems.append(f"{case['name']}: foot baseline differs")
        baseline = model_baseline(left, right, model_input)
        if baseline != exp["baseline"]:
            problems.append(f"{case['name']}: baseline differs")
        out = apply(case["rows"], baseline, case["min"], case["max"])
        bits = [[f32_bits(v) for v in r] for r in out]
        if bits != exp["windowF32Bits"]:
            problems.append(f"{case['name']}: window bits differ")
    return problems


# --- Baseline vectors (trial-00 fixture, BACKLOG 74) ----------------------------

CAPTURE_FIXTURE_SIDECAR = (ROOT / "shared" / "capture_fixture" / "schema2"
                           / "TEST-009_20261110-090000" / "TEST-009_00_calibration_a1.json")


def _trial_csv(rng: random.Random, seconds: float, change=None, step: float = 19.95) -> str:
    """A synthetic schema-2 trial-00 CSV as the app writes it (column order
    from the capture fixture's sidecar, the app's number formats): both
    feet standing still, 8-sample packets, a DeviceClock-like [step] (19.95 ms by default)
    between samples, the trial window [start, start + seconds). [change](side, i, row)
    edits row i of a foot before it is written."""
    columns = load_json(CAPTURE_FIXTURE_SIDECAR)["columns"]
    start = 1794276000000.0
    lines = [",".join(columns)]
    feet = {}
    for side, offset in (("L", 3.0), ("R", 13.0)):
        rows = []
        stand = [rng.uniform(15, 60) for _ in range(8)]
        i = 0
        while True:
            t = start + offset + i * step
            if t >= start + seconds * 1000:
                break
            row = {
                "unix_ms": t, "device_ms": 50000 + i * 20, "side": side,
                "conn_session": 1, "seq": i // 8, "i": i % 8,
                "missing_before": 0, "saturated": 0, "calibrating": 0, "valid": 1,
                "kpa": [max(0.0, k + rng.gauss(0, 1.5)) for k in stand],
                "accel": [rng.gauss(0, 0.01), rng.gauss(0, 0.01), 1 + rng.gauss(0, 0.01)],
                "gyro": [rng.gauss(0, 0.8) for _ in range(3)],
            }
            if change:
                change(side, i, row)
            if row is not None and not row.get("drop"):
                rows.append(row)
            i += 1
        feet[side] = rows
    merged = sorted(feet["L"] + feet["R"], key=lambda r: r["unix_ms"])
    for r in merged:
        kpa = [f"{k:.3f}" for k in r["kpa"]]
        adc = [str(int(k * 4)) for k in r["kpa"]]
        vals = [f"{r['unix_ms']:.3f}", str(r["device_ms"]), r["side"], str(r["conn_session"]),
                str(r["seq"]), str(r["i"]), str(r["missing_before"]), str(r["saturated"]),
                str(r["calibrating"]), str(r["valid"]), *adc, *kpa,
                *(f"{a:.6f}" for a in r["accel"]), *(f"{g:.4f}" for g in r["gyro"])]
        vals += [""] * (len(columns) - len(vals))
        lines.append(",".join(vals))
    return "\n".join(lines) + "\n"


def _baseline_cases() -> list[tuple[str, str, float, object, float]]:
    """(name, what it shows, seconds, change, sample step ms). Each failure
    is on one foot; the other foot breaks no rule."""
    def on(side, lo, hi, **fields):
        def change(s, i, row):
            if s == side and lo <= i < hi:
                for k, v in fields.items():
                    row[k] = v(row, i) if callable(v) else v
        return change

    def lost(s, i, row):
        # Right foot: packet 12 (rows 96-103) lost, the next packet says so.
        if s == "R" and 96 <= i < 104:
            row["drop"] = True
        if s == "R" and i == 104:
            row["missing_before"] = 1

    def first_loss_ok(s, i, row):
        # A loss before the trial shows on its first row: not a failure.
        if i == 0:
            row["missing_before"] = 2
        if i >= 1510:  # moving after the window: ignored
            row["accel"] = [0.0, 0.0, 1.6 if i % 2 else 0.4]

    shake = lambda row, i: [0.0, 0.0, 1.5 if i % 2 else 0.5]  # noqa: E731
    light = lambda row, i: [0.4] * 8  # noqa: E731
    # The failure cases are 4 s (the other foot then reads tooShort), to
    # keep the fixture small; only "ok" needs the whole window.
    return [
        ("ok", "30 s standing, both feet: the first 1500 rows of each (a loss before "
               "the trial on the first row and movement after the window are ignored)",
         30.0, first_loss_ok, 19.95),
        ("lost_packets", "right foot: a lost packet at 1.9 s", 4.0, lost, 19.95),
        ("reconnected", "left foot: a new conn_session from 2.4 s", 4.0,
         on("L", 120, 10**6, conn_session=2, seq=lambda r, i: (i - 120) // 8), 19.95),
        ("calibrating", "right foot: a TARE running at 1.2 s", 4.0,
         on("R", 60, 68, calibrating=1), 19.95),
        ("marked_invalid", "left foot: rows marked invalid at 3 s", 4.0,
         on("L", 150, 170, valid=0), 19.95),
        ("moved", "right foot: the walking gate turns on at 2 s", 4.0,
         on("R", 100, 200, accel=shake), 19.95),
        ("not_loaded", "left foot: summed kPa at or below steps.contactKpa at 2.6 s", 4.0,
         on("L", 130, 10**6, kpa=light), 19.95),
        ("too_short", "a 10 s rehearsal calibration: both feet too short", 10.0, None, 19.95),
        # Last, so the cases above keep their random draws.
        ("slow_clock", "30 s standing with a 20.05 ms step (a board clock slow against "
                       "the phone): 1497 / 1496 rows, within baselineToleranceSamples",
         30.0, None, 20.05),
    ]


def _expected(rows: dict, model_input: dict, spec: dict, thresholds: dict) -> dict:
    n = window_samples(spec)
    out = {}
    for side in SIDES:
        values, failure, count = foot_baseline_window(rows[side], foot_columns(model_input, side),
                                                      n, thresholds, min_samples(spec))
        out[side] = {"failure": failure, "sampleCount": count, "values": values}
    return out


def make_baseline_vectors(path: Path = BASELINE_VECTORS) -> dict:
    model_input, spec, thresholds = load_json(MODEL_INPUT), load_spec(), load_thresholds()
    rng = random.Random(20261102)
    path.mkdir(parents=True, exist_ok=True)
    cases = []
    for name, about, seconds, change, step in _baseline_cases():
        csv_path = path / f"{name}.csv"
        csv_path.write_text(_trial_csv(rng, seconds, change, step), encoding="utf-8")
        cases.append({"name": name, "about": about, "csv": csv_path.name,
                      "expected": _expected(read_trial_csv(csv_path), model_input, spec,
                                            thresholds)})
    doc = {
        "about": "Trial-00 baseline vectors (S9-2, BACKLOG 74): synthetic schema-2 capture "
                 "trial CSVs, each run through the one baseline function "
                 "(tools/model/preprocess.py foot_baseline_window; the app's "
                 "FootBaselineWindow must give the same). Made by preprocess.py "
                 "--make-vectors; never hand-edited. expected per foot: failure id (null = "
                 "ok), rows kept, the 14 float64 medians in the foot's model channel order.",
        "baselineSeconds": spec["baselineSeconds"],
        "baselineToleranceSamples": spec["baselineToleranceSamples"],
        "thresholds": thresholds,
        "cases": cases,
    }
    (path / "expected.json").write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    return doc


def check_baseline_vectors(path: Path = BASELINE_VECTORS) -> list[str]:
    model_input, spec, thresholds = load_json(MODEL_INPUT), load_spec(), load_thresholds()
    doc = load_json(path / "expected.json")
    problems = []
    if (doc["thresholds"] != thresholds or doc["baselineSeconds"] != spec["baselineSeconds"]
            or doc.get("baselineToleranceSamples") != spec["baselineToleranceSamples"]):
        problems.append("baseline vectors were made with other thresholds; --make-vectors")
    for case in doc["cases"]:
        got = _expected(read_trial_csv(path / case["csv"]), model_input, spec, thresholds)
        if got != case["expected"]:
            problems.append(f"baseline {case['name']}: differs")
    return problems


def selftest() -> bool:
    ok = True

    def expect(cond: bool, what: str):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok &= cond

    load_spec()
    expect(median([3.0, 1.0, 2.0]) == 2.0, "median of an odd count")
    expect(median([4.0, 1.0, 3.0, 2.0]) == 2.5, "median of an even count")
    mi = load_json(MODEL_INPUT)
    expect(len(foot_columns(mi, "L")) == 14 and foot_columns(mi, "L")[8] == "accel_x_g",
           "foot columns are the capture CSV's names in model order")
    b = model_baseline(list(range(14)), list(range(100, 114)), mi)
    expect(b[:14] == list(range(14)) and b[14:] == list(range(100, 114)),
           "baseline in model channel order")
    out = apply([[2.0, -1.0]], [1.0, 0.0], [0.0, 0.0], [2.0, 2.0])
    expect(out == [[0.5, -0.5]], "no clipping below 0")
    try:
        fit_minmax([[[1.0], [1.0]]])
        expect(False, "a constant channel is refused")
    except ValueError:
        expect(True, "a constant channel is refused")
    mins, maxs = fit_minmax([[[0.0, 5.0]], [[2.0, -5.0]]])
    expect(mins == [0.0, -5.0] and maxs == [2.0, 5.0], "min/max over subjects")
    expect(dart_round(2.5) == 3 and dart_round(149.5) == 150 and dart_round(0.49) == 0,
           "the gate rounds half away from zero, as Dart")
    th = load_thresholds()
    gate = WalkingGate(th["windowMs"], th["accelG"])
    expect(not gate.add(0.0, [0.0, 0.0, 1.0]) and gate.add(20.0, [0.0, 0.0, 1 + 4 * th["accelG"]]),
           "the walking gate turns on at a mean deviation of walkingAccelG")
    lc = _load_capture()
    fixture = lc.load_session(ROOT / "shared" / "capture_fixture" / "schema2"
                              / "TEST-009_20261110-090000")
    # The capture fixture's trial 00 (6.4 s, synthetic accel far from 1 g)
    # breaks the rules: no baseline, and the error names the attempt.
    try:
        session_baseline(fixture, mi)
        expect(False, "a calibration that breaks the rules gives no baseline")
    except ValueError as e:
        expect("TEST-009_00_calibration_a1: L " in str(e),
               "a calibration that breaks the rules gives no baseline, naming the attempt")
    for p in check_baseline_vectors():
        print("FAIL " + p)
        ok = False
    expect(not check_baseline_vectors(),
           f"baseline vectors in {BASELINE_VECTORS.relative_to(ROOT)} reproduce")
    doc = load_json(BASELINE_VECTORS / "expected.json")
    kinds = {c["name"]: {s: c["expected"][s]["failure"] for s in SIDES} for c in doc["cases"]}
    expect(kinds["ok"] == {"L": None, "R": None}
           and all(c["expected"][s]["sampleCount"] == window_samples(load_spec())
                   for c in doc["cases"] if c["name"] == "ok" for s in SIDES),
           "the ok trial gives both feet exactly baselineSeconds x 50 rows")
    expect(kinds["lost_packets"]["R"] == "lostPackets" and kinds["reconnected"]["L"] == "reconnected"
           and kinds["calibrating"]["R"] == "calibrating"
           and kinds["marked_invalid"]["L"] == "markedInvalid"
           and kinds["moved"]["R"] == "moved" and kinds["not_loaded"]["L"] == "notLoaded"
           and kinds["too_short"] == {"L": "tooShort", "R": "tooShort"},
           "each failure case names its failure")
    slow = next(c for c in doc["cases"] if c["name"] == "slow_clock")["expected"]
    spec = load_spec()
    n, lo = window_samples(spec), min_samples(spec)
    expect(all(slow[s]["failure"] is None and lo <= slow[s]["sampleCount"] < n for s in SIDES),
           "a trial a few rows short (slow board clock) still gives a baseline")
    cols = [f"c{i}" for i in range(14)]
    def standing(k):
        return [{"unix_ms": 1000.0 + i * 20, "conn_session": 1, "missing_before": 0,
                 "calibrating": 0, "valid": 1, **{c: 30.0 for c in FSR_COLUMNS},
                 "accel_x_g": 0.0, "accel_y_g": 0.0, "accel_z_g": 1.0,
                 **{c: float(i % 3) for c in cols}} for i in range(k)]
    thr = load_thresholds()
    expect(foot_baseline_window(standing(lo), cols, n, thr, lo)[1] is None
           and foot_baseline_window(standing(lo - 1), cols, n, thr, lo)[1] == "tooShort"
           and foot_baseline_window(standing(n + 3), cols, n, thr, lo)[2] == n,
           "the tolerance boundary: N - tolerance rows pass, one fewer is tooShort, "
           "a longer trial keeps exactly N")
    problems = check_vectors()
    for p in problems:
        print("FAIL " + p)
    expect(not problems, f"vectors in {VECTORS.relative_to(ROOT)} reproduce")
    print("PASS" if ok else "FAILED")
    return ok


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--make-vectors", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    fit = sub.add_parser("fit", help="LOSO min/max over capture sessions")
    fit.add_argument("sessions", nargs="+", type=Path)
    fit.add_argument("--out", type=Path)
    base = sub.add_parser("baseline", help="each session's trial-00 baseline")
    base.add_argument("sessions", nargs="+", type=Path)
    args = ap.parse_args(argv)
    if args.make_vectors:
        make_vectors()
        make_baseline_vectors()
        print(f"wrote {VECTORS.relative_to(ROOT)} and {BASELINE_VECTORS.relative_to(ROOT)}/")
        return 0
    if args.selftest:
        return 0 if selftest() else 1
    if args.cmd == "fit":
        load_spec()
        mi = load_json(MODEL_INPUT)
        for code, mins, maxs in loso(args.sessions, mi):
            print(f"fold {code}: min {mins}\n         max {maxs}")
            if args.out:
                d = args.out / code
                d.mkdir(parents=True, exist_ok=True)
                about = (f"LOSO fold holding out {code}: min/max over the other subjects' "
                         "baseline-subtracted gait trials (tools/model/preprocess.py).")
                (d / "normalization.json").write_text(
                    json.dumps(normalization_json(mins, maxs, mi, about), indent=2) + "\n",
                    encoding="utf-8")
        return 0
    if args.cmd == "baseline":
        mi = load_json(MODEL_INPUT)
        lc = _load_capture()
        bad = 0
        for d in args.sessions:
            try:
                b = session_baseline(lc.load_session(d), mi)
                print(f"{Path(d).name}: OK {b}")
            except ValueError as e:
                bad += 1
                print(e)
        return 1 if bad else 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

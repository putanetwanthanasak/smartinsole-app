#!/usr/bin/env python3
"""Model A preprocessing "ทางเอ": the Python reference (S9).

DATA-CONTRACT v1.6 §7.1 and shared/model_preprocess.json. Two steps, the
same in the app (mobile/lib/gait/preprocess.dart) and in training:

1. Personal baseline. Per foot and channel, the median of that foot's
   samples over the 30 s quiet-standing calibration recorded before the
   trials (capture trial 00). It is subtracted from every model channel
   (all 28: 8 FSR kPa + accel g + gyro deg/s per foot).
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
  python3 tools/model/preprocess.py fit <session-dir>...
      LOSO folds over the sessions (one subject each): prints each fold's
      min/max; --out DIR writes DIR/<held-out code>/normalization.json
"""

from __future__ import annotations

import argparse
import json
import random
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "shared" / "model_preprocess.json"
MODEL_INPUT = ROOT / "shared" / "model_input.json"
VECTORS = ROOT / "shared" / "test_vectors" / "model_preprocess" / "vectors.json"
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


# --- Capture sessions ----------------------------------------------------------

def _load_capture():
    sys.path.insert(0, str(ROOT / "tools" / "capture"))
    import load_capture  # noqa: E402
    return load_capture


def session_baseline(session, model_input: dict) -> list[float]:
    """The subject's baseline (28, model order) from the session's valid
    calibration trial (the newest valid attempt)."""
    cal = [t for t in session.trials if t.label == CALIBRATION_LABEL and t.valid]
    if not cal:
        raise ValueError(f"{session.path.name}: no valid calibration trial")
    trial = cal[-1]
    feet = {}
    for side in SIDES:
        cols = foot_columns(model_input, side)
        rows = [[r[c] for c in cols] for r in trial.rows[side] if r["valid"] == 1]
        feet[side] = foot_baseline(rows)
    return model_baseline(feet["L"], feet["R"], model_input)


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
    lc = _load_capture()
    fixture = lc.load_session(ROOT / "shared" / "capture_fixture" / "schema2"
                              / "TEST-009_20261110-090000")
    base = session_baseline(fixture, mi)
    cal = [t for t in fixture.trials if t.label == CALIBRATION_LABEL][0]
    col = foot_columns(mi, "R")[1]
    want = median([r[col] for r in cal.rows["R"] if r["valid"] == 1])
    expect(len(base) == 28 and base[14 + 1] == want,
           "a session's baseline is its calibration trial's per-foot median")
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
    args = ap.parse_args(argv)
    if args.make_vectors:
        make_vectors()
        print(f"wrote {VECTORS.relative_to(ROOT)}")
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
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Compare a real board's BLE capture with DATA-CONTRACT v1.6 (Appendix C).

Reads one or more capture folders written by board_capture.py (offline: no
Bluetooth, no serial port) and checks every packet against the contract,
field by field. The parsers are firmware/simulator/tools/sim_check.py's,
imported unchanged; their --selftest is run first, so they are proven to
agree with shared/test_vectors/ (the vectors the app's Dart parser is tested
against, and that Appendix C's examples come from) before any capture is
judged.

    python3 tools/board_check/compare.py RUN_DIR [RUN_DIR ...] \\
        [--serial SERIAL_LOG] [--md OUT.md]

Prints the analysis and writes it as Markdown (default: analysis.md in the
first RUN_DIR). Device addresses are never printed.

Result per check: PASS, FAIL (the board does not do what the contract
says), INFO (recorded, no contract value to judge against), N/A.
Severity per finding: blocker (the app refuses the board or would show a
made-up reading), issue (the app accepts it but a feature misbehaves),
note.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import re
import statistics
import struct
import sys
from contextlib import redirect_stdout
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "firmware" / "simulator" / "tools"))
import sim_check as sc  # noqa: E402

VECTORS = REPO / "shared" / "test_vectors"
THRESHOLDS = json.loads((REPO / "shared" / "thresholds.json").read_text())
N_FSR = 8
SENSOR_BYTES = 8 + 8 * (2 * N_FSR + 12)  # 232
TEMP_BYTES = 32
STATUS_BYTES = 8
MIN_MTU = SENSOR_BYTES + 3  # 235
# The capture pre-check's battery floor lives in Dart, not thresholds.json.
CAPTURE_MIN_BATTERY = int(re.search(
    r"minBatteryPct\s*=\s*(\d+)",
    (REPO / "mobile" / "lib" / "capture" / "capture_protocol.dart").read_text()).group(1))
ERROR_CODES = {0: "none", 1: "IMU not responding", 2: "NTC unreadable",
               3: "ADC saturated (short circuit?)", 4: "battery critically low",
               5: "internal memory full"}
SITES = ["hallux", "MTH1", "MTH2-3", "MTH5", "lateral midfoot", "heel centre",
         "medial arch", "lateral heel"]


class Out:
    def __init__(self):
        self.lines: list[str] = []
        self.checks: list[tuple] = []
        self.findings: list[dict] = []

    def p(self, text: str = "") -> None:
        print(text)
        self.lines.append(text)

    def check(self, run: str, area: str, what: str, ref: str, result: str, observed: str):
        self.checks.append((run, area, what, ref, result, observed))

    def finding(self, severity: str, area: str, ref: str, expected: str, observed: str,
                app_effect: str):
        key = (area, expected)
        for f in self.findings:
            if (f["area"], f["expected"]) == key:
                if observed not in f["observed"]:
                    f["observed"] += f"; {observed}"
                return
        self.findings.append({"severity": severity, "area": area, "ref": ref,
                              "expected": expected, "observed": observed,
                              "app_effect": app_effect})


def load(run_dir: Path) -> list[dict]:
    return [json.loads(x) for x in (run_dir / "capture.jsonl").read_text().splitlines() if x]


def first(events, **match):
    for e in events:
        if all(e.get(k) == v for k, v in match.items()):
            return e
    return None


def hexs(b: bytes) -> str:
    return b.hex(" ")


# --- annotated dumps next to the Appendix C examples ------------------------


def sensor_fields():
    f = [(0, 2, "<H", "seq"), (2, 4, "<I", "t0_ms"), (6, 1, "<B", "count"), (7, 1, "<B", "flags")]
    for i in range(N_FSR):
        f.append((8 + 2 * i, 2, "<H", f"s0 fsr[{i}] {SITES[i]}"))
    for j, ax in enumerate("xyz"):
        f.append((24 + 2 * j, 2, "<h", f"s0 accel {ax}"))
    for j, ax in enumerate("xyz"):
        f.append((30 + 2 * j, 2, "<h", f"s0 gyro {ax}"))
    return f


def temp_fields():
    f = [(0, 2, "<H", "seq"), (2, 4, "<I", "t_ms"), (6, 1, "<B", "count"), (7, 1, "<B", "reserved")]
    for i in range(8):
        f.append((8 + 2 * i, 2, "<h", f"temp[{i}] {SITES[i]}"))
    for i in range(8):
        f.append((24 + i, 1, "<B", f"quality[{i}]"))
    return f


STATUS_FIELDS = [(0, 1, "<B", "battery_pct"), (1, 2, "<H", "battery_mv"), (3, 1, "<B", "foot_side"),
                 (4, 1, "<B", "fw_major"), (5, 1, "<B", "fw_minor"), (6, 1, "<B", "state"),
                 (7, 1, "<B", "error_code")]


def dump_side_by_side(o: Out, title: str, board: bytes, example: bytes, ex_name: str, fields):
    o.p(f"\n{title}")
    o.p(f"  example: shared/test_vectors {ex_name} (Appendix C)")
    o.p("  ```")
    o.p(f"  {'off':>4}  {'field':28s} {'board bytes':12s} {'board':>8s} | {'example':12s} {'example':>8s}")
    for off, size, fmt, name in fields:
        def val(b):
            if len(b) < off + size:
                return "--", "(missing)"
            return hexs(b[off:off + size]), str(struct.unpack_from(fmt, b, off)[0])
        bb, bv = val(board)
        eb, ev = val(example)
        o.p(f"  0x{off:02x}  {name:28s} {bb:12s} {bv:>8s} | {eb:12s} {ev:>8s}")
    if len(board) > max(off + size for off, size, _, _ in fields) and fields[0][3] == "seq" \
            and "s0 fsr[0] hallux" in [f[3] for f in fields]:
        o.p(f"  ... samples 1-7 follow at 0x24, 0x40, ... (28 bytes each); board total {len(board)} bytes")
    o.p("  ```")


# --- per-run analysis -------------------------------------------------------


def analyse(o: Out, run_dir: Path, run: str, prev_last_t0):
    ev = load(run_dir)
    meta = first(ev, kind="meta") or {}
    side = meta.get("side", "R")
    want_side = 0 if side == "L" else 1
    o.p(f"\n## {run} ({run_dir.name})")
    o.p(f"side {side}, START->STOP {meta.get('duration_s')} s, "
        f"SYNC_TIME before START: {meta.get('app_sequence')}")

    # Advertising
    conn = first(ev, kind="connecting")
    addr = conn["address"] if conn else None
    advs = [e for e in ev if e["kind"] == "adv" and e["address"] == addr]
    names = sorted({a.get("local_name") or a.get("name") or "" for a in advs})
    uuid_adv = any(sc.SERVICE in a["service_uuids"] for a in advs)
    want_name = f"SMARTINSOLE-{side}"
    o.check(run, "advertising", f"name {want_name}", "§2.1", "PASS" if want_name in names else "FAIL",
            ", ".join(repr(n) for n in names) or "no advert")
    if want_name not in names:
        o.finding("note", "advertising", "§2.1", f"name {want_name}", f"names {names}",
                  "none: the app picks the board by service UUID and judges the side by foot_side")
    o.check(run, "advertising", "service UUID in advertising", "§2.1", "PASS" if uuid_adv else "FAIL",
            "advertised" if uuid_adv else "not advertised")
    if not uuid_adv:
        o.finding("blocker", "advertising", "§2.1", "service UUID f0a5c000-...-b45900 in the advertising "
                  "data", "not advertised", "the app scans by service UUID and would never find the board")
    txp = sorted({a["tx_power"] for a in advs if a.get("tx_power") is not None})
    o.check(run, "advertising", "TX power 0 dBm", "§2.1", "INFO",
            f"advertised {txp} dBm" if txp else "not in the advertising data")
    o.check(run, "advertising", "interval 100 ms", "§2.1", "N/A", "not measurable from the laptop scan")
    rssi = [a["rssi"] for a in advs if a.get("rssi") is not None]
    if rssi:
        o.check(run, "advertising", "RSSI at the laptop", "-", "INFO", f"{min(rssi)}..{max(rssi)} dBm")

    connected = first(ev, kind="connected")
    if not connected:
        o.check(run, "connection", "connects", "§2", "FAIL", "no connection")
        return None
    mtu = connected["mtu"]
    o.check(run, "connection", f"MTU >= {MIN_MTU} (232-byte packet + 3)", "§2.3",
            "PASS" if mtu >= MIN_MTU else "FAIL", f"{mtu}")
    if mtu < MIN_MTU:
        o.finding("blocker", "connection", "§2.3", f"MTU >= {MIN_MTU}", f"MTU {mtu} on the laptop",
                  "full packets do not fit; the app needs the 4-sample fallback or shows MTU too small")

    # GATT
    gatt = first(ev, kind="gatt")
    ours = next((s for s in gatt["services"] if s["uuid"] == sc.SERVICE), None) if gatt else None
    o.check(run, "GATT", "service f0a5c000-...-b45900", "§2.2", "PASS" if ours else "FAIL",
            "present" if ours else "missing")
    have = {c["uuid"]: set(c["properties"]) for c in (ours or {}).get("characteristics", [])}
    need = {"sensor": (sc.SENSOR, {"notify"}), "temperature": (sc.TEMPERATURE, {"notify"}),
            "status": (sc.STATUS, {"read", "notify"}), "control": (sc.CONTROL, {"write"}),
            "calibration": (sc.CALIBRATION, {"read"})}
    for name, (uuid, props) in need.items():
        got = have.get(uuid)
        ok = got is not None and props <= got
        o.check(run, "GATT", f"{name} ...{uuid[-6:]}: {'+'.join(sorted(props))}", "§2.2",
                "PASS" if ok else "FAIL", "missing" if got is None else "+".join(sorted(got)))
        if not ok:
            effect = {"control": "the app writes START/STOP with response; without 'write' it cannot start "
                                 "the stream",
                      "status": "the app reads foot_side at connect (rule 8) and listens for state changes"
                      }.get(name, "the app cannot receive this data")
            o.finding("blocker", "GATT", "§2.2", f"{name} characteristic with {'+'.join(sorted(props))}",
                      "missing" if got is None else f"properties {'+'.join(sorted(got))}", effect)
    for e in ev:
        if e["kind"] == "read" and e.get("phase") == "dis":
            o.check(run, "GATT", f"Device Information: {e['char']}", "-", "INFO",
                    repr(bytes.fromhex(e["hex"]).decode("utf-8", "replace")))
    extra = [s["uuid"] for s in (gatt or {}).get("services", []) if s["uuid"] != sc.SERVICE]
    if extra:
        o.check(run, "GATT", "other services", "-", "INFO", ", ".join(u[:8] for u in extra))

    # Status
    status_reads = [(e["phase"], bytes.fromhex(e["hex"])) for e in ev
                    if e["kind"] == "read" and e["char"] == "status"]
    status_notes = [(e["t"], bytes.fromhex(e["hex"])) for e in ev
                    if e["kind"] == "notify" and e["char"] == "status"]
    first_status = None
    for label, b in status_reads + [("notify", b) for _, b in status_notes]:
        ok_len = len(b) == STATUS_BYTES
        o.check(run, "status", f"{label}: exactly 8 bytes", "§3.3", "PASS" if ok_len else "FAIL",
                f"{len(b)} bytes: {hexs(b)}")
        if not ok_len:
            o.finding("blocker", "status", "§3.3", "8-byte Device Status", f"{len(b)} bytes",
                      "tooShort / lengthMismatch: the app rejects it and cannot confirm the foot side")
            continue
        st = sc.parse_status(b)
        first_status = first_status or (label, b, st)
        o.check(run, "status", f"{label}: foot_side {want_side} ({side})", "§3.3",
                "PASS" if st["foot_side"] == want_side else "FAIL", str(st["foot_side"]))
        if st["foot_side"] != want_side:
            o.finding("blocker", "status", "§3.3", f"foot_side {want_side} on the {side} insole",
                      f"foot_side {st['foot_side']}",
                      "rule 8: the app refuses a board reporting the other side (or rejects values > 1)")
        o.check(run, "status", f"{label}: battery_pct 0-100 / battery_mv", "§3.3",
                "PASS" if st["battery_pct"] <= 100 else "FAIL",
                f"{st['battery_pct']} % / {st['battery_mv']} mV")
        o.check(run, "status", f"{label}: firmware", "§3.3", "INFO", f"{st['fw_major']}.{st['fw_minor']}")
        o.check(run, "status", f"{label}: state / error_code", "§3.3, App. A", "INFO",
                f"state {st['state']}, error {st['error_code']} ({ERROR_CODES.get(st['error_code'], '?')})")
        if st["state"] > 2:
            o.finding("blocker", "status", "§3.3", "state 0, 1 or 2", f"state {st['state']}",
                      "invalidState: the app rejects the status packet")
    if first_status:
        st = first_status[2]
        low = THRESHOLDS["battery"]["lowPct"]
        if st["battery_pct"] < CAPTURE_MIN_BATTERY:
            effect = (f"below the research capture pre-check ({CAPTURE_MIN_BATTERY} %, "
                      f"capture_protocol.dart): a capture session cannot start with this insole")
            if st["battery_pct"] < low:
                effect += f"; below battery.lowPct {low}: the app raises BATTERY_LOW"
            o.finding("issue", "status", "§3.3", "battery_pct a real charge level",
                      f"battery_pct {st['battery_pct']}, battery_mv {st['battery_mv']} "
                      f"(USB powered, no battery)", effect)
        if st["error_code"] != 0 or st["state"] == 2:
            o.finding("issue", "status", "§3.3, App. A", "state 0/1 and error_code 0 on a working board",
                      f"state {st['state']}, error_code {st['error_code']} "
                      f"({ERROR_CODES.get(st['error_code'], '?')})",
                      "the app does not act on it (no alert, no refusal); Researcher › Diagnostics shows "
                      "the error number")
    bs = dict((p, sc.parse_status(b)) for p, b in status_reads if len(b) == 8)
    if "before_start" in bs:
        s0 = bs["before_start"]["state"]
        o.check(run, "status", "state 0 (idle) before START", "§3.3", "PASS" if s0 == 0 else "FAIL", str(s0))
        if s0 != 0:
            o.finding("issue", "status", "§3.3", "state 0 before START_STREAM", f"state {s0}",
                      "Diagnostics and the connection screen show the wrong state")
    if "after_stop" in bs:
        s2 = bs["after_stop"]["state"]
        o.check(run, "status", "state 0 (idle) after STOP", "§3.3", "PASS" if s2 == 0 else "FAIL", str(s2))
        if s2 != 0:
            o.finding("issue", "status", "§3.3", "state 0 after STOP_STREAM", f"state {s2}",
                      "Diagnostics and the connection screen show the wrong state")
    streaming_states = [sc.parse_status(b)["state"] for _, b in status_notes if len(b) == 8]
    o.check(run, "status", "notifies state changes (1 after START, 0 after STOP)", "§2.2, §3.3",
            "PASS" if 1 in streaming_states and 0 in streaming_states else "FAIL",
            f"{len(status_notes)} notifications, states {streaming_states}")
    if not (1 in streaming_states and 0 in streaming_states):
        o.finding("issue", "status", "§2.2", "a status notification when the state changes "
                  "(1 after START, 0 after STOP)", f"states notified {streaming_states}",
                  "the app's live device state does not follow; streaming is still detected from the data")

    # Calibration
    cal_ev = first(ev, kind="read", char="calibration")
    cal = None
    if cal_ev:
        raw = bytes.fromhex(cal_ev["hex"])
        o.check(run, "calibration", "at most 512 bytes", "§2.2", "PASS" if len(raw) <= 512 else "FAIL",
                f"{len(raw)} bytes")
        if len(raw) > 512:
            o.finding("blocker", "calibration", "§2.2", "at most 512 bytes", f"{len(raw)} bytes",
                      "a GATT attribute is at most 512 bytes; the read is cut")
        try:
            cal = sc.parse_calibration(raw.decode("utf-8"))
            o.check(run, "calibration", "valid JSON, contract fields and types", "§5.1", "PASS",
                    f"device_id {cal['device_id']!r}")
        except (UnicodeDecodeError, ValueError, KeyError, TypeError) as e:
            o.check(run, "calibration", "valid JSON, contract fields and types", "§5.1", "FAIL", str(e))
            o.finding("blocker", "calibration", "§5.1", "the calibration JSON of §5.1", str(e),
                      "calibration rejected: the app refuses the insole, nothing streams")
        if cal:
            n = len(cal["channels"])
            o.check(run, "calibration", "exactly 8 channels, indexes 0-7", "§5.1, App. C item 4",
                    "PASS" if n == N_FSR else "FAIL", f"N = {n}")
            if n != N_FSR:
                o.finding("blocker", "calibration", "App. C item 4", "channels lists exactly 8 entries",
                          f"N = {n}", "calibrationFsrCount: the app refuses the insole, nothing streams")
            o.check(run, "calibration", "r_pulldown_ohm / sensor_area_m2", "§5.1", "INFO",
                    f"{cal['r_pulldown_ohm']} ohm / {cal['sensor_area_m2']} m2")
            for c in cal["channels"]:
                o.check(run, "calibration", f"channel {c['index']} a / b / offset_adc", "§5.1", "INFO",
                        f"{c['a']} / {c['b']} / {c['offset_adc']}")
            same = len({(c["a"], c["b"]) for c in cal["channels"]}) == 1
            if same and n > 1:
                o.finding("note", "calibration", "§5.1", "a, b fitted per sensor ('curve fitting รายชิ้น')",
                          f"all {n} channels share a = {cal['channels'][0]['a']}, "
                          f"b = {cal['channels'][0]['b']}",
                          "kPa uses one generic curve for every sensor: fine for format checks, "
                          "absolute kPa is not calibrated")
            extra_keys = sorted(set(json.loads(raw)) - {"device_id", "r_pulldown_ohm", "sensor_area_m2",
                                                        "channels"})
            if extra_keys:
                o.check(run, "calibration", "extra top-level keys", "§5.1", "INFO", ", ".join(extra_keys))
    else:
        o.check(run, "calibration", "readable", "§2.2", "FAIL", "not read")

    # Control writes
    writes = [e for e in ev if e["kind"] in ("write", "write_error")]
    marks = {}
    for e in writes:
        if e["kind"] == "write_error":
            o.check(run, "control", f"{e['label']} write accepted", "§3.4", "FAIL", e["error"])
            o.finding("blocker", "control", "§3.4", f"{e['label']} accepted (write with response)",
                      e["error"], "the app cannot drive the stream")
        else:
            marks[(e["label"], e["phase"])] = e["t"]
    for label in ("SYNC_TIME", "START_STREAM", "STOP_STREAM"):
        if (label, "acked") in marks:
            o.check(run, "control", f"{label} write acknowledged", "§3.4", "PASS",
                    f"{(marks[(label, 'acked')] - marks[(label, 'sent')]) * 1000:.0f} ms")
    t_pre = (first(ev, kind="mark", label="pre_start_window") or {}).get("t")
    t_start_sent = marks.get(("START_STREAM", "sent"))
    t_stop_sent = marks.get(("STOP_STREAM", "sent"))
    t_stop_ack = marks.get(("STOP_STREAM", "acked"), t_stop_sent)

    # Sensor stream
    sensor = [(e["t"], bytes.fromhex(e["hex"])) for e in ev if e["kind"] == "notify" and e["char"] == "sensor"]
    if t_start_sent is not None:
        before = [x for x in sensor if x[0] < t_start_sent]
        o.check(run, "sensor", "nothing before START_STREAM", "§3.4", "PASS" if not before else "FAIL",
                f"{len(before)} packets in the {t_start_sent - (t_pre or t_start_sent):.1f} s before")
        if before:
            o.finding("issue", "sensor", "§3.4", "no sensor packets before START_STREAM",
                      f"{len(before)} packets before START", "the app drops them (rule 9 check 1)")
    grace = 0.5
    during = [x for x in sensor if (t_start_sent is None or x[0] >= t_start_sent)
              and (t_stop_ack is None or x[0] <= t_stop_ack + grace)]
    after = [x for x in sensor if t_stop_ack is not None and x[0] > t_stop_ack + grace]
    o.check(run, "sensor", "stream stops after STOP_STREAM", "§3.4", "PASS" if not after else "FAIL",
            f"{len(after)} packets later than STOP + {grace} s")
    if after:
        o.finding("issue", "sensor", "§3.4", "no sensor packets after STOP_STREAM",
                  f"{len(after)} packets after STOP", "streaming continues after the app stops it")
    lens = {}
    for _, b in during:
        lens[len(b)] = lens.get(len(b), 0) + 1
    o.check(run, "sensor", f"every packet exactly {SENSOR_BYTES} bytes", "§3.1, App. C item 2",
            "PASS" if set(lens) == {SENSOR_BYTES} else ("FAIL" if during else "N/A"),
            f"{len(during)} packets, lengths {lens}" if during else "no packets")
    if not during:
        o.finding("blocker", "sensor", "§3.1", "sensor packets at 6.25 Hz after START_STREAM",
                  "no sensor packets", "nothing streams")
    bad = {k: v for k, v in lens.items() if k != SENSOR_BYTES}
    if bad:
        guess = []
        for _, b in during:
            if len(b) != SENSOR_BYTES and len(b) >= 8 and b[6]:
                per = (len(b) - 8) / b[6]
                guess.append(f"count {b[6]} -> {per:g} bytes/sample -> N = {(per - 12) / 2:g}")
                break
        o.finding("blocker", "sensor", "§3.1, App. C item 2", f"{SENSOR_BYTES}-byte packets (N = 8, 8 samples)",
                  f"lengths {bad}{' (' + guess[0] + ')' if guess else ''}",
                  "lengthMismatch / truncated: the app drops every such packet")
    # The stream is judged at the contract's N = 8. If the calibration says
    # otherwise the app parses with that N (and refuses the insole first).
    n_cal = len(cal["channels"]) if cal else N_FSR
    if n_cal != N_FSR and during:
        r_cal = {}
        for _, b in during:
            try:
                sc.parse_sensor(b, n_cal)
            except sc.Reject as e:
                r_cal[e.reason] = r_cal.get(e.reason, 0) + 1
        o.check(run, "sensor", f"parses with the calibration's N = {n_cal} (as the app would)", "§5.1",
                "FAIL" if r_cal else "INFO", f"rejects {r_cal or 0}")
    n_parse = N_FSR
    pkts, rejects = [], {}
    for t, b in during:
        try:
            pkts.append((t, sc.parse_sensor(b, n_parse)))
        except sc.Reject as e:
            rejects[e.reason] = rejects.get(e.reason, 0) + 1
    o.check(run, "sensor", f"parses (strict, N = {n_parse})", "§3.1", "PASS" if not rejects and pkts else
            ("FAIL" if during else "N/A"), f"{len(pkts)} parsed, rejects {rejects or 0}")
    last_t0 = prev_last_t0
    if pkts:
        P = [p for _, p in pkts]
        counts = sorted({p["count"] for p in P})
        o.check(run, "sensor", "count = 8 in every packet", "§3.1", "PASS" if counts == [8] else "FAIL",
                str(counts))
        if counts != [8]:
            o.finding("issue", "sensor", "§3.1", "count 8", f"counts {counts}",
                      "the app accepts other counts if the length matches, but the rate is wrong")
        o.check(run, "sensor", "first seq after START is 0", "§3.1, BACKLOG 19",
                "PASS" if P[0]["seq"] == 0 else "FAIL", str(P[0]["seq"]))
        if P[0]["seq"] != 0:
            o.finding("issue", "sensor", "§3.1, BACKLOG 19", "seq restarts at 0 on every START_STREAM",
                      f"first seq {P[0]['seq']}",
                      "Diagnostics counts packets 'missing at start'; the gap counter is off")
        gaps = [(a["seq"], b["seq"]) for a, b in zip(P, P[1:]) if (a["seq"] + 1) & 0xFFFF != b["seq"]]
        o.check(run, "sensor", "seq +1 each packet, no gaps", "§3.1", "PASS" if not gaps else "FAIL",
                f"{len(gaps)} gaps {gaps[:5]}")
        if gaps:
            o.finding("issue", "sensor", "§3.1", "seq increments by 1", f"{len(gaps)} gaps, e.g. {gaps[:3]}",
                      "lost packets are counted as missing and marked in captures")
        steps = {}
        for a, b in zip(P, P[1:]):
            d = (b["t0_ms"] - a["t0_ms"]) & 0xFFFFFFFF
            steps[d] = steps.get(d, 0) + 1
        o.check(run, "sensor", "t0_ms step 160 ms (8 samples x 20 ms)", "§3.1",
                "PASS" if set(steps) == {160} else "FAIL", str(dict(sorted(steps.items()))))
        if set(steps) != {160}:
            o.finding("blocker", "sensor", "§3.1", "t0_ms advances 160 ms per packet (20 ms per sample)",
                      f"t0 steps {dict(sorted(steps.items()))}",
                      "rule 1: the app times samples t0 + i x 20 ms; other spacing puts samples at the "
                      "wrong times (and the DeviceClock flags jumps)")
        o.check(run, "sensor", "t0_ms (ms since boot) at first packet", "§3.1", "INFO",
                f"{P[0]['t0_ms']} ms = {P[0]['t0_ms'] / 1000:.1f} s since boot")
        if prev_last_t0 is not None:
            o.check(run, "sensor", "t0 continues from the previous run (not reset per connection)",
                    "§3.1, BACKLOG 19", "PASS" if P[0]["t0_ms"] > prev_last_t0 else "INFO",
                    f"{prev_last_t0} -> {P[0]['t0_ms']}")
        last_t0 = P[-1]["t0_ms"]
        ts = [t for t, _ in pkts]
        span = ts[-1] - ts[0]
        rate = (len(ts) - 1) / span if span > 0 else 0
        o.check(run, "sensor", "packet rate 6.25 Hz (+-2 %)", "§2.2",
                "PASS" if abs(rate - 6.25) / 6.25 < 0.02 else "FAIL", f"{rate:.3f} Hz over {span:.1f} s")
        if abs(rate - 6.25) / 6.25 >= 0.02:
            o.finding("blocker", "sensor", "§2.2", "6.25 packets/s (50 Hz samples)", f"{rate:.3f} packets/s",
                      "the sample rate is not 50 Hz; captures and every timing rule assume it")
        dev_span = (P[-1]["t0_ms"] - P[0]["t0_ms"]) / 1000
        if span > 5:
            o.check(run, "sensor", "device clock vs laptop clock", "§4", "INFO",
                    f"{(dev_span / span - 1) * 1e6:+.0f} ppm over {span:.0f} s")
        gaps_s = [b - a for a, b in zip(ts, ts[1:])]
        o.check(run, "sensor", "arrival interval (laptop)", "-", "INFO",
                f"median {statistics.median(gaps_s) * 1000:.0f} ms, max {max(gaps_s) * 1000:.0f} ms")
        if t_start_sent is not None:
            o.check(run, "sensor", "first packet after START write", "-", "INFO",
                    f"{(ts[0] - t_start_sent) * 1000:.0f} ms")
        flags = {}
        for p in P:
            flags[p["flags"]] = flags.get(p["flags"], 0) + 1
        o.check(run, "sensor", "flags", "§3.1", "PASS" if set(flags) <= {0} else "INFO",
                ", ".join(f"0x{k:02x} x{v}" for k, v in sorted(flags.items())))
        if any(k & ~0x03 for k in flags):
            o.finding("note", "sensor", "§3.1", "flags bits 2-7 zero", f"flags {sorted(flags)}",
                      "the app ignores bits 2-7")
        if any(k & 0x02 for k in flags):
            o.finding("issue", "sensor", "§3.1", "flags bit1 (calibrating) only during a TARE",
                      f"{sum(v for k, v in flags.items() if k & 2)} packets flagged calibrating, no TARE sent",
                      "baseline recordings refuse calibrating samples; captures mark them")
        S = [s for p in P for s in p["samples"]]
        o.p(f"\n{run}: FSR raw ADC per channel over {len(S)} samples (min / median / max):")
        for i in range(n_parse):
            col = [s["fsr_adc"][i] for s in S]
            o.p(f"  ch {i} {SITES[i] if i < 8 else '':16s} {min(col):5d} / {int(statistics.median(col)):5d}"
                f" / {max(col):5d}")
        mx = max(a for s in S for a in s["fsr_adc"])
        o.check(run, "sensor", "FSR raw ADC 0-4095 (12-bit)", "§3.1", "PASS" if mx <= 4095 else "FAIL",
                f"max {mx}")
        if mx > 4095:
            o.finding("blocker", "sensor", "§3.1", "raw 12-bit ADC 0-4095", f"max {mx}",
                      "values above 4095 are not raw ADC: kPa is wrong")
        # Which channels respond, in time order (for a press test, channel order §3.1).
        active = []
        for i in range(n_parse):
            col = [s["fsr_adc"][i] for s in S]
            med = statistics.median(col)
            thr = med + 300
            idx = next((k for k, v in enumerate(col) if v > thr), None)
            if idx is not None:
                n_on = sum(v > thr for v in col)
                active.append((idx, i, n_on))
        if active:
            o.check(run, "sensor", "channels pressed, in time order (> median + 300 ADC)", "§3.1", "INFO",
                    ", ".join(f"ch {i} ({SITES[i] if i < 8 else '?'}) at {S[idx]['t_ms'] - S[0]['t_ms']} ms "
                              f"for {n_on * 20} ms" for idx, i, n_on in sorted(active)))
        else:
            o.check(run, "sensor", "channels pressed", "§3.1", "INFO", "no channel rose 300 ADC above its median")
        acc = [s["accel_raw"] for s in S]
        gyr = [s["gyro_raw"] for s in S]
        rng = lambda rows, j: (min(r[j] for r in rows), max(r[j] for r in rows))
        o.check(run, "sensor", "accel raw x/y/z min..max", "§3.1", "INFO",
                " / ".join(f"{a}..{b}" for a, b in (rng(acc, j) for j in range(3))))
        o.check(run, "sensor", "gyro raw x/y/z min..max", "§3.1", "INFO",
                " / ".join(f"{a}..{b}" for a, b in (rng(gyr, j) for j in range(3))))
        g = [math.sqrt(sum(v * v for v in a)) / 4096 for a in acc]
        win = THRESHOLDS["motion"]["walkingWindowMs"] // 20
        thr_g = THRESHOLDS["motion"]["walkingAccelG"]
        stats = [statistics.fmean(abs(x - 1) for x in g[k:k + win]) for k in range(0, len(g) - win + 1, win)]
        if stats:
            on = sum(s > thr_g for s in stats)
            o.check(run, "sensor", f"walking-gate statistic (mean |a| - 1 g| over {win * 20} ms)", "§8.3.2",
                    "INFO", f"{min(stats):.3f}..{max(stats):.3f} g; above {thr_g} g in {on}/{len(stats)} "
                    f"windows while the board lay still")
            constant = len({tuple(a) for a in acc}) == 1 and len({tuple(r) for r in gyr}) == 1
            what = (f"accel {acc[0]} and gyro {gyr[0]} raw in every sample (no IMU fitted)" if constant
                    else f"|a| {min(g):.3f}..{max(g):.3f} g at rest")
            if on == len(stats):
                o.finding("issue", "sensor", "§3.1, §8.3.2",
                          "accel about 1 g (4096 LSB) at rest; an IMU is part of the v1.6 board (§1)",
                          f"{what}; gate statistic {min(stats):.2f} g",
                          "the walking gate reads 'walking' all the time: the 30 s baseline is refused as "
                          "'moved' (so Model A is not used) and PRESSURE_PEAK's gate is always open; the "
                          "IMU model channels carry no information")
            elif constant:
                o.finding("issue", "sensor", "§3.1, §8.3.2",
                          "real accel and gyro readings; an IMU is part of the v1.6 board (§1)", what,
                          "the walking gate never opens: PRESSURE_PEAK (walking only) can never fire; the "
                          "IMU model channels carry no information")
    # Temperature
    temp = [(e["t"], bytes.fromhex(e["hex"])) for e in ev if e["kind"] == "notify" and e["char"] == "temperature"]
    tdur = [x for x in temp if (t_start_sent is None or x[0] >= t_start_sent)
            and (t_stop_ack is None or x[0] <= t_stop_ack + grace)]
    tafter = [x for x in temp if t_stop_ack is not None and x[0] > t_stop_ack + grace]
    tbefore = [x for x in temp if t_start_sent is not None and x[0] < t_start_sent]
    dur_s = (t_stop_sent - t_start_sent) if t_start_sent and t_stop_sent else 0
    o.check(run, "temperature", "packets during the stream (every 30 s)", "§2.2, §3.2",
            "PASS" if tdur else "FAIL", f"{len(tdur)} in {dur_s:.0f} s"
            + (f"; {len(tbefore)} before START, {len(tafter)} after STOP" if tbefore or tafter else ""))
    if not tdur:
        o.finding("issue", "temperature", "§3.2, App. C item 3",
                  "a 32-byte temperature v2 packet every 30 s; with no NTC fitted, temp -32768 and quality 2 "
                  "per site", f"no temperature packet in {dur_s:.0f} s",
                  "the app shows no temperature (no ΔT, no TEMP_DELTA); Diagnostics never shows "
                  "'temperature v2, 8 sites'")
    tl = {}
    for _, b in tdur:
        tl[len(b)] = tl.get(len(b), 0) + 1
    if tdur:
        o.check(run, "temperature", "exactly 32 bytes", "§3.2, App. C item 3",
                "PASS" if set(tl) == {TEMP_BYTES} else "FAIL", str(tl))
        if set(tl) != {TEMP_BYTES}:
            o.finding("blocker", "temperature", "§3.2", "32-byte temperature v2", f"lengths {tl}"
                      + (" (12 = the old v1.5 packet)" if 12 in tl else ""),
                      "tempLength: the app drops every packet")
    T, trej = [], {}
    for t, b in tdur:
        try:
            T.append((t, sc.parse_temperature(b), b))
        except sc.Reject as e:
            trej[e.reason] = trej.get(e.reason, 0) + 1
    if tdur:
        o.check(run, "temperature", "parses (count 8, quality 0-2)", "§3.2", "PASS" if not trej else "FAIL",
                f"{len(T)} parsed, rejects {trej or 0}")
        for reason in trej:
            o.finding("blocker", "temperature", "§3.2", "count 8 and quality 0-2", reason,
                      f"{reason}: the app drops the packet")
    for t, p, b in T:
        o.check(run, "temperature", f"seq {p['seq']} t_ms {p['t_ms']}: reserved byte", "§3.2",
                "PASS" if b[7] == 0 else "INFO", f"0x{b[7]:02x}")
        o.check(run, "temperature", f"seq {p['seq']}: °C per site / quality", "§3.2", "INFO",
                f"{p['celsius']} / {p['quality']}")
        made_up = [i for i, (c, q) in enumerate(zip(p["celsius"], p["quality"])) if c is not None and q == 0]
        if made_up:
            o.finding("blocker", "temperature", "§3.2",
                      "a site with no NTC sends -32768 (could not read), quality 2",
                      f"sites {made_up} send numbers with quality 0, e.g. "
                      f"{[p['celsius'][i] for i in made_up[:3]]} °C",
                      "the app shows these as real skin temperatures and computes ΔT from them: a "
                      "fabricated reading")
        elif any(c is not None for c in p["celsius"]):
            o.finding("issue", "temperature", "§3.2", "a site with no NTC sends -32768",
                      "numbers with quality 1/2", "the app shows the number with a quality warning")
    if len(T) >= 2:
        dts = sorted({b["t_ms"] - a["t_ms"] for (_, a, _), (_, b, _) in zip(T, T[1:])})
        arr = [round(b - a, 1) for (a, _, _), (b, _, _) in zip(T, T[1:])]
        o.check(run, "temperature", "t_ms step 30000 ms", "§2.2", "PASS" if dts == [30000] else "FAIL",
                f"device {dts} ms, arrival {arr} s")
        if dts != [30000]:
            o.finding("issue", "temperature", "§2.2", "one temperature packet every 30 s", f"steps {dts} ms",
                      "TEMP_DELTA needs 2 consecutive reading pairs; other periods change its timing")
    if T and t_start_sent is not None:
        o.check(run, "temperature", "first packet after START", "-", "INFO",
                f"{T[0][0] - t_start_sent:.1f} s; seq {[p['seq'] for _, p, _ in T]}")
    if tafter:
        o.finding("note", "temperature", "§3.4", "no temperature packets after STOP_STREAM",
                  f"{len(tafter)} after STOP", "the app ignores them while stopped")

    # Annotated dumps
    vec = lambda f, name: bytes.fromhex(next(c for c in json.loads((VECTORS / f).read_text())["cases"]
                                             if c["name"] == name)["hex"])
    if during:
        dump_side_by_side(o, f"{run}: first sensor packet after START, header + sample 0",
                          during[0][1], vec("sensor_n8.json", "n8_8_samples"), "sensor_n8.json n8_8_samples",
                          sensor_fields())
    if tdur:
        ex = "unreadable_all" if all(c is None for c in (T[0][1]["celsius"] if T else [None])) else "quality_mixed"
        dump_side_by_side(o, f"{run}: first temperature packet", tdur[0][1],
                          vec("temperature_v2.json", ex), f"temperature_v2.json {ex}", temp_fields())
    if first_status:
        dump_side_by_side(o, f"{run}: status ({first_status[0]})", first_status[1],
                          vec("status.json", "right_streaming"), "status.json right_streaming", STATUS_FIELDS)
    return last_t0


def serial_summary(o: Out, path: Path):
    o.p(f"\n## Serial log ({path.name})")
    lines = path.read_text(errors="replace").splitlines()
    o.p(f"{len(lines)} lines")
    pat = re.compile(r"error|fail|panic|guru|assert|abort|brownout|watchdog|wdt|rst:|E \(\d+\)|"
                     r"version|firmware|fw|boot", re.I)
    hits = [ln for ln in lines if pat.search(ln)]
    o.p(f"{len(hits)} lines mention boot / version / error words:")
    o.p("```")
    for ln in hits[:80]:
        o.p(ln)
    o.p("```")


def render_tables(o: Out) -> list[str]:
    md = ["\n## Checks", "", "| Run | Area | Check | Contract | Result | Observed |",
          "|---|---|---|---|---|---|"]
    for run, area, what, ref, res, obs in o.checks:
        md.append(f"| {run} | {area} | {what} | {ref} | {res} | {obs.replace('|', '/')} |")
    md += ["", "## Mismatches for the hardware team", "",
           "| # | Severity | Area | Contract | Expected | Observed | Effect in the app |",
           "|---|---|---|---|---|---|---|"]
    order = {"blocker": 0, "issue": 1, "note": 2}
    for k, f in enumerate(sorted(o.findings, key=lambda f: order[f["severity"]]), 1):
        md.append(f"| {k} | {f['severity']} | {f['area']} | {f['ref']} | {f['expected']} | "
                  f"{f['observed']} | {f['app_effect']} |")
    if not o.findings:
        md.append("| - | - | - | - | none | - | - |")
    return md


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("runs", nargs="+", type=Path)
    ap.add_argument("--serial", type=Path)
    ap.add_argument("--md", type=Path)
    args = ap.parse_args()

    o = Out()
    buf = io.StringIO()
    with redirect_stdout(buf):
        ok = sc.selftest()
    o.p("# Board capture vs DATA-CONTRACT v1.6")
    o.p(f"parsers: sim_check.py {buf.getvalue().strip()}")
    if not ok:
        print(buf.getvalue())
        return 1
    last_t0 = None
    for k, run_dir in enumerate(args.runs, 1):
        last_t0 = analyse(o, run_dir.expanduser(), f"run {k}", last_t0)
    if args.serial:
        serial_summary(o, args.serial.expanduser())
    tables = render_tables(o)
    for ln in tables:
        print(ln)
    md_path = args.md or (args.runs[0].expanduser() / "analysis.md")
    if REPO in md_path.resolve().parents:
        print(f"not writing {md_path}: inside the repo", file=sys.stderr)
        return 2
    md_path.write_text("\n".join(o.lines + tables) + "\n", encoding="utf-8")
    print(f"\nwritten {md_path}")
    blockers = sum(f["severity"] == "blocker" for f in o.findings)
    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())

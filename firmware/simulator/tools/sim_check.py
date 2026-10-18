#!/usr/bin/env python3
"""Live check of the SmartInsole simulator over BLE, from a laptop (bleak).

Runs the app's connect sequence (docs/FLUTTER-PLAN.md section 5, minus
SYNC_TIME, which is S2C), streams for --duration seconds, then sends
STOP_STREAM and checks that the stream ends. Then it reconnects
--reconnects times and checks that each new connection gets nothing before
its START_STREAM, starts at seq 0, and that t0 keeps counting from boot. It
exits non-zero if any check fails.

Before going live, the script's own parsers are checked against
shared/test_vectors/ (the same vectors the Flutter parser and the
simulator's encoders are tested against), so a pass here means the bytes
on the air match the contract, not just this script's reading of it.

    tools/.venv/bin/python tools/sim_check.py --selftest
    tools/.venv/bin/python tools/sim_check.py --side L --duration 600
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

SERVICE = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900"
SENSOR = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45901"
TEMPERATURE = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45902"
STATUS = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45903"
CONTROL = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45904"
CALIBRATION = "f0a5c000-9b4d-4e8a-a3c1-72d6e1b45905"

START_STREAM = b"\x01"
STOP_STREAM = b"\x02"

SAMPLE_PERIOD_MS = 20
SAMPLES_PER_PACKET = 8
PACKET_RATE_HZ = 1000 / (SAMPLE_PERIOD_MS * SAMPLES_PER_PACKET)  # 6.25
TEMP_PERIOD_MS = 30000
BATTERY_FLOOR_PCT = 50  # the simulator never goes below this

VECTORS = Path(__file__).resolve().parents[3] / "shared" / "test_vectors"


class Reject(Exception):
    """Mirrors the Dart parser's RejectReason for length problems."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


# --- parsers (strict, like mobile/lib/ble/packet_parser.dart) -------------


def sample_size(n: int) -> int:
    return 2 * n + 12


def parse_sensor(b: bytes, n: int) -> dict:
    if len(b) < 8:
        raise Reject("tooShort")
    seq, t0, count, flags = struct.unpack_from("<HIBB", b, 0)
    want = 8 + count * sample_size(n)
    if len(b) < want:
        raise Reject("truncated")
    if len(b) > want:
        raise Reject("lengthMismatch")
    samples = []
    off = 8
    for i in range(count):
        fsr = list(struct.unpack_from(f"<{n}H", b, off))
        off += 2 * n
        imu = struct.unpack_from("<6h", b, off)
        off += 12
        samples.append({"t_ms": t0 + i * SAMPLE_PERIOD_MS, "fsr_adc": fsr,
                        "accel_raw": list(imu[:3]), "gyro_raw": list(imu[3:])})
    return {"seq": seq, "t0_ms": t0, "count": count, "flags": flags,
            "saturated": bool(flags & 1), "calibrating": bool(flags & 2),
            "samples": samples}


def parse_temperature(b: bytes) -> dict:
    if len(b) < 12:
        raise Reject("tooShort")
    if len(b) > 12:
        raise Reject("lengthMismatch")
    seq, t, fore, heel, quality, _ = struct.unpack("<HIhhBB", b)
    c = lambda v: None if v == -32768 else v / 100
    return {"seq": seq, "t_ms": t, "forefoot_c": c(fore), "heel_c": c(heel), "quality": quality}


def parse_status(b: bytes) -> dict:
    if len(b) < 8:
        raise Reject("tooShort")
    if len(b) > 8:
        raise Reject("lengthMismatch")
    pct, mv, side, major, minor, state, err = struct.unpack("<BHBBBBB", b)
    return {"battery_pct": pct, "battery_mv": mv, "foot_side": side, "fw_major": major,
            "fw_minor": minor, "state": state, "error_code": err}


def parse_calibration(text: str) -> dict:
    cal = json.loads(text)
    num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
    if not isinstance(cal, dict):
        raise ValueError("calibration is not a JSON object")
    if not isinstance(cal.get("device_id"), str):
        raise ValueError("device_id must be a string")
    if not num(cal.get("r_pulldown_ohm")) or not num(cal.get("sensor_area_m2")):
        raise ValueError("r_pulldown_ohm and sensor_area_m2 must be numbers")
    ch = cal.get("channels")
    if not isinstance(ch, list) or not all(isinstance(c, dict) for c in ch):
        raise ValueError("channels must be an array of objects")
    for c in ch:
        if not isinstance(c.get("index"), int) or isinstance(c.get("index"), bool):
            raise ValueError("channel index must be an integer")
        if not all(num(c.get(k)) for k in ("a", "b", "offset_adc")):
            raise ValueError("channel a, b, offset_adc must be numbers")
    idx = [c["index"] for c in ch]
    if sorted(idx) != list(range(len(ch))):
        raise ValueError(f"channel indexes must be 0..{len(ch) - 1}, got {idx}")
    if cal["r_pulldown_ohm"] <= 0 or cal["sensor_area_m2"] <= 0:
        raise ValueError("r_pulldown_ohm and sensor_area_m2 must be > 0")
    cal["channels"] = sorted(ch, key=lambda c: c["index"])
    return cal


def adc_to_kpa(adc: int, ch: dict, cal: dict) -> float:
    """Contract section 5.1, same operation order as the TS/Dart parsers."""
    corrected = max(0, adc - ch["offset_adc"])
    v = max(corrected, 1) / 4095 * 3.3
    r = max(cal["r_pulldown_ohm"] * (3.3 - v) / v, 1e-6)
    return ch["a"] * r ** ch["b"] / cal["sensor_area_m2"] / 1000


# --- self-test against shared/test_vectors -----------------------------------


def selftest() -> bool:
    ok = True
    checked = 0

    def fail(file, name, msg):
        nonlocal ok
        ok = False
        print(f"  FAIL {file}:{name}: {msg}")

    for file in ("sensor.json", "sensor_n4.json", "sensor_n8.json"):
        for c in json.loads((VECTORS / file).read_text())["cases"]:
            exp = c["expected"]
            want = c.get("dart_rejected") or exp["rejected"]
            try:
                got = parse_sensor(bytes.fromhex(c["hex"]), c["fsr_count"])
            except Reject as e:
                if e.reason != want:
                    fail(file, c["name"], f"rejected {e.reason}, expected {want}")
                checked += 1
                continue
            if want:
                fail(file, c["name"], f"parsed, expected {want}")
                continue
            h = exp["header"]
            for k in ("seq", "t0_ms", "count", "saturated", "calibrating"):
                if got[k] != h[k]:
                    fail(file, c["name"], f"{k} {got[k]} != {h[k]}")
            for gs, es in zip(got["samples"], exp["samples"]):
                for k in ("t_ms", "fsr_adc", "accel_raw", "gyro_raw"):
                    if gs[k] != es[k]:
                        fail(file, c["name"], f"{k} {gs[k]} != {es[k]}")
            cal = parse_calibration(json.dumps(json.loads((VECTORS / file).read_text())
                                               ["calibrations"][c["calibration"]]))
            for gs, es in zip(got["samples"], exp["samples"]):
                for i, adc in enumerate(gs["fsr_adc"]):
                    k = adc_to_kpa(adc, cal["channels"][i], cal)
                    if not math.isclose(k, es["kpa"][i], rel_tol=1e-9, abs_tol=1e-9):
                        fail(file, c["name"], f"kpa[{i}] {k} != {es['kpa'][i]}")
            checked += 1

    for file, parse in (("temperature.json", parse_temperature), ("status.json", parse_status)):
        for c in json.loads((VECTORS / file).read_text())["cases"]:
            exp = dict(c["expected"])
            want = exp.pop("rejected")
            try:
                got = parse(bytes.fromhex(c["hex"]))
            except Reject as e:
                if e.reason != want:
                    fail(file, c["name"], f"rejected {e.reason}, expected {want}")
                checked += 1
                continue
            if want:
                fail(file, c["name"], f"parsed, expected {want}")
                continue
            for k, v in exp.items():
                if got[k] != v:
                    fail(file, c["name"], f"{k} {got[k]} != {v}")
            checked += 1

    for c in json.loads((VECTORS / "calibration.json").read_text())["cases"]:
        try:
            parse_calibration(c["text"])
            if c["expected"].get("rejected"):
                fail("calibration.json", c["name"], "accepted a malformed blob")
        except (ValueError, KeyError, TypeError) as e:
            if not c["expected"].get("rejected"):
                fail("calibration.json", c["name"], f"rejected a valid blob: {e}")
        checked += 1

    print(f"selftest: {checked} vector cases, {'PASS' if ok else 'FAIL'}")
    return ok


# --- live run -------------------------------------------------------------


@dataclass
class Run:
    n: int = 6
    sensor: list = field(default_factory=list)  # (arrival_s, raw)
    temp: list = field(default_factory=list)
    status: list = field(default_factory=list)
    start_at: float = 0.0
    stop_at: float = 0.0


class Checks:
    def __init__(self):
        self.failed = 0

    def check(self, ok: bool, what: str, detail: str = ""):
        if not ok:
            self.failed += 1
        print(f"  [{'PASS' if ok else 'FAIL'}] {what}{(' - ' + detail) if detail else ''}")


async def live(args) -> bool:
    from bleak import BleakClient, BleakScanner

    want_side = 0 if args.side == "L" else 1
    want_name = f"SMARTINSOLE-{args.side}"
    c = Checks()
    run = Run()

    print(f"scanning for service {SERVICE} ...")
    found = {}

    def on_adv(dev, adv):
        if SERVICE in [u.lower() for u in adv.service_uuids]:
            found.setdefault(dev.address, (dev, adv))

    async with BleakScanner(on_adv, service_uuids=[SERVICE]):
        t_end = time.monotonic() + args.scan_timeout
        while time.monotonic() < t_end:
            if any((a.local_name or d.name) == want_name for d, a in found.values()):
                break
            await asyncio.sleep(0.2)
    names = {addr: (a.local_name or d.name) for addr, (d, a) in found.items()}
    print(f"  found by service UUID: {names or 'nothing'}")
    c.check(bool(found), "advertises the service UUID")
    if not found:
        return False
    # The OS can cache a device's name (contract section 2.1): BlueZ keeps
    # showing the old name after the same board is reflashed as the other
    # foot. So the name only picks among several candidates and is reported;
    # status foot_side below is the real check, as in the app.
    match = [found[a][0] for a, nm in names.items() if nm == want_name]
    dev = match[0] if match else next(iter(found.values()))[0]
    if not match:
        print(f"  note: no device named {want_name} (cached name?); using {dev.address}, "
              f"foot_side decides")

    async with BleakClient(dev) as client:
        # On BlueZ, bleak reports 23 until the negotiated MTU is fetched.
        acquire = getattr(getattr(client, "_backend", None), "_acquire_mtu", None)
        if acquire:
            await acquire()
        mtu = client.mtu_size
        print(f"connected to {dev.address}, mtu {mtu}")
        c.check(mtu >= 203, "MTU fits an 8-sample packet", f"mtu {mtu}")

        st = parse_status(bytes(await client.read_gatt_char(STATUS)))
        print(f"  status: {st}")
        c.check(st["foot_side"] == want_side, "status foot_side matches", str(st["foot_side"]))
        c.check(st["state"] == 0, "idle before START_STREAM", f"state {st['state']}")

        raw_cal = bytes(await client.read_gatt_char(CALIBRATION))
        cal = parse_calibration(raw_cal.decode("utf-8"))
        run.n = len(cal["channels"])
        print(f"  calibration: {len(raw_cal)} bytes, device_id {cal['device_id']}, N = {run.n}")
        c.check(len(raw_cal) > mtu - 3, "calibration read longer than one ATT payload (long read)",
                f"{len(raw_cal)} bytes")
        c.check(run.n == args.fsr_count, "calibration channel count", f"N = {run.n}")

        now = time.monotonic
        await client.start_notify(STATUS, lambda _, d: run.status.append((now(), bytes(d))))
        await client.start_notify(TEMPERATURE, lambda _, d: run.temp.append((now(), bytes(d))))
        await client.start_notify(SENSOR, lambda _, d: run.sensor.append((now(), bytes(d))))

        await asyncio.sleep(1.0)
        c.check(not run.sensor and not run.temp, "nothing streams before START_STREAM",
                f"{len(run.sensor)} sensor, {len(run.temp)} temp")

        run.start_at = now()
        await client.write_gatt_char(CONTROL, START_STREAM, response=True)
        print(f"START_STREAM sent; streaming {args.duration} s ...")
        end = run.start_at + args.duration
        while now() < end:
            await asyncio.sleep(min(30, end - now()))
            print(f"  t+{now() - run.start_at:5.0f} s: {len(run.sensor)} sensor, "
                  f"{len(run.temp)} temp, {len(run.status)} status packets")

        run.stop_at = now()
        await client.write_gatt_char(CONTROL, STOP_STREAM, response=True)
        await asyncio.sleep(2.0)
        st_after = parse_status(bytes(await client.read_gatt_char(STATUS)))

    evaluate(run, cal, st_after, c)
    last_t0 = None
    for _, b in reversed(run.sensor):
        try:
            last_t0 = parse_sensor(b, run.n)["t0_ms"]
            break
        except Reject:
            pass
    for i in range(args.reconnects):
        last_t0 = await reconnect_check(dev, run.n, last_t0, i + 1, c)
    print(f"\n{'PASS' if c.failed == 0 else 'FAIL'}: {c.failed} check(s) failed")
    return c.failed == 0


async def reconnect_check(dev, n: int, prev_t0, cycle: int, c: Checks):
    """Rule 9 groundwork: after a disconnect, the next connection gets
    nothing before its own START_STREAM, its seq starts again at 0, and t0
    (ms since boot) keeps going forward instead of restarting."""
    from bleak import BleakClient

    print(f"\nreconnect {cycle}: disconnected, connecting again ...")
    await asyncio.sleep(1.0)
    got = []
    async with BleakClient(dev) as client:
        await client.start_notify(SENSOR, lambda _, d: got.append(bytes(d)))
        await client.start_notify(TEMPERATURE, lambda _, d: got.append(bytes(d)))
        await asyncio.sleep(1.0)
        before = len(got)
        await client.write_gatt_char(CONTROL, START_STREAM, response=True)
        await asyncio.sleep(3.0)
        await client.write_gatt_char(CONTROL, STOP_STREAM, response=True)
        await asyncio.sleep(0.5)
    c.check(before == 0, f"reconnect {cycle}: nothing before START_STREAM", f"{before} packets")
    pkts = []
    for b in got[before:]:
        if len(b) == 12:
            continue  # temperature
        try:
            pkts.append(parse_sensor(b, n))
        except Reject as e:
            c.check(False, f"reconnect {cycle}: sensor packet parses", e.reason)
    if not pkts:
        c.check(False, f"reconnect {cycle}: received sensor packets")
        return prev_t0
    c.check(pkts[0]["seq"] == 0, f"reconnect {cycle}: first seq is 0", str(pkts[0]["seq"]))
    c.check(prev_t0 is None or pkts[0]["t0_ms"] > prev_t0,
            f"reconnect {cycle}: t0 continues from the last connection (ms since boot)",
            f"{prev_t0} -> {pkts[0]['t0_ms']}")
    gaps = [(a["seq"], b["seq"]) for a, b in zip(pkts, pkts[1:]) if (a["seq"] + 1) & 0xFFFF != b["seq"]]
    c.check(not gaps, f"reconnect {cycle}: no seq gaps", f"{len(pkts)} packets, gaps {gaps[:3]}")
    return pkts[-1]["t0_ms"]


def evaluate(run: Run, cal: dict, st_after: dict, c: Checks):
    print("\nresults")
    grace = 0.5  # packets already in flight when STOP was written
    streamed = [(t, b) for t, b in run.sensor if t <= run.stop_at + grace]
    after = [(t, b) for t, b in run.sensor if t > run.stop_at + grace]

    want_len = 8 + SAMPLES_PER_PACKET * sample_size(run.n)
    bad_len = [len(b) for _, b in streamed if len(b) != want_len]
    c.check(not bad_len, f"every sensor notification is exactly {want_len} bytes",
            f"{len(streamed)} packets, {len(bad_len)} wrong: {sorted(set(bad_len))[:5]}")

    pkts = []
    for t, b in streamed:
        try:
            pkts.append((t, parse_sensor(b, run.n)))
        except Reject as e:
            c.check(False, "sensor packet parses", e.reason)
    if not pkts:
        c.check(False, "received sensor packets")
        return

    c.check(all(p["count"] == SAMPLES_PER_PACKET for _, p in pkts), "count = 8 in every packet")
    c.check(pkts[0][1]["seq"] == 0, "seq starts at 0 after START_STREAM", str(pkts[0][1]["seq"]))
    gaps = [(a["seq"], b["seq"]) for (_, a), (_, b) in zip(pkts, pkts[1:])
            if (a["seq"] + 1) & 0xFFFF != b["seq"]]
    c.check(not gaps, "no seq gaps", f"{len(gaps)} gaps {gaps[:5]}")
    steps = {b["t0_ms"] - a["t0_ms"] for (_, a), (_, b) in zip(pkts, pkts[1:])}
    c.check(steps == {SAMPLES_PER_PACKET * SAMPLE_PERIOD_MS}, "t0 step = 160 ms", str(sorted(steps)[:5]))

    span = pkts[-1][0] - pkts[0][0]
    rate = (len(pkts) - 1) / span if span > 0 else 0
    c.check(abs(rate - PACKET_RATE_HZ) / PACKET_RATE_HZ < 0.02, "packet rate 6.25 Hz (+-2 %)",
            f"{rate:.3f} Hz over {span:.1f} s")
    # Device clock vs laptop arrival: drift and jitter (informational for S4).
    lag = [t * 1000 - p["t0_ms"] for t, p in pkts]
    base = lag[0]
    lag = [x - base for x in lag]
    print(f"  arrival - t0 (ms, relative): min {min(lag):.1f}, max {max(lag):.1f}, "
          f"last {lag[-1]:.1f} (clock drift + BLE jitter, informational)")

    adcs = [a for _, p in pkts for s in p["samples"] for a in s["fsr_adc"]]
    c.check(max(adcs) <= 4095, "ADC within 0-4095", f"max {max(adcs)}")
    c.check(not any(p["flags"] for _, p in pkts), "flags = 0 (not saturated, not calibrating)")
    peaks = [max(s["fsr_adc"][i] for _, p in pkts for s in p["samples"]) for i in range(run.n)]
    kpa = [round(adc_to_kpa(a, cal["channels"][i], cal), 1) for i, a in enumerate(peaks)]
    print(f"  peak ADC per channel {peaks} -> kPa {kpa} (informational)")

    c.check(not after, "sensor stream stops after STOP_STREAM", f"{len(after)} packets after")
    temp_after = [x for x in run.temp if x[0] > run.stop_at + grace]
    c.check(not temp_after, "temperature stops after STOP_STREAM", f"{len(temp_after)} after")

    temps = []
    for t, b in run.temp:
        try:
            temps.append((t, parse_temperature(b)))
        except Reject as e:
            c.check(False, "temperature packet is 12 bytes", f"{len(b)} bytes ({e.reason})")
    if temps:
        first_delay = temps[0][0] - run.start_at
        c.check(first_delay < 2.0, "first temperature right after START_STREAM",
                f"{first_delay:.2f} s")
        dts = {b["t_ms"] - a["t_ms"] for (_, a), (_, b) in zip(temps, temps[1:])}
        c.check(not dts or dts == {TEMP_PERIOD_MS}, "temperature every 30 s (device time)",
                str(sorted(dts)))
        expected = 1 + int((run.stop_at - run.start_at) // 30)
        c.check(abs(len(temps) - expected) <= 1, "temperature packet count",
                f"{len(temps)}, expected about {expected}")
        tseq = [p["seq"] for _, p in temps]
        c.check(tseq == list(range(len(tseq))), "temperature seq 0, 1, 2, ...")
        c.check(all(p["quality"] == 0 and p["forefoot_c"] is not None and p["heel_c"] is not None
                    for _, p in temps), "temperature readable, quality 0")
        print(f"  temperature: forefoot {temps[0][1]['forefoot_c']}..{temps[-1][1]['forefoot_c']} C, "
              f"heel {temps[0][1]['heel_c']}..{temps[-1][1]['heel_c']} C")
    else:
        c.check(False, "received temperature packets")

    sts = []
    for t, b in run.status:
        try:
            sts.append((t, parse_status(b)))
        except Reject as e:
            c.check(False, "status notification is 8 bytes", f"{len(b)} bytes ({e.reason})")
    streaming = [s for t, s in sts if run.start_at < t <= run.stop_at]
    c.check(any(s["state"] == 1 for s in streaming), "status notifies state 1 after START")
    c.check(all(s["battery_pct"] >= BATTERY_FLOOR_PCT for _, s in sts) and
            st_after["battery_pct"] >= BATTERY_FLOOR_PCT, "battery >= 50 %",
            f"last {st_after['battery_pct']} % / {st_after['battery_mv']} mV")
    c.check(st_after["state"] == 0, "state 0 after STOP_STREAM", f"state {st_after['state']}")
    c.check(any(s["state"] == 0 for t, s in sts if t > run.stop_at), "status notifies state 0 after STOP")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--side", choices=["L", "R"], default="L")
    ap.add_argument("--duration", type=float, default=120, help="seconds of streaming")
    ap.add_argument("--fsr-count", type=int, default=6)
    ap.add_argument("--scan-timeout", type=float, default=20)
    ap.add_argument("--reconnects", type=int, default=2,
                    help="disconnect/reconnect cycles after the main run")
    ap.add_argument("--selftest", action="store_true", help="only check the parsers")
    args = ap.parse_args()

    if not selftest():
        return 1
    if args.selftest:
        return 0
    return 0 if asyncio.run(live(args)) else 1


if __name__ == "__main__":
    sys.exit(main())

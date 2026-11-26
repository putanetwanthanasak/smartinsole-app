#!/usr/bin/env python3
"""Capture what a real insole board sends over BLE, from the laptop (bleak).

For checking the hardware team's firmware against DATA-CONTRACT v1.6
(Appendix C) before any phone connects. Read-only apart from the control
writes the check needs: START_STREAM, STOP_STREAM and, with
--app-sequence, SYNC_TIME before START (the app's own connect sequence,
docs/FLUTTER-PLAN.md section 5). Any other control write (TARE, REBOOT,
SET_RATE, anything unknown) is refused in code. Nothing is judged here;
compare.py reads the capture afterwards.

    firmware/simulator/tools/.venv/bin/python tools/board_check/board_capture.py \\
        --side R --usb-mac <MAC from the by-id name> --duration 65 \\
        --out ~/smartinsole-data/board-checks/<run>
    (that venv has bleak)

It connects only to the cabled chip (--usb-mac: the base MAC in its
/dev/serial/by-id name, BLE address = base + 0..3), never to a board picked
by name or service UUID: in SR-1 another team's insole was in range, and our
own simulators advertise the same names. --scan-only needs no --usb-mac.

Writes into --out (refused inside the repo):
  capture.jsonl     one JSON record per event: scan adverts, GATT table,
                    reads, writes, every notification (laptop monotonic and
                    unix time + hex bytes), disconnects
  calibration.json  the calibration characteristic exactly as read
  console.txt       this script's output
"""

from __future__ import annotations

import argparse
import asyncio
import json
import struct
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "firmware" / "simulator" / "tools"))
import sim_check  # noqa: E402  (UUIDs; parsers are used by compare.py)

SERVICE = sim_check.SERVICE
CHARS = {
    "sensor": sim_check.SENSOR,
    "temperature": sim_check.TEMPERATURE,
    "status": sim_check.STATUS,
    "control": sim_check.CONTROL,
    "calibration": sim_check.CALIBRATION,
}
# Device Information Service strings, read if the board has them.
DIS = {
    "00002a29-0000-1000-8000-00805f9b34fb": "manufacturer",
    "00002a24-0000-1000-8000-00805f9b34fb": "model",
    "00002a26-0000-1000-8000-00805f9b34fb": "firmware_revision",
    "00002a27-0000-1000-8000-00805f9b34fb": "hardware_revision",
    "00002a28-0000-1000-8000-00805f9b34fb": "software_revision",
}
ALLOWED_OPCODES = {0x01: "START_STREAM", 0x02: "STOP_STREAM", 0x03: "SYNC_TIME"}


class Recorder:
    def __init__(self, out: Path):
        self.f = open(out / "capture.jsonl", "a", encoding="utf-8")
        self.console = open(out / "console.txt", "a", encoding="utf-8")

    def rec(self, kind: str, **fields) -> None:
        fields = {"kind": kind, "t": time.monotonic(), "unix_ms": int(time.time() * 1000),
                  **fields}
        self.f.write(json.dumps(fields) + "\n")
        self.f.flush()

    def say(self, text: str) -> None:
        print(text, flush=True)
        self.console.write(text + "\n")
        self.console.flush()


def mac_targets(usb_mac: str | None) -> set[str]:
    """The ESP32 BLE address is the chip's base MAC (its USB serial number)
    plus 2 on the C3 (plus 2 or 3 on other ESP32s); accept base..base+3."""
    if not usb_mac:
        return set()
    base = int(usb_mac.replace(":", ""), 16)
    return {":".join(f"{(base + k) >> (8 * i) & 0xFF:02X}" for i in range(5, -1, -1))
            for k in range(4)}


async def scan(r: Recorder, want_name: str, timeout: float, targets: set[str]):
    """Unfiltered scan (a board that leaves the service UUID out of its
    advertising would be invisible to a filtered one). Records only adverts
    from the target address or carrying the service UUID or a SMARTINSOLE
    name, nobody else's. Picks only the target address, never a board by
    name or "any board with the UUID" (SR-1: another insole nearby)."""
    from bleak import BleakScanner

    seen = {}

    def on_adv(dev, adv):
        uuids = [u.lower() for u in adv.service_uuids]
        name = adv.local_name or dev.name or ""
        mine = dev.address.upper() in targets
        if not mine and SERVICE not in uuids and not name.startswith("SMARTINSOLE"):
            return
        r.rec("adv", address=dev.address, target=mine, name=dev.name, local_name=adv.local_name,
              rssi=adv.rssi, tx_power=adv.tx_power, service_uuids=uuids,
              manufacturer_data={str(k): v.hex() for k, v in adv.manufacturer_data.items()},
              service_data={k: v.hex() for k, v in adv.service_data.items()})
        seen[dev.address] = (dev, adv)

    def pick():
        # Connecting needs targets (main() enforces --usb-mac); a scan-only
        # run without them just lists what is near.
        return [d for d, _ in seen.values() if d.address.upper() in targets]

    what = "the cabled board's address" if targets else "nothing in particular (scan only)"
    r.say(f"scanning up to {timeout:.0f} s for {what} (unfiltered; recording only the target, "
          f"SMARTINSOLE names and the service UUID) ...")
    async with BleakScanner(on_adv):
        t_end = time.monotonic() + timeout
        found_at = None
        while time.monotonic() < t_end:
            if found_at is None and pick():
                found_at = time.monotonic()
            # A few seconds more after the first hit, for scan responses.
            if found_at is not None and time.monotonic() - found_at > 4:
                break
            await asyncio.sleep(0.2)
    for addr, (d, a) in seen.items():
        r.say(f"  seen: {'TARGET ' if addr.upper() in targets else ''}name {a.local_name or d.name!r}, "
              f"rssi {a.rssi}, service UUID advertised: "
              f"{SERVICE in [u.lower() for u in a.service_uuids]}")
    return (pick() or [None])[0]


async def run(args) -> int:
    from bleak import BleakClient

    out = Path(args.out).expanduser().resolve()
    if REPO == out or REPO in out.parents:
        print(f"refusing --out {out}: inside the repo (board data stays out of git)",
              file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    if (out / "capture.jsonl").exists():
        print(f"refusing: {out}/capture.jsonl exists; use a new --out", file=sys.stderr)
        return 2
    r = Recorder(out)
    want_name = f"SMARTINSOLE-{args.side}"
    r.rec("meta", tool="board_capture.py", side=args.side, duration_s=args.duration,
          app_sequence=args.app_sequence, want_name=want_name)

    targets = mac_targets(args.usb_mac)
    dev = await scan(r, want_name, args.scan_timeout, targets)
    if args.scan_only:
        r.say("scan only: target " + ("seen" if dev else "not seen" if targets else "not given"))
        r.rec("end", ok=True, reason="scan only", target_seen=dev is not None)
        return 0
    if dev is None:
        r.say("target board not found: no advert from the cabled board's address")
        r.rec("end", ok=False, reason="not found")
        return 1

    r.rec("connecting", address=dev.address)
    disconnected = []

    def on_disconnect(_):
        disconnected.append(time.monotonic())
        r.rec("disconnected")

    async with BleakClient(dev, disconnected_callback=on_disconnect) as client:
        # Without a successful acquire, bleak reports its default 23, which
        # says nothing about the board: recorded so compare.py doesn't judge it.
        acquired = False
        acquire = getattr(getattr(client, "_backend", None), "_acquire_mtu", None)
        if acquire:
            try:
                await acquire()
                acquired = True
            except Exception as e:  # noqa: BLE001
                r.say(f"  MTU acquire failed: {e}")
        else:
            r.say("  this bleak backend cannot acquire the MTU")
        r.rec("connected", mtu=client.mtu_size, mtu_acquired=acquired)
        r.say(f"connected, mtu {client.mtu_size}")

        table = []
        for svc in client.services:
            chars = []
            for ch in svc.characteristics:
                chars.append({"uuid": ch.uuid.lower(), "handle": ch.handle,
                              "properties": list(ch.properties),
                              "descriptors": [d.uuid.lower() for d in ch.descriptors]})
            table.append({"uuid": svc.uuid.lower(), "characteristics": chars})
        r.rec("gatt", services=table)
        ours = next((s for s in table if s["uuid"] == SERVICE), None)
        have = {c["uuid"]: c for c in (ours or {}).get("characteristics", [])}
        r.say(f"  service {SERVICE}: {'present' if ours else 'MISSING'}")
        for name, uuid in CHARS.items():
            c = have.get(uuid)
            r.say(f"    {name:12s} {uuid[-6:]}: "
                  f"{','.join(c['properties']) if c else 'MISSING'}")

        async def read(name: str, uuid: str, phase: str):
            try:
                b = bytes(await client.read_gatt_char(uuid))
                r.rec("read", char=name, phase=phase, hex=b.hex())
                return b
            except Exception as e:  # noqa: BLE001
                r.rec("read_error", char=name, phase=phase, error=f"{type(e).__name__}: {e}")
                r.say(f"  read {name} ({phase}) failed: {type(e).__name__}: {e}")
                return None

        # Device Information Service, if present (read-only strings).
        for svc in table:
            for ch in svc["characteristics"]:
                if ch["uuid"] in DIS and "read" in ch["properties"]:
                    b = await read(DIS[ch["uuid"]], ch["uuid"], "dis")
                    if b is not None:
                        r.say(f"  DIS {DIS[ch['uuid']]}: {b.decode('utf-8', 'replace')!r}")

        st = await read("status", CHARS["status"], "before_start") if CHARS["status"] in have else None
        if st is not None:
            r.say(f"  status before START: {st.hex(' ')} ({len(st)} bytes)")
        cal = await read("calibration", CHARS["calibration"], "connect") \
            if CHARS["calibration"] in have else None
        if cal is not None:
            (out / "calibration.json").write_bytes(cal)
            r.say(f"  calibration: {len(cal)} bytes -> calibration.json")

        for name in ("status", "temperature", "sensor"):
            uuid = CHARS[name]
            c = have.get(uuid)
            if not c or not ({"notify", "indicate"} & set(c["properties"])):
                r.say(f"  {name}: no notify property, not subscribed")
                continue
            try:
                await client.start_notify(
                    uuid, lambda _, d, n=name: r.rec("notify", char=n, hex=bytes(d).hex()))
                r.rec("subscribed", char=name)
            except Exception as e:  # noqa: BLE001
                r.rec("subscribe_error", char=name, error=f"{type(e).__name__}: {e}")
                r.say(f"  subscribe {name} failed: {type(e).__name__}: {e}")

        async def control(data: bytes, label: str):
            if not data or data[0] not in ALLOWED_OPCODES:
                raise RuntimeError(f"refusing control write {data.hex()}: read-only check")
            r.rec("write", char="control", label=label, hex=data.hex(), phase="sent")
            try:
                await client.write_gatt_char(CHARS["control"], data, response=True)
                r.rec("write", char="control", label=label, hex=data.hex(), phase="acked")
            except Exception as e:  # noqa: BLE001
                r.rec("write_error", char="control", label=label, error=f"{type(e).__name__}: {e}")
                r.say(f"  write {label} failed: {type(e).__name__}: {e}")

        r.say("  listening 1 s before START (nothing should arrive) ...")
        r.rec("mark", label="pre_start_window")
        await asyncio.sleep(1.0)

        if args.app_sequence:
            await control(bytes([0x03]) + struct.pack("<Q", int(time.time() * 1000)), "SYNC_TIME")
        await control(b"\x01", "START_STREAM")
        r.say(f"START_STREAM written; recording {args.duration:.0f} s ...")
        t_start = time.monotonic()
        while time.monotonic() - t_start < args.duration and not disconnected:
            await asyncio.sleep(min(10.0, args.duration - (time.monotonic() - t_start)))
            r.say(f"  t+{time.monotonic() - t_start:4.0f} s")
        await control(b"\x02", "STOP_STREAM")
        r.rec("mark", label="post_stop_window")
        r.say("STOP_STREAM written; listening 3 s for anything after it ...")
        await asyncio.sleep(3.0)
        if not disconnected:
            st2 = await read("status", CHARS["status"], "after_stop") \
                if CHARS["status"] in have else None
            if st2 is not None:
                r.say(f"  status after STOP: {st2.hex(' ')}")
    r.rec("end", ok=True)
    n = {"sensor": 0, "temperature": 0, "status": 0}
    for ln in (out / "capture.jsonl").read_text().splitlines():
        e = json.loads(ln)
        if e["kind"] == "notify":
            n[e["char"]] += 1
    r.say(f"done: {n['sensor']} sensor, {n['temperature']} temperature, "
          f"{n['status']} status notifications -> {out}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--side", choices=["L", "R"], required=True)
    ap.add_argument("--duration", type=float, default=65, help="seconds between START and STOP")
    ap.add_argument("--app-sequence", action="store_true",
                    help="send SYNC_TIME before START, as the app does")
    ap.add_argument("--scan-timeout", type=float, default=20)
    ap.add_argument("--usb-mac", help="the board's USB serial number (its base MAC, from "
                    "/dev/serial/by-id/usb-Espressif_..._<MAC>-if00): connect only to that chip")
    ap.add_argument("--scan-only", action="store_true",
                    help="scan and report, never connect")
    ap.add_argument("--out", required=True, help="new folder outside the repo")
    args = ap.parse_args()
    if not args.usb_mac and not args.scan_only:
        ap.error("--usb-mac is required to connect (only the cabled board is ever "
                 "connected); use --scan-only to just look")
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())

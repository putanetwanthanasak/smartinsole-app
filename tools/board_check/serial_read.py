#!/usr/bin/env python3
"""Read-only serial log of a real insole board on its ESP32 USB port.

The real boards are the hardware team's firmware: this script never writes a
byte to the port. It opens only an Espressif USB-Serial/JTAG port named by
/dev/serial/by-id/usb-Espressif_..., and refuses anything else (the laptop's
Quectel LTE modem is also a USB serial port).

Reset safety. On the ESP32's own USB-Serial/JTAG port the host's RTS and DTR
lines drive the chip's reset: RTS asserted with DTR not asserted holds the
chip in reset (esptool uses this). Linux raises DTR and RTS together when
the port opens and drops them together when it closes, which never passes
through that combination. This script keeps them exactly there: both
asserted while open, no separate DTR or RTS change. (The simulator logger,
firmware/simulator/tools/serial_log.py, lowers DTR first: correct for its
CP2102 boards, but on this port it would reset the chip.)

Pressing the board's RESET button restarts the whole chip, USB included, so
the port disappears and comes back. The script waits for the by-id path to
reappear and reopens it, logging both events. Lines printed before the USB
port re-enumerates are lost by the hardware; the raw byte copy keeps
everything that did arrive.

    /usr/bin/python3 tools/board_check/serial_read.py \\
        /dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_...-if00 \\
        ~/smartinsole-data/board-checks/<run>/serial.log

Writes <log> (laptop-timestamped lines) and <log>.raw (every byte read).
Stop it with SIGTERM (kill <pid>) or Ctrl-C.
"""

from __future__ import annotations

import argparse
import glob
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

import serial  # pyserial (/usr/bin/python3 has it; the bleak venv does not)

ALLOWED_PREFIX = "/dev/serial/by-id/usb-Espressif_"
REPO = Path(__file__).resolve().parents[2]


def stamp() -> str:
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def clean(raw: bytes) -> str:
    return raw.decode("utf-8", "replace").rstrip("\r")


def refuse_reason(port: str) -> str | None:
    if not port.startswith(ALLOWED_PREFIX):
        return f"only {ALLOWED_PREFIX}* ports are opened (got {port})"
    real = os.path.realpath(port)
    for name in glob.glob("/dev/serial/by-id/*"):
        if not os.path.basename(name).startswith("usb-Espressif_") and \
                os.path.realpath(name) == real:
            return f"{port} resolves to the same device as {os.path.basename(name)}"
    return None


def open_port(port: str) -> serial.Serial:
    ser = serial.Serial()
    ser.port = port
    ser.baudrate = 115200  # ignored by USB-Serial/JTAG, set for completeness
    ser.timeout = 0.2
    # Linux has already asserted both lines at open; asking for the same
    # state sends no USB request. Never change one line without the other.
    ser.dtr = True
    ser.rts = True
    ser.open()
    return ser


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("port", help=f"{ALLOWED_PREFIX}...-if00")
    ap.add_argument("out", help="log file (appended); <out>.raw gets the raw bytes")
    args = ap.parse_args()

    why = refuse_reason(args.port)
    if why:
        print(f"refusing: {why}", file=sys.stderr)
        return 2
    out = Path(args.out).expanduser().resolve()
    if REPO in out.parents:
        print(f"refusing: {out} is inside the repo; board logs stay out of git "
              f"(~/smartinsole-data/board-checks/)", file=sys.stderr)
        return 2
    out.parent.mkdir(parents=True, exist_ok=True)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    with open(out, "a", encoding="utf-8") as log, open(f"{out}.raw", "ab") as raw:
        def line(text: str) -> None:
            log.write(f"{stamp()} {text}\n")
            log.flush()

        log.write(f"# {datetime.now():%Y-%m-%d %H:%M:%S} read-only log of {args.port}\n")
        log.flush()
        ser = None
        buf = b""
        try:
            while True:
                if ser is None:
                    if not os.path.exists(args.port):
                        time.sleep(0.02)
                        continue
                    try:
                        ser = open_port(args.port)
                        line("[serial_read] port open")
                    except (OSError, serial.SerialException) as e:
                        line(f"[serial_read] open failed: {e}")
                        time.sleep(0.5)
                        continue
                try:
                    data = ser.read(ser.in_waiting or 1)
                except (OSError, serial.SerialException) as e:
                    if buf:
                        line(clean(buf))
                        buf = b""
                    line(f"[serial_read] port gone ({type(e).__name__}); waiting for it")
                    try:
                        ser.close()
                    except Exception:
                        pass
                    ser = None
                    continue
                if data:
                    raw.write(data)
                    raw.flush()
                    buf += data
                    while b"\n" in buf:
                        one, buf = buf.split(b"\n", 1)
                        line(clean(one))
        except KeyboardInterrupt:
            pass
        finally:
            if buf:
                line(clean(buf))
            if ser is not None:
                ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

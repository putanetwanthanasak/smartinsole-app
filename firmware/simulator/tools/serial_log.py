#!/usr/bin/env python3
"""Log one simulator board's serial output with laptop timestamps.

Each line is written as `HH:MM:SS.mmm <text>` (laptop clock), with control
bytes stripped, and flushed at once so the file can be read while a test
runs. Runs until Ctrl-C or SIGTERM.

Opening the CP2102 port resets the board (POWERON_RESET, even with DTR/RTS
held low), which drops every BLE central. Start this BEFORE any central
connects and never reopen the port during a test. Open the board by its
`/dev/serial/by-path/...` name (or by-id when only one CP2102 is plugged
in), never by ttyUSB number: the numbers swap, and the other ttyUSB on the
dev laptop is an LTE modem.

    /usr/bin/python3 tools/serial_log.py \
        /dev/serial/by-path/pci-0000:00:14.0-usb-0:6:1.0-port0 left.log

Uses pyserial, which /usr/bin/python3 has (the bleak venv does not).
"""

from __future__ import annotations

import argparse
import glob
import os
import signal
import sys
from datetime import datetime

import serial

BAUD = 115200


def stamp() -> str:
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def clean(raw: bytes) -> str:
    text = raw.decode("utf-8", errors="replace")
    return "".join(ch for ch in text if ch == "\t" or ch >= " ").rstrip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("port", help="/dev/serial/by-path/... or by-id/... of the CP2102")
    ap.add_argument("out", help="log file (appended)")
    args = ap.parse_args()

    if "/dev/serial/" not in args.port:
        print("refusing a bare ttyUSB name; use /dev/serial/by-path/ or by-id/", file=sys.stderr)
        return 2
    real = os.path.realpath(args.port)
    for name in glob.glob("/dev/serial/by-id/*"):
        if "CP210" not in name and os.path.realpath(name) == real:
            print(f"refusing {args.port}: it is {os.path.basename(name)}, not a CP2102", file=sys.stderr)
            return 2

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    ser = serial.Serial()
    ser.port = args.port
    ser.baudrate = BAUD
    ser.timeout = 0.5
    ser.dtr = False
    ser.rts = False
    ser.open()
    ser.reset_input_buffer()

    with open(args.out, "a", encoding="utf-8") as f:
        f.write(f"# {datetime.now():%Y-%m-%d %H:%M:%S} logging {args.port}\n")
        f.flush()
        buf = b""
        try:
            while True:
                buf += ser.read(ser.in_waiting or 1)
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    f.write(f"{stamp()} {clean(line)}\n")
                    f.flush()
        except KeyboardInterrupt:
            pass
        finally:
            if buf:
                f.write(f"{stamp()} {clean(buf)}\n")
            ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

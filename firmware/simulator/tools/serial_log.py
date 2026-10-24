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

`--commands FIFO` makes a named pipe; each line written to it is sent to
the board over the same open port (no second open, so no reset), e.g. the
S7 scenario commands: `echo p > left.cmd` (n normal, t forefoot +3 degC,
p meta1 ~250 kPa, ? show). Sent commands are logged as `> p`.

Uses pyserial, which /usr/bin/python3 has (the bleak venv does not).
"""

from __future__ import annotations

import argparse
import glob
import os
import signal
import stat
import sys
import threading
from datetime import datetime

import serial

BAUD = 115200


def stamp() -> str:
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def clean(raw: bytes) -> str:
    text = raw.decode("utf-8", errors="replace")
    return "".join(ch for ch in text if ch == "\t" or ch >= " ").rstrip()


def forward_commands(fifo: str, ser: serial.Serial, log) -> None:
    """Sends every line written to [fifo] to the board, forever."""
    while True:
        with open(fifo, "rb") as pipe:  # blocks until a writer opens it
            for line in pipe:
                cmd = line.strip()
                if cmd:
                    ser.write(cmd)
                    log(f"> {clean(cmd)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("port", help="/dev/serial/by-path/... or by-id/... of the CP2102")
    ap.add_argument("out", help="log file (appended)")
    ap.add_argument("--commands", metavar="FIFO",
                    help="named pipe (created if missing) whose lines are sent to the board")
    args = ap.parse_args()
    if args.commands:
        if not os.path.exists(args.commands):
            os.mkfifo(args.commands)
        elif not stat.S_ISFIFO(os.stat(args.commands).st_mode):
            print(f"{args.commands} exists and is not a named pipe", file=sys.stderr)
            return 2

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
        lock = threading.Lock()

        def log(text: str) -> None:
            with lock:
                f.write(f"{stamp()} {text}\n")
                f.flush()

        f.write(f"# {datetime.now():%Y-%m-%d %H:%M:%S} logging {args.port}\n")
        f.flush()
        if args.commands:
            threading.Thread(target=forward_commands, args=(args.commands, ser, log),
                             daemon=True).start()
        buf = b""
        try:
            while True:
                buf += ser.read(ser.in_waiting or 1)
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    log(clean(line))
        except KeyboardInterrupt:
            pass
        finally:
            if buf:
                log(clean(buf))
            ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

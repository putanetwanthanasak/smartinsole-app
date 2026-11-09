# tools/board_check — checking a real insole board against the contract

Laptop tools for the hardware team's boards (session SR-1, report 042). They
check what a board sends against `docs/DATA-CONTRACT.md` v1.6 (Appendix C)
before any phone connects. They are not the simulator's tools:
`firmware/simulator/tools/sim_check.py` judges simulator behaviour
(battery ≥ 50 %, every temperature site readable, TARE, REBOOT) that a real
board need not share, and `serial_log.py` opens only CP2102 boards.

## Safety rules (the board runs the hardware team's real firmware)

- **Nothing is flashed, erased or reset.** `serial_read.py` never writes to
  the serial port and holds DTR and RTS exactly where Linux puts them at
  open (both asserted together), so the ESP32's USB-Serial/JTAG reset
  combination (RTS without DTR) never happens. It opens only
  `/dev/serial/by-id/usb-Espressif_*`, never the Quectel modem.
- **BLE writes are limited in code** to START_STREAM, STOP_STREAM and (with
  `--app-sequence`) SYNC_TIME. TARE, REBOOT, SET_RATE and anything else are
  refused by `board_capture.py`.
- **Captures stay out of git.** The repo is public and the firmware's
  output is the hardware team's work: every tool refuses an output path
  inside the repo. Use `~/smartinsole-data/board-checks/<run>/`. Reports
  quote short excerpts only and never the board's MAC address.

## Before plugging in

- ModemManager must ignore the board's USB port (it probes new ttys, which
  can reset the chip): `/etc/udev/rules.d/99-esp32-usbjtag-no-modemmanager.rules`
  with `ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", ENV{ID_MM_DEVICE_IGNORE}="1"`.
- The Claude Code process may lack `dialout`: `sudo setfacl -m u:pumon:rw
  /dev/ttyACM0` after each plug-in (a RESET re-creates the node and drops
  the ACL; adding `OWNER="pumon"` to the rule above avoids that).
- The phone's Bluetooth off, so the board has one central (the laptop).

## Commands (repo root)

```sh
RUN=~/smartinsole-data/board-checks/<run>
# 1. serial log (read-only), started first and left running
/usr/bin/python3 tools/board_check/serial_read.py \
    /dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_<...>-if00 $RUN/serial.log &
# 2. BLE capture: START, 65 s, STOP; then the app's sequence (SYNC_TIME first).
#    --usb-mac = the MAC in the board's by-id name: only that chip is ever
#    connected (never a board picked by name or service UUID; --scan-only
#    just looks and needs no --usb-mac).
MAC=<MAC from the by-id name>
firmware/simulator/tools/.venv/bin/python tools/board_check/board_capture.py \
    --side R --usb-mac $MAC --duration 65 --out $RUN/run1-start-stop
firmware/simulator/tools/.venv/bin/python tools/board_check/board_capture.py \
    --side R --usb-mac $MAC --duration 10 --app-sequence --out $RUN/run2-app-sequence
# 3. offline comparison (no Bluetooth) and the app's own parsers
python3 tools/board_check/compare.py $RUN/run1-start-stop $RUN/run2-app-sequence \
    --serial $RUN/serial.log --md $RUN/analysis.md
(cd mobile && dart run tool/check_capture.dart $RUN/run1-start-stop/capture.jsonl)
```

`compare.py` runs `sim_check.py`'s parser selftest against
`shared/test_vectors/` first, then checks advertising, GATT, MTU, status,
calibration, the sensor stream (232 bytes, count 8, seq from 0 with no gaps,
t0 + 160 ms per packet, 6.25 Hz, flags, ADC range, IMU, walking-gate
statistic, channels pressed in time order) and temperature v2, prints the
first packet of each kind next to its Appendix C example, and ends with a
mismatch table (blocker / issue / note, each with its effect in the app).
A run shorter than 35 s is not judged on temperature (the contract sets a
30 s period, not when the first packet comes). It never overwrites: an
existing `analysis.md` gets a time-stamped sibling instead.
`mobile/tool/check_capture.dart` runs the app's Dart parsers over the same
capture and prints what Researcher › Diagnostics would show.

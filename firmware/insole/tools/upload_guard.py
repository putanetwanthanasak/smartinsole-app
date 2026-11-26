# PlatformIO pre-script: refuses any flash or erase that isn't to the cabled
# ESP32's own USB-Serial/JTAG port. Never the laptop's Quectel modem (a
# ttyUSB device), never an auto-detected port, never the buildcheck env.
# The port comes from INSOLE_UPLOAD_PORT so the by-id name (it carries the
# chip's MAC) stays out of this public repo.
import os
import sys

Import("env")  # noqa: F821  (PlatformIO SCons global)

WRITE_TARGETS = {"upload", "uploadfs", "uploadfsota", "erase", "erase_upload", "program", "nobuild"}
PREFIX = "/dev/serial/by-id/usb-Espressif_"


def refuse(msg):
    sys.stderr.write(f"\nupload_guard: REFUSED: {msg}\n\n")
    env.Exit(1)  # noqa: F821


targets = set(COMMAND_LINE_TARGETS)  # noqa: F821
if targets & WRITE_TARGETS:
    name = env["PIOENV"]  # noqa: F821
    port = os.environ.get("INSOLE_UPLOAD_PORT", "")
    if name == "buildcheck":
        refuse("the buildcheck env has placeholder pins and is never flashed")
    if not port:
        refuse("INSOLE_UPLOAD_PORT is not set (no auto-detected ports)")
    if not port.startswith(PREFIX):
        refuse(f"{port} is not a {PREFIX}* path")
    if not os.path.exists(port):
        refuse(f"{port} does not exist (board unplugged?)")
    real = os.path.realpath(port)
    if not os.path.basename(real).startswith("ttyACM"):
        refuse(f"{port} resolves to {real}, not the ESP32's own USB port (ttyACM*)")
    by_id = "/dev/serial/by-id"
    for other in os.listdir(by_id):
        p = os.path.join(by_id, other)
        if not other.startswith("usb-Espressif_") and os.path.realpath(p) == real:
            refuse(f"{port} is also {p}")
    env.Replace(UPLOAD_PORT=port)  # noqa: F821
    print(f"upload_guard: {name} -> {real} (Espressif USB-Serial/JTAG)")

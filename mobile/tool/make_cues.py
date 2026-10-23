#!/usr/bin/env python3
"""Writes the research-capture cue sounds (assets/sounds/*.wav).

Plain sine beeps, generated here so the app ships no third-party audio.
Run from mobile/: python3 tool/make_cues.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def tone(freq: float, ms: int) -> list[float]:
    n = int(RATE * ms / 1000)
    ramp = int(RATE * 0.01)  # 10 ms fade in/out, no clicks
    out = []
    for i in range(n):
        env = min(1.0, i / ramp, (n - 1 - i) / ramp)
        out.append(0.8 * env * math.sin(2 * math.pi * freq * i / RATE))
    return out


def silence(ms: int) -> list[float]:
    return [0.0] * int(RATE * ms / 1000)


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


def main() -> None:
    write("cue_practice.wav", tone(523, 150) + silence(100) + tone(523, 150))
    write("cue_start.wav", tone(880, 300))
    write("cue_warning.wav", tone(988, 200) + silence(120) + tone(988, 200))
    write(
        "cue_end.wav",
        tone(784, 300) + silence(120) + tone(784, 300) + silence(120) + tone(587, 600),
    )
    write(
        "cue_link_lost.wav",
        tone(440, 150) + silence(80) + tone(440, 150) + silence(80) + tone(440, 150),
    )


if __name__ == "__main__":
    main()

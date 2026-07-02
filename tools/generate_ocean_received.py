#!/usr/bin/env python3
"""Generate OceanReceived.caf, the capture-received chime.

The sound the Ocean makes when it quietly receives a thought: two soft
glassy notes a perfect fifth apart (D5 then A5), no hard transients,
ringing out in a plate-style reverb tail with subtle stereo width.
Peaks around -12 dBFS so it sits under the moment instead of announcing it.

Pure Python standard library (no numpy/soundfile), then afconvert (ships
with macOS) packs the rendered WAV into an IMA4-compressed CAF, which is
what AudioServicesCreateSystemSoundID plays and keeps the file small.

Regenerate the bundled asset:

    python3 tools/generate_ocean_received.py

Tune the feel:

    # different notes (Hz): a major third instead of a fifth
    python3 tools/generate_ocean_received.py --notes 587.33 739.99

    # longer, wetter tail
    python3 tools/generate_ocean_received.py --reverb-time 1.6 --wet 0.6 --total 1.8

    # audition without touching the bundle
    python3 tools/generate_ocean_received.py --wav-out /tmp/chime.wav --out /tmp/chime.caf
"""

import argparse
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

SR = 44100

# ---- The feel, in knobs -------------------------------------------------
D5 = 587.33
A5 = 880.00

NOTE_GAP = 0.16          # s between the two note onsets
NOTE_LEVELS = (0.85, 1.0)  # the second note is the "arrival"
ATTACK = 0.032           # s, raised-cosine attack: soft, no click
DECAY_TAU = 0.13         # s, exponential decay of each note body
PARTIALS = (             # (multiple of fundamental, relative level)
    (1.0, 1.0),
    (2.0, 0.16),
    (3.0, 0.055),
    (4.16, 0.02),        # slightly inharmonic top partial = glassiness
)
LOWPASS_HZ = 4200.0      # gentle low-pass so nothing is piercing
WIDTH_CENTS = 4.0        # +/- detune between channels (slow beating = width)
WET_PREDELAY_R = 0.007   # s, extra pre-delay on the right reverb only:
                         # widens the diffuse field, keeps the notes centered

# Schroeder plate: parallel damped combs into series allpasses.
COMB_DELAYS = (0.0297, 0.0371, 0.0411, 0.0437)
COMB_DAMP_HZ = 3000.0
COMB_SCALE_R = 1.013     # decorrelates the right channel's plate
ALLPASS_DELAYS = (0.0050, 0.0017)
ALLPASS_G = 0.7


def one_pole_coeff(cutoff_hz: float) -> float:
    return 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)


def render_notes(freqs, detune_cents: float, total_samples: int) -> list:
    """The dry signal: soft-attack glassy tones, low-passed."""
    out = [0.0] * total_samples
    for note_index, freq in enumerate(freqs):
        f0 = freq * 2.0 ** (detune_cents / 1200.0)
        start = int(note_index * NOTE_GAP * SR)
        level = NOTE_LEVELS[min(note_index, len(NOTE_LEVELS) - 1)]
        n = 0
        while True:
            t = n / SR
            if t < ATTACK:
                env = 0.5 - 0.5 * math.cos(math.pi * t / ATTACK)
            else:
                env = math.exp(-(t - ATTACK) / DECAY_TAU)
            if t >= ATTACK and env < 1e-4:
                break
            i = start + n
            if i >= total_samples:
                break
            s = 0.0
            for mult, amp in PARTIALS:
                s += amp * math.sin(2.0 * math.pi * f0 * mult * t)
            out[i] += level * env * s
            n += 1

    # Gentle low-pass over the whole dry signal.
    a = one_pole_coeff(LOWPASS_HZ)
    y = 0.0
    for i in range(total_samples):
        y += a * (out[i] - y)
        out[i] = y
    return out


def plate_reverb(x: list, reverb_time: float, delay_scale: float, predelay: float) -> list:
    """Damped parallel combs -> series allpasses. Rings like a calm room."""
    n = len(x)
    if predelay > 0:
        pd = int(predelay * SR)
        x = [0.0] * pd + x[: n - pd]

    damp = one_pole_coeff(COMB_DAMP_HZ)
    summed = [0.0] * n
    for base_delay in COMB_DELAYS:
        d = max(1, int(base_delay * delay_scale * SR))
        g = 10.0 ** (-3.0 * (d / SR) / reverb_time)  # feedback for the wanted RT60
        buf = [0.0] * d
        lp = 0.0
        idx = 0
        for i in range(n):
            delayed = buf[idx]
            lp += damp * (delayed - lp)          # damping inside the loop:
            buf[idx] = x[i] + lp * g             # highs die faster, like air
            idx = (idx + 1) % d
            summed[i] += delayed
        # (parallel combs just sum)

    y = [s / len(COMB_DELAYS) for s in summed]
    for base_delay in ALLPASS_DELAYS:
        d = max(1, int(base_delay * delay_scale * SR))
        buf = [0.0] * d
        idx = 0
        for i in range(n):
            delayed = buf[idx]
            inp = y[i]
            buf[idx] = inp + delayed * ALLPASS_G
            y[i] = delayed - inp * ALLPASS_G
            idx = (idx + 1) % d
    return y


def render(freqs, total: float, reverb_time: float, wet: float, peak_dbfs: float):
    total_samples = int(total * SR)
    channels = []
    for detune, scale, predelay in (
        (-WIDTH_CENTS, 1.0, 0.0),                    # left
        (+WIDTH_CENTS, COMB_SCALE_R, WET_PREDELAY_R)  # right
    ):
        dry = render_notes(freqs, detune, total_samples)
        rev = plate_reverb(dry, reverb_time, scale, predelay)
        channels.append([d * (1.0 - wet) + r * wet for d, r in zip(dry, rev)])

    # Normalize to the target peak; conservative on purpose.
    peak = max(max(abs(s) for s in ch) for ch in channels)
    gain = (10.0 ** (peak_dbfs / 20.0)) / peak if peak > 0 else 0.0

    # Cosine fade over the last 80 ms guarantees true silence at the end.
    fade = int(0.08 * SR)
    for ch in channels:
        for i in range(total_samples):
            ch[i] *= gain
        for j in range(fade):
            ch[total_samples - fade + j] *= 0.5 + 0.5 * math.cos(math.pi * j / fade)
    return channels


def write_wav(path: Path, channels) -> None:
    frames = bytearray()
    for pair in zip(*channels):
        for s in pair:
            frames += struct.pack("<h", max(-32767, min(32767, int(round(s * 32767)))))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(len(channels))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--notes", nargs=2, type=float, default=[D5, A5],
                   metavar=("HZ1", "HZ2"), help="the two note frequencies in Hz")
    p.add_argument("--reverb-time", type=float, default=1.1,
                   help="RT60 of the plate tail, seconds")
    p.add_argument("--wet", type=float, default=0.5, help="reverb mix, 0..1")
    p.add_argument("--total", type=float, default=1.4, help="total length, seconds")
    p.add_argument("--peak-db", type=float, default=-12.0, help="peak level, dBFS")
    p.add_argument("--out", type=Path,
                   default=repo / "Oryne" / "Resources" / "OceanReceived.caf")
    p.add_argument("--wav-out", type=Path, default=None,
                   help="also keep the intermediate WAV here (for auditioning)")
    args = p.parse_args()

    if shutil.which("afconvert") is None:
        print("afconvert not found; this script needs macOS.", file=sys.stderr)
        return 1

    channels = render(args.notes, args.total, args.reverb_time, args.wet, args.peak_db)

    with tempfile.TemporaryDirectory() as tmp:
        wav = args.wav_out or Path(tmp) / "OceanReceived.wav"
        write_wav(wav, channels)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        # IMA4-in-CAF: ~4:1, decoded natively by AudioServicesPlaySystemSound.
        subprocess.run(
            ["afconvert", "-f", "caff", "-d", "ima4", str(wav), str(args.out)],
            check=True,
        )

    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size / 1024:.1f} KB)")
    if size > 100_000:
        print("warning: larger than the 100 KB budget", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

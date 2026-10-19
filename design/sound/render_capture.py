"""Renders Oryne's capture sound, Oryne/Resources/OceanReceived.caf, played by CaptureFeedback
when a thought is saved. Chosen by ear on 2026-10-19 after many listening rounds (design/sound/README.md).

Two layers, each with one job:
  "captured"      a landed note on Locant's Tock instrument (Locant/design/sound/render.swift):
                  a harmonic series falling as 1/n^1.4, upper harmonics dying faster, two voices
                  1.5 cents apart, an 8-cent settling glide, a 6 ms raised-cosine rise, never a
                  strike. On E4, Oryne's own pitch.
  "into the sea"  a quiet, even bed of a real recorded wave under the whole sound, 17 dB below
                  the note: "Waves On The Beach (Sand Wash)" by ralph.whitehead, Freesound 470648,
                  CC0, cut at 7:39.9, its fizz of draining water pulled down so the wave's roll
                  carries it.

usage (from the repo root, with the 214 MB source WAV downloaded from Freesound):
  python3 design/sound/render_capture.py <470648__ralphwhitehead__waves-on-the-beach-sand-wash.wav> [out.wav]
Without out.wav it writes Oryne/Resources/OceanReceived.caf. Needs numpy, scipy, ffmpeg, afconvert.
"""
import os, subprocess, sys, tempfile, wave
import numpy as np
from scipy import signal

RATE = 48000
SOURCE_ONSET = 459.9       # 7:39.9 into the recording: one clean wave, found by a scan of all 13 minutes
SOURCE_CORE = 1.13         # the wave itself, before lead-in and tail
NOTE_PITCH = 329.6         # E4
NOTE_LEVEL = -31.0         # phone-speaker level of the note (300 Hz to 6 kHz), dB
BED_UNDER = -17.0          # the wave bed, below the note
LENGTH = 0.45              # seconds


def phone_level(y):
    m = y.mean(1) if y.ndim > 1 else y
    power = np.abs(np.fft.rfft(m)) ** 2
    freq = np.fft.rfftfreq(len(m), 1 / RATE)
    return 10 * np.log10(power[(freq >= 300) & (freq < 6000)].sum() / len(m) ** 2 * 2)


def rbj(kind, f0, gain_db=0.0, q=0.707):
    """One RBJ-cookbook biquad as second-order sections."""
    a_ = 10 ** (gain_db / 40); w0 = 2 * np.pi * f0 / RATE; c, s = np.cos(w0), np.sin(w0); al = s / (2 * q)
    if kind == "peak":
        b = [1 + al * a_, -2 * c, 1 - al * a_]; a = [1 + al / a_, -2 * c, 1 - al / a_]
    elif kind in ("lowshelf", "highshelf"):
        sq = 2 * np.sqrt(a_) * al; sg = 1 if kind == "lowshelf" else -1
        b = [a_ * ((a_ + 1) - sg * (a_ - 1) * c + sq), sg * 2 * a_ * ((a_ - 1) - sg * (a_ + 1) * c), a_ * ((a_ + 1) - sg * (a_ - 1) * c - sq)]
        a = [(a_ + 1) + sg * (a_ - 1) * c + sq, -sg * 2 * ((a_ - 1) + sg * (a_ + 1) * c), (a_ + 1) + sg * (a_ - 1) * c - sq]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]; a = [1 + al, -2 * c, 1 - al]
    else:
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]; a = [1 + al, -2 * c, 1 - al]
    return signal.tf2sos(np.array(b) / a[0], np.array(a) / a[0])


# Less water, more wave: keep the body, lift the roll of the surge, pull down the fizz.
WAVE_EQ = np.vstack([rbj("hp", 70, q=0.6), rbj("peak", 340, +3.5, q=0.8), rbj("highshelf", 2200, -9.0, q=0.6),
                     rbj("peak", 4500, -3.0, q=1.0), rbj("lp", 7500, q=0.6)])


def quantize24(y):
    """Round-trip through 24-bit PCM, as the listening files did."""
    return np.round(np.clip(y, -1, 1) * 8388607) / 8388608.0


def cut_wave(source):
    lead, tail, pre = 0.08, 0.32, 1.0
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{SOURCE_ONSET - lead - pre:.3f}",
                          "-t", f"{lead + SOURCE_CORE + tail + pre:.3f}", "-i", source, "-ac", "2",
                          "-ar", str(RATE), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)
    y = signal.sosfilt(WAVE_EQ, x, axis=0)[int(pre * RATE):]
    m = np.sqrt(signal.sosfiltfilt(signal.butter(2, 6, fs=RATE, output="sos"), (y ** 2).mean(1)).clip(1e-12))
    y *= np.clip((m / m.max()) ** 0.45, 10 ** (-12 / 20), 1.0)[:, None]
    fi, fo = int(0.03 * RATE), int(0.30 * RATE)
    y[:fi] *= (0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi))[:, None]
    y[-fo:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo))[:, None]
    y *= 10 ** ((-33.0 - phone_level(y)) / 20)
    if np.abs(y).max() > 10 ** (-10 / 20):
        y *= 10 ** (-10 / 20) / np.abs(y).max()
    y = quantize24(y)
    # calmer still: soften what is left above 3 kHz
    return signal.sosfilt(signal.butter(2, 3200, fs=RATE, output="sos"), y, axis=0)


def bed(wave_):
    """The steadiest stretch of the wave, its slow envelope divided out: a background, not a crest."""
    env = np.sqrt(signal.sosfiltfilt(signal.butter(2, 6, fs=RATE, output="sos"), (wave_ ** 2).mean(1)).clip(1e-12))
    n = int(LENGTH * RATE); best = None
    for a in range(int(0.1 * RATE), len(wave_) - n - int(0.1 * RATE), int(0.01 * RATE)):
        e = 20 * np.log10(env[a:a + n]); spread = e.max() - e.min()
        if best is None or spread < best[0]:
            best = (spread, a)
    a = best[1]
    y = wave_[a:a + n].copy() * (np.median(env[a:a + n]) / env[a:a + n]).clip(0.5, 2.0)[:, None]
    fi, fo = int(0.02 * RATE), int(min(0.2, 0.4 * LENGTH) * RATE)
    y[:fi] *= (0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi))[:, None]
    y[-fo:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / (fo - 1)))[:, None]
    return y


def note(pitch, length=0.42, harmonics=6, tilt=1.4, shine=1.3, detune=1.5, glide=8, attack=0.006, decay=0.055):
    """Locant's Tock instrument (Locant/design/sound/render.swift), a touch longer."""
    n = int(length * RATE); t = np.arange(n) / RATE; y = np.zeros(n); d = 2 ** (detune / 1200)
    path = 2 ** (glide * np.exp(-t / 0.030) / 1200)
    rise = np.where(t < attack, 0.5 - 0.5 * np.cos(np.pi * t / attack), 1.0)
    for v in (1 / d, d):
        for k in range(1, harmonics + 1):
            y += (1 / k ** tilt / 2) * np.exp(-t / (decay / k ** shine)) * np.sin(2 * np.pi * np.cumsum(pitch * k * v * path) / RATE)
    k = int(0.08 * RATE); y[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / (k - 1))
    return y * rise


def render(source):
    n_ = note(NOTE_PITCH); n_ *= 10 ** ((NOTE_LEVEL - phone_level(n_)) / 20)
    b = bed(cut_wave(source)); b *= 10 ** ((NOTE_LEVEL + BED_UNDER - phone_level(b[:len(n_)])) / 20)
    mix = b.copy(); s = int(0.02 * RATE)
    mix[s:s + len(n_)] += n_[:, None] * np.array([0.98, 1.0])
    return mix


def write_wav24(path, y):
    pcm = (np.clip(y, -1, 1) * 8388607).astype(np.int32).reshape(-1).astype(np.uint32)
    b = np.empty((len(pcm), 3), dtype=np.uint8); b[:, 0] = pcm & 255; b[:, 1] = (pcm >> 8) & 255; b[:, 2] = (pcm >> 16) & 255
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(3); w.setframerate(RATE); w.writeframes(b.tobytes())


if __name__ == "__main__":
    mix = render(sys.argv[1])
    print(f"capture sound: {len(mix) / RATE * 1000:.0f} ms, peak {20 * np.log10(np.abs(mix).max()):.1f} dBFS, "
          f"phone-speaker level {phone_level(mix):.1f} dB")
    if len(sys.argv) > 2:
        write_wav24(sys.argv[2], mix)
    else:
        tmp = os.path.join(tempfile.mkdtemp(), "capture.wav"); write_wav24(tmp, mix)
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI24", tmp, "Oryne/Resources/OceanReceived.caf"], check=True)
        print("wrote Oryne/Resources/OceanReceived.caf")

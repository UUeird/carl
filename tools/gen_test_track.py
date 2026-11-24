#!/usr/bin/env python3
"""Generate the prototype's placeholder festival track + its beatmap.

Pure stdlib (no numpy): synthesizes a 128 BPM four-on-the-floor track with an
intro, groove, build, drop, breakdown, second build and a long "boss" drop, then
writes:

  assets/music/test_track.wav   (22.05 kHz mono 16-bit)
  assets/music/test_track.json  (beatmap: bpm, offset, sections)

The song structure is defined ONCE (SECTIONS below) and drives both the audio and
the beatmap, so they can't drift apart. Gameplay rules per section kind live in
CSGame.SECTION_RULES, not here — the beatmap only describes the music.

Usage: python3 tools/gen_test_track.py   (run from the repo root)
"""
import array
import json
import math
import os
import random
import wave

SR = 22050
BPM = 128
SPB = 60.0 / BPM  # seconds per beat

# (name, kind, length_in_beats). Kinds: intro, groove, build, drop, break, boss, outro.
SECTIONS = [
    ("Intro", "intro", 16),
    ("Groove", "groove", 32),
    ("Build", "build", 16),
    ("Drop 1", "drop", 48),
    ("Breakdown", "break", 16),
    ("Build 2", "build", 16),
    ("The Drop (boss)", "boss", 64),
    ("Outro", "outro", 16),
]

# Bass/chord roots per bar (A minor-ish: A F C G).
ROOTS = [55.0, 43.65, 65.41, 49.0]

random.seed(7)
TOTAL_BEATS = sum(s[2] for s in SECTIONS)
N = int(TOTAL_BEATS * SPB * SR) + SR  # +1s tail
buf = array.array("f", [0.0]) * N


def add(start_s, samples, gain=1.0):
    i0 = int(start_s * SR)
    for i, v in enumerate(samples):
        j = i0 + i
        if 0 <= j < N:
            buf[j] += v * gain


def kick():
    out, phase = [], 0.0
    for i in range(int(0.32 * SR)):
        t = i / SR
        f = 50 + 110 * math.exp(-t * 28)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-t * 9))
    return out


def noise_hit(length, decay, highpass=False):
    out, prev = [], 0.0
    for i in range(int(length * SR)):
        n = random.uniform(-1, 1)
        v = (n - prev) if highpass else n
        prev = n
        out.append(v * math.exp(-(i / SR) * decay))
    return out


def stab(freq, length=0.18):
    out = []
    for i in range(int(length * SR)):
        t = i / SR
        env = math.exp(-t * 14)
        v = 0.0
        for mult in (1.0, 1.1892, 1.4983):  # minor triad
            v += 1.0 if math.sin(2 * math.pi * freq * 4 * mult * t) > 0 else -1.0
        out.append(v / 3 * env)
    return out


KICK = kick()
CLAP = noise_hit(0.16, 22)
HAT = noise_hit(0.05, 70, highpass=True)
OPEN_HAT = noise_hit(0.16, 18, highpass=True)

beatmap_sections = []
beat0 = 0
for name, kind, length in SECTIONS:
    beatmap_sections.append({"name": name, "kind": kind, "start": beat0, "end": beat0 + length})
    for b in range(beat0, beat0 + length):
        t = b * SPB
        rel = b - beat0
        bar = b // 4
        root = ROOTS[bar % 4]
        full = kind in ("drop", "boss")
        # Kick: everywhere except the breakdown (and the last bar of builds = tension gap).
        if kind != "break" and not (kind == "build" and rel >= length - 2):
            add(t, KICK, 0.9 if full else 0.75)
        # Hats on the offbeat.
        if kind in ("groove", "drop", "boss", "build", "outro"):
            add(t + SPB / 2, OPEN_HAT if full else HAT, 0.25 if full else 0.18)
        if full:
            add(t + SPB / 4, HAT, 0.12)
            add(t + 3 * SPB / 4, HAT, 0.12)
        # Clap on 2 and 4.
        if kind in ("groove", "drop", "boss") and b % 2 == 1:
            add(t, CLAP, 0.35)
        # Build: snare roll that accelerates (1/4 -> 1/8 -> 1/16).
        if kind == "build":
            div = 1 if rel < length / 2 else (2 if rel < length * 3 / 4 else 4)
            for k in range(div):
                add(t + k * SPB / div, CLAP, 0.15 + 0.3 * rel / length)
        # Lead stabs in drops on the "and" of 1 and 3.
        if full and b % 2 == 0:
            add(t + SPB * 0.75, stab(root), 0.16 if kind == "drop" else 0.2)
    beat0 += length

# Sustained layers, sample by sample: pumping offbeat bass, breakdown pad, build riser.
sec_at_beat = []
for s in beatmap_sections:
    sec_at_beat += [s] * (s["end"] - s["start"])
for i in range(int(TOTAL_BEATS * SPB * SR)):
    t = i / SR
    beat = t / SPB
    b = int(beat)
    s = sec_at_beat[b]
    kind = s["kind"]
    root = ROOTS[(b // 4) % 4]
    frac = beat - b
    v = 0.0
    if kind in ("groove", "drop", "boss", "outro"):
        # Offbeat bass: sidechain-style pump, silent on the kick.
        pump = max(0.0, math.sin(math.pi * frac)) ** 2
        saw = 2 * ((root * t) % 1.0) - 1
        v += saw * pump * (0.28 if kind in ("drop", "boss") else 0.2)
    if kind == "break":
        p = (beat - s["start"]) / (s["end"] - s["start"])
        for mult in (2.0, 2.378, 2.997, 4.0):
            v += math.sin(2 * math.pi * root * mult * t) * 0.06 * math.sin(math.pi * p)
    if kind == "build":
        p = (beat - s["start"]) / (s["end"] - s["start"])
        f = 200 + 1600 * p * p
        v += math.sin(2 * math.pi * f * t) * 0.05 * p + random.uniform(-1, 1) * 0.08 * p * p
    buf[i] += v

# Soft clip + normalize to 16-bit.
peak = max(abs(x) for x in buf) or 1.0
pcm = array.array("h", (int(math.tanh(x / peak * 1.4) * 0.92 * 32767) for x in buf))

root_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "music")
os.makedirs(root_dir, exist_ok=True)
with wave.open(os.path.join(root_dir, "test_track.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
with open(os.path.join(root_dir, "test_track.json"), "w") as f:
    json.dump({
        "title": "Placeholder Festival Track",
        "artist": "carl tools/gen_test_track.py",
        "bpm": BPM,
        "offset": 0.0,
        "length_beats": TOTAL_BEATS,
        "sections": beatmap_sections,
    }, f, indent=2)
print("wrote %d beats (%.1fs)" % (TOTAL_BEATS, TOTAL_BEATS * SPB))

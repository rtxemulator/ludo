#!/usr/bin/env python3
"""Synthesizes every Ludo sound effect and the ambient music loop.

Plain Python 3 with the standard library only (`wave`, `math`, `random`,
`array`), plus the `opusenc` command line encoder (Termux: `pkg install
opus-tools`; Debian/Ubuntu: `apt install opus-tools`). Nothing is sampled
from anywhere: every sound is built from oscillators, noise and envelopes,
and every random draw uses a fixed seed, so the same script always makes the
same audio (docs/ludo-sound-themes.md sections 2 and 3).

Usage (from the repository root):

    python3 tool/audio/generate.py                 # all sounds + music
    python3 tool/audio/generate.py --only capture  # one sound (or "music")
    python3 tool/audio/generate.py --keep-wav /tmp/wavs   # keep the WAVs too
    python3 tool/audio/generate.py --out some/dir  # other output directory

Output: `app/assets/audio/<SfxEvent name>.opus` for the ten effects (mono,
48 kHz, 48 kbps VBR) and `music.opus` (stereo, 48 kHz, 64 kbps constrained VBR,
60 s seamless loop). Every
effect is normalised to the same loudness (-16 LUFS over its active part,
peak below -1 dBFS); the music loop has the same loudness over the whole
loop and is played about 6 dB lower by `AudioService`.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import subprocess
import sys
import tempfile
import wave
import zlib
from array import array

SR = 48000
TARGET_LUFS = -16.0
CEILING_DBFS = -1.0
BUDGET_BYTES = 600 * 1024

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "app", "assets", "audio"))


# ---- Small helpers ---------------------------------------------------------


def ms(x: float) -> int:
    """Milliseconds to samples at SR."""
    return int(round(x * SR / 1000.0))


def zeros(n: int) -> array:
    return array("d", bytes(8 * n))


def add(dst: array, src, at_ms: float = 0.0, gain: float = 1.0) -> None:
    """Mixes [src] into [dst] starting at [at_ms] (clipped to dst's length)."""
    off = ms(at_ms)
    for i in range(min(len(src), len(dst) - off)):
        dst[off + i] += src[i] * gain


def rms(buf) -> float:
    if len(buf) == 0:
        return 0.0
    return math.sqrt(sum(v * v for v in buf) / len(buf))


def rescale_rms(buf: array, target: float) -> None:
    r = rms(buf)
    if r > 0:
        g = target / r
        for i in range(len(buf)):
            buf[i] *= g


def modal(parts, dur_ms: float, pitch: float = 1.0) -> array:
    """Sum of exponentially decaying sines: parts are (Hz, amp, tau ms)."""
    n = ms(dur_ms)
    out = zeros(n)
    for freq, amp, tau in parts:
        w = 2 * math.pi * freq * pitch / SR
        k = math.exp(-1000.0 / (tau * SR))
        a = amp
        for i in range(n):
            out[i] += a * math.sin(w * i)
            a *= k
    return out


def noise(rng: random.Random, dur_ms: float, tau_ms: float, lp_hz: float) -> array:
    """A decaying burst of low-passed white noise (the click of a hit)."""
    n = ms(dur_ms)
    out = zeros(n)
    a = 1 - math.exp(-2 * math.pi * lp_hz / SR)
    k = math.exp(-1000.0 / (tau_ms * SR))
    y = 0.0
    amp = 1.0
    for i in range(n):
        y += a * (rng.uniform(-1, 1) - y)
        out[i] = y * amp
        amp *= k
    return out


def whoosh(rng: random.Random, dur_ms: float, f_start: float, f_end: float) -> array:
    """Noise through a two-pole low-pass that sweeps down from f_start to f_end."""
    n = ms(dur_ms)
    out = zeros(n)
    y1 = y2 = 0.0
    attack = max(1, ms(8))
    for i in range(n):
        u = i / n
        fc = f_start * (f_end / f_start) ** u
        a = 1 - math.exp(-2 * math.pi * fc / SR)
        y1 += a * (rng.uniform(-1, 1) - y1)
        y2 += a * (y1 - y2)
        env = min(1.0, i / attack) * (1 - u) ** 1.5
        out[i] = y2 * env
    return out


BELL = ((1.0, 1.0, 1.0), (2.0, 0.30, 0.6), (3.01, 0.10, 0.4))
BRIGHT_BELL = ((1.0, 1.0, 1.0), (2.0, 0.45, 0.6), (3.01, 0.22, 0.45), (4.2, 0.08, 0.3))


def bell(freq: float, dur_ms: float, tau_ms: float, partials=BELL, attack_ms: float = 2.0) -> array:
    n = ms(dur_ms)
    out = zeros(n)
    att = max(1, ms(attack_ms))
    for ratio, amp, dscale in partials:
        w = 2 * math.pi * freq * ratio / SR
        k = math.exp(-1000.0 / (tau_ms * dscale * SR))
        a = amp
        for i in range(n):
            out[i] += (a if i >= att else a * i / att) * math.sin(w * i)
            a *= k
    return out


HORN = (1.0, 0.5, 0.33, 0.2, 0.12, 0.07)


def horn(freq: float, dur_ms: float, attack_ms: float, release_ms: float, tau_ms: float) -> array:
    """A soft brassy note: a few harmonics, linear attack and release."""
    n = ms(dur_ms)
    out = zeros(n)
    att = max(1, ms(attack_ms))
    rel = max(1, ms(release_ms))
    k = math.exp(-1000.0 / (tau_ms * SR))
    env = 1.0
    ws = [2 * math.pi * freq * (h + 1) / SR for h in range(len(HORN))]
    for i in range(n):
        g = env
        if i < att:
            g *= i / att
        if i > n - rel:
            g *= (n - i) / rel
        s = 0.0
        for h, w in enumerate(ws):
            s += HORN[h] * math.sin(w * i)
        out[i] = s * g
        env *= k
    return out


# ---- The ten effects -------------------------------------------------------
# Durations follow docs/ludo-sound-themes.md section 2 (the dice roll spans
# its three bounces, 0 / 230 / 380 ms after the first, so it is a bit longer
# than the "about 380 ms" of the table).


def knock(rng: random.Random, dur_ms: float, pitch: float = 1.0, bright: float = 1.0) -> array:
    body = modal([(210, 1.0, 26), (430, 0.55, 16), (790, 0.30, 9), (1380, 0.14, 5)], dur_ms, pitch)
    add(body, noise(rng, 6, 1.2, 4500 * bright), 0, 0.5)
    return body


def fx_dice_roll(rng: random.Random) -> array:
    out = zeros(ms(470))
    add(out, knock(rng, 170, 1.0, 1.0), 0, 1.0)
    add(out, knock(rng, 160, 0.94, 0.9), 230, 0.65)
    add(out, knock(rng, 90, 1.07, 0.8), 380, 0.38)
    return out


def fx_dice_settle(rng: random.Random) -> array:
    out = modal([(1250, 1.0, 9), (2300, 0.4, 5), (620, 0.7, 14)], 100)
    add(out, noise(rng, 4, 1.0, 6000), 0, 0.8)
    return out


def fx_hop(rng: random.Random) -> array:
    out = modal([(540, 1.0, 14), (1080, 0.35, 8), (1620, 0.12, 5)], 70)
    ramp = ms(1.5)
    for i in range(ramp):
        out[i] *= i / ramp
    add(out, noise(rng, 3, 1.0, 2500), 0, 0.15)
    return out


def fx_land(rng: random.Random) -> array:
    out = modal([(190, 1.0, 34), (380, 0.45, 20), (720, 0.18, 9)], 120)
    add(out, noise(rng, 5, 1.5, 1800), 0, 0.35)
    return out


def fx_capture(rng: random.Random) -> array:
    out = modal([(95, 1.0, 70), (190, 0.6, 45), (410, 0.35, 22), (870, 0.18, 10)], 350)
    add(out, noise(rng, 6, 1.2, 3500), 0, 0.6)
    sweep = whoosh(rng, 300, 1600, 260)
    rescale_rms(sweep, 0.16)
    add(out, sweep, 40, 1.0)
    return out


def fx_home(rng: random.Random) -> array:
    out = zeros(ms(520))
    add(out, bell(523.25, 520, 110), 0, 1.0)
    add(out, bell(659.25, 410, 105), 110, 0.95)
    add(out, bell(783.99, 300, 95), 220, 0.9)
    return out


def fx_six(rng: random.Random) -> array:
    out = zeros(ms(260))
    add(out, bell(783.99, 260, 85, BRIGHT_BELL), 0, 1.0)
    add(out, bell(1046.5, 170, 65, BRIGHT_BELL), 90, 0.9)
    return out


def fx_win(rng: random.Random) -> array:
    out = zeros(ms(1800))
    for i, f in enumerate((261.63, 329.63, 392.0, 523.25)):
        add(out, horn(f, 340, 18, 90, 400), 130 * i, 0.45)
    for f in (130.81, 261.63, 329.63, 392.0, 523.25, 659.25):
        add(out, horn(f, 1240, 25, 450, 700), 560, 0.28)
    return out


def fx_illegal(rng: random.Random) -> array:
    out = zeros(ms(160))
    for at, pitch, gain in ((0, 1.0, 1.0), (75, 0.85, 0.9)):
        tick = modal([(160, 1.0, 22), (300, 0.4, 12)], 80, pitch)
        add(tick, noise(rng, 3, 1.0, 1200), 0, 0.3)
        add(out, tick, at, gain)
    return out


def fx_select(rng: random.Random) -> array:
    out = modal([(2400, 1.0, 7), (3600, 0.3, 4)], 40)
    add(out, noise(rng, 2, 0.8, 7000), 0, 0.3)
    return out


EFFECTS = {
    "diceRoll": fx_dice_roll,
    "diceSettle": fx_dice_settle,
    "hop": fx_hop,
    "land": fx_land,
    "capture": fx_capture,
    "home": fx_home,
    "six": fx_six,
    "win": fx_win,
    "illegal": fx_illegal,
    "select": fx_select,
}


# ---- The ambient loop ------------------------------------------------------
# Four soft chords (C maj7, A m, F maj7, G 6/9) of 15 s each crossfade in a
# circle, so the end of the loop flows into its start. Every oscillator has a
# whole number of cycles per loop and the sparse bell notes wrap around the
# end, so the loop is seamless before encoding. It is synthesized at 16 kHz
# (nothing in it needs more) and brought up to 48 kHz by linear interpolation.

MUSIC_SR = 16000
MUSIC_SECONDS = 60
MUSIC_UP = SR // MUSIC_SR
CHORD_SECONDS = 15
CHORDS = (
    (130.81, 196.00, 329.63, 493.88),  # C3 G3 E4 B4
    (110.00, 164.81, 261.63, 392.00),  # A2 E3 C4 G4
    (87.31, 130.81, 220.00, 329.63),  # F2 C3 A3 E4
    (98.00, 146.83, 246.94, 329.63),  # G2 D3 B3 E4
)
VOICE_GAIN = (1.0, 0.8, 0.7, 0.5)
PENTATONIC = (523.25, 587.33, 659.25, 783.99, 880.0, 1046.5)


def make_music(log) -> tuple[array, array]:
    n = MUSIC_SR * MUSIC_SECONDS
    left = zeros(n)
    right = zeros(n)
    two_pi = 2 * math.pi
    for c, freqs in enumerate(CHORDS):
        centre = (c + 0.5) * CHORD_SECONDS
        start = int((centre - CHORD_SECONDS) * MUSIC_SR)
        end = int((centre + CHORD_SECONDS) * MUSIC_SR)
        seg = end - start
        stem_l = zeros(seg)
        stem_r = zeros(seg)
        for v, f in enumerate(freqs):
            for side, detune in ((0, 7 + v), (1, -(7 + v))):
                cycles = round(f * MUSIC_SECONDS) + detune
                w = two_pi * cycles / n
                vals = [math.sin(w * i) + 0.22 * math.sin(2 * w * i) for i in range(start, end)]
                gl, gr = (0.7, 0.3) if side == 0 else (0.3, 0.7)
                g = VOICE_GAIN[v] * 0.25
                for i in range(seg):
                    x = vals[i] * g
                    stem_l[i] += x * gl
                    stem_r[i] += x * gr
            log(f"  chord {c + 1}/4 voice {v + 1}/4")
        # Window: partition of unity between neighbouring chords.
        for i in range(seg):
            d = abs((start + i) / MUSIC_SR - centre)
            w = math.cos(math.pi * d / (2 * CHORD_SECONDS)) ** 2
            j = (start + i) % n
            left[j] += stem_l[i] * w
            right[j] += stem_r[i] * w
    # Sparse soft bell notes, wrapping around the end of the loop.
    rng = random.Random(20261104)
    count = 14
    for k in range(count):
        at = (k + 0.5) * MUSIC_SECONDS / count + rng.uniform(-1.2, 1.2)
        freq = rng.choice(PENTATONIC)
        pan = rng.uniform(0.2, 0.8)
        length = 4 * MUSIC_SR
        att = int(0.03 * MUSIC_SR)
        w = two_pi * freq / MUSIC_SR
        base = int(at * MUSIC_SR)
        for i in range(length):
            env = math.exp(-i / (1.1 * MUSIC_SR)) * (i / att if i < att else 1.0)
            s = 0.07 * env * (math.sin(w * i) + 0.25 * math.sin(2.01 * w * i))
            j = (base + i) % n
            left[j] += s * (1 - pan)
            right[j] += s * pan
    return upsample(left), upsample(right)


def upsample(x: array) -> array:
    """Linear interpolation by MUSIC_UP, wrapping at the end (it is a loop)."""
    n = len(x)
    out = zeros(n * MUSIC_UP)
    for i in range(n):
        a = x[i]
        b = x[(i + 1) % n]
        for u in range(MUSIC_UP):
            out[i * MUSIC_UP + u] = a + (b - a) * u / MUSIC_UP
    return out


# ---- Loudness (ITU-R BS.1770 K-weighting at 48 kHz) -------------------------

_K1 = (1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585)
_K2 = (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)


def _biquad(x, c) -> array:
    b0, b1, b2, a1, a2 = c
    x1 = x2 = y1 = y2 = 0.0
    out = zeros(len(x))
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y
        x2, x1 = x1, v
        y2, y1 = y1, y
    return out


def loudness(channels, active_only: bool) -> float:
    """LUFS of the (K-weighted) channels. With [active_only], only the 10 ms
    blocks within 30 dB of the loudest one count, so a click or a note is
    measured over its sound and not over its silence."""
    weighted = [_biquad(_biquad(ch, _K1), _K2) for ch in channels]
    n = len(weighted[0])
    block = ms(10)
    energies = []
    for s in range(0, n, block):
        e = 0.0
        for ch in weighted:
            e += sum(v * v for v in ch[s:s + block])
        energies.append((e, min(block, n - s)))
    if active_only:
        top = max(e / m for e, m in energies)
        energies = [(e, m) for e, m in energies if e / m >= top * 1e-3]
    total = sum(e for e, _ in energies)
    count = sum(m for _, m in energies)
    return -0.691 + 10 * math.log10(max(total / count, 1e-12))


def soft_limit(v: float, knee: float, ceiling: float) -> float:
    a = abs(v)
    if a <= knee:
        return v
    y = knee + (ceiling - knee) * math.tanh((a - knee) / (ceiling - knee))
    return y if v > 0 else -y


def finish(channels, active_only: bool):
    """Normalises to TARGET_LUFS, limits the peaks below CEILING_DBFS and
    fades the last 3 ms to zero. Returns (channels, lufs, peak dBFS)."""
    lufs = loudness(channels, active_only)
    gain = 10 ** ((TARGET_LUFS - lufs) / 20)
    ceiling = 10 ** (CEILING_DBFS / 20)
    out = []
    for ch in channels:
        scaled = array("d", (soft_limit(v * gain, 0.6, ceiling) for v in ch))
        tail = ms(3)
        for i in range(tail):
            scaled[len(scaled) - 1 - i] *= i / tail
        out.append(scaled)
    peak = max(max(abs(v) for v in ch) for ch in out)
    return out, loudness(out, active_only), 20 * math.log10(max(peak, 1e-9))


# ---- Files -----------------------------------------------------------------


def write_wav(path: str, channels) -> None:
    pcm = array("h", bytes(2 * len(channels[0]) * len(channels)))
    for c, ch in enumerate(channels):
        pcm[c::len(channels)] = array(
            "h", (max(-32768, min(32767, int(round(v * 32767)))) for v in ch)
        )
    if sys.byteorder == "big":
        pcm.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(len(channels))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode(wav: str, out: str, kbps: int, constrained: bool) -> None:
    """Encodes with opusenc. The music uses constrained VBR so its size stays
    at the target bitrate (plain VBR overshoots on dense pads); the short
    effects use plain VBR. A fixed serial number keeps the files stable."""
    mode = "--cvbr" if constrained else "--vbr"
    subprocess.run(
        ["opusenc", "--quiet", mode, "--bitrate", str(kbps), "--comp", "10", "--serial", "1", wav, out],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=DEFAULT_OUT, help="output directory")
    parser.add_argument("--only", help="one effect name, or 'music'")
    parser.add_argument("--keep-wav", metavar="DIR", help="also keep the WAV files here")
    args = parser.parse_args()

    names = list(EFFECTS) + ["music"]
    if args.only:
        if args.only not in names:
            parser.error(f"unknown sound {args.only!r}; one of: {', '.join(names)}")
        names = [args.only]
    os.makedirs(args.out, exist_ok=True)
    if args.keep_wav:
        os.makedirs(args.keep_wav, exist_ok=True)

    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            print(f"{name} ...", flush=True)
            if name == "music":
                raw = list(make_music(lambda s: print(s, flush=True)))
                chans, lufs, peak = finish(raw, active_only=False)
                kbps = 64
                constrained = True
            else:
                rng = random.Random(zlib.crc32(name.encode()))
                raw = [EFFECTS[name](rng)]
                chans, lufs, peak = finish(raw, active_only=True)
                kbps = 48
                constrained = False
            wav = os.path.join(args.keep_wav or tmp, f"{name}.wav")
            write_wav(wav, chans)
            dest = os.path.join(args.out, f"{name}.opus")
            encode(wav, dest, kbps, constrained)
            rows.append((name, len(chans[0]) * 1000.0 / SR, os.path.getsize(dest), lufs, peak))

    print()
    print(f"{'file':<16}{'duration':>10}{'size':>10}{'LUFS':>8}{'peak':>8}")
    for name, dur, size, lufs, peak in rows:
        print(f"{name + '.opus':<16}{dur:>8.0f}ms{size:>9}B{lufs:>8.1f}{peak:>7.1f}")
    total = sum(r[2] for r in rows)
    print(f"total {total} B ({total / 1024:.1f} KB of {BUDGET_BYTES // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

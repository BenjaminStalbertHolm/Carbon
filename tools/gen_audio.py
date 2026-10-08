"""Generate every sound in spec section 11.3 and the ambient beds in 11.2 into
assets/audio/ as 44.1 kHz, 16-bit, mono WAV.

Run from any directory:
    python3 tools/gen_audio.py

Determinism: each file draws noise from its own RNG seeded from (412, name).

Conventions used throughout (spec 11.3 wording is applied as written unless
noted here):
- "Noise a-b kHz" is white noise through a 4th-order Butterworth band-pass
  (scipy butter(4, ...)). Circular (FFT-domain) filters are used wherever a
  file must loop seamlessly.
- "Decay tau" is exp(-t/tau). "Attack a ms" is a linear rise over a ms, then
  the decay starts at the end of the attack (attack_decay()).
- One-shots get a 1 ms linear fade-in (unless an attack is given) and a 5 ms
  fade-out. Peaks are normalised to the dBFS value in the table.
- Ambient beds are normalised to their RMS level instead (spec 11.2 "Level").
- Sweeps (tube, door, whoosh) interpolate the centre frequency in log-Hz.
- Choices the spec leaves open are listed in QUESTIONS.md.
"""

from __future__ import annotations

import wave
import zlib
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SEED = 412
FS = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "audio"


# --- helpers -----------------------------------------------------------------


def ms(value: float) -> int:
    return int(round(value * FS / 1000.0))


def t_of(n: int) -> np.ndarray:
    return np.arange(n) / FS


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(np.random.SeedSequence([SEED, zlib.crc32(name.encode("ascii"))]))


def white(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.standard_normal(n)


def unit(x: np.ndarray) -> np.ndarray:
    peak = np.max(np.abs(x))
    return x / peak if peak > 0 else x


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 4) -> np.ndarray:
    sos = butter(order, [lo, hi], btype="bandpass", fs=FS, output="sos")
    return sosfilt(sos, x)


def lowpass(x: np.ndarray, fc: float, order: int = 4) -> np.ndarray:
    sos = butter(order, fc, btype="lowpass", fs=FS, output="sos")
    return sosfilt(sos, x)


def attack_decay(t: np.ndarray, attack_s: float, decay_s: float) -> np.ndarray:
    return np.minimum(1.0, t / attack_s) * np.exp(-np.maximum(0.0, t - attack_s) / decay_s)


def one_shot(x: np.ndarray, attack_ms: float = 1.0, release_ms: float = 5.0) -> np.ndarray:
    n = len(x)
    idx = np.arange(n)
    env = np.ones(n)
    if attack_ms > 0:
        env = np.minimum(1.0, idx / max(1, ms(attack_ms)))
    env *= np.clip((n - 1 - idx) / ms(release_ms), 0.0, 1.0)
    return x * env


def finish_peak(x: np.ndarray, peak_dbfs: float) -> np.ndarray:
    return x * (10 ** (peak_dbfs / 20.0) / np.max(np.abs(x)))


def finish_rms(x: np.ndarray, rms_dbfs: float) -> np.ndarray:
    rms = np.sqrt(np.mean(x**2))
    return x * (10 ** (rms_dbfs / 20.0) / rms)


def log_sweep(n: int, points: list[tuple[float, float]]) -> np.ndarray:
    """Centre frequency per sample, interpolated in log-Hz between points.

    Each point is (position as fraction of n, frequency in Hz).
    """
    xs = np.array([p[0] for p in points]) * (n - 1)
    ys = np.log(np.array([p[1] for p in points]))
    return np.exp(np.interp(np.arange(n), xs, ys))


def rbj_bandpass(fc: float, q: float) -> tuple[np.ndarray, np.ndarray]:
    w0 = 2.0 * np.pi * fc / FS
    alpha = np.sin(w0) / (2.0 * q)
    b = np.array([alpha, 0.0, -alpha])
    a = np.array([1.0 + alpha, -2.0 * np.cos(w0), 1.0 - alpha])
    return b / a[0], a / a[0]


def swept_bandpass(x: np.ndarray, centre_hz: np.ndarray, q: float, block: int = 32) -> np.ndarray:
    """Band-pass with a centre frequency that changes every block (state carried over)."""
    out = np.empty_like(x)
    zi = np.zeros(2)
    for start in range(0, len(x), block):
        end = min(start + block, len(x))
        b, a = rbj_bandpass(float(centre_hz[(start + end) // 2]), q)
        y, zi = lfilter(b, a, x[start:end], zi=zi)
        out[start:end] = y
    return out


def butter_mag(f: np.ndarray, fc: float, order: int, kind: str) -> np.ndarray:
    if kind == "lp":
        return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    safe = np.where(f > 0, f, 1e-12)
    return 1.0 / np.sqrt(1.0 + (fc / safe) ** (2 * order))


def periodic_filter(x: np.ndarray, shape) -> np.ndarray:
    """FFT-domain filter. Output is exactly periodic over len(x) samples."""
    spectrum = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), d=1.0 / FS)
    return np.fft.irfft(spectrum * shape(f), len(x))


def circular_bandpass(x: np.ndarray, lo: float, hi: float, order: int = 4) -> np.ndarray:
    return periodic_filter(x, lambda f: butter_mag(f, lo, order, "hp") * butter_mag(f, hi, order, "lp"))


def paper_flutter(rng: np.random.Generator, n: int) -> np.ndarray:
    """1 + 0.4 * random-walk sampled at 30 Hz, linearly interpolated (spec 11.3 paper)."""
    nodes = int(np.ceil(n / FS * 30.0)) + 2
    walk = np.cumsum(rng.standard_normal(nodes))
    walk /= np.max(np.abs(walk))
    pos = np.arange(n) / FS * 30.0
    return 1.0 + 0.4 * np.interp(pos, np.arange(nodes), walk)


def paper_burst(rng: np.random.Generator, n: int) -> np.ndarray:
    noise = unit(bandpass(white(rng, n), 1000.0, 4000.0))
    return noise * np.hanning(n) * paper_flutter(rng, n)


# --- one-shot sounds ---------------------------------------------------------


def key_clack(variant: int) -> np.ndarray:
    rng = rng_for(f"key_clack_{variant}")
    n = ms(40)
    t = t_of(n)
    impulse = np.zeros(n)
    impulse[0] = 1.0
    noise = unit(bandpass(white(rng, n), 2000.0, 6000.0)) * np.exp(-t / 0.006)
    tone = 0.5 * np.sin(2 * np.pi * 120.0 * t) * np.exp(-t / 0.004)
    # The impulse is the transient itself, so it is added after the fade-in.
    return impulse + one_shot(noise + tone)


def carriage_return() -> np.ndarray:
    rng = rng_for("carriage_return")
    n = ms(500)
    x = np.zeros(n)
    click_n = ms(4)
    tc = t_of(click_n)
    for i in range(8):
        click = unit(bandpass(white(rng, click_n), 3000.0, 7000.0)) * np.exp(-tc / 0.001)
        start = ms(25 * i)
        x[start : start + click_n] += click
    slide_n = ms(250)
    slide = unit(bandpass(white(rng, slide_n), 400.0, 1500.0)) * np.linspace(1.0, 0.0, slide_n)
    start = ms(200)
    x[start : start + slide_n] += slide * 10 ** (-8 / 20)
    return one_shot(x)


def bell() -> np.ndarray:
    n = ms(1400)
    t = t_of(n)
    tone = np.sin(2 * np.pi * 2093.0 * t) + 0.5 * np.sin(2 * np.pi * 2810.0 * t) + 0.15 * np.sin(2 * np.pi * 5230.0 * t)
    return one_shot(tone * attack_decay(t, 0.002, 0.45), attack_ms=0.0)


def backspace_click() -> np.ndarray:
    rng = rng_for("backspace_click")
    n = ms(12)
    t = t_of(n)
    return one_shot(unit(bandpass(white(rng, n), 2000.0, 5000.0)) * np.exp(-t / 0.003))


def platen_ratchet() -> np.ndarray:
    rng = rng_for("platen_ratchet")
    n = ms(70)
    click_n = ms(3)
    tc = t_of(click_n)
    x = np.zeros(n)
    for offset in (0, 18, 36):
        click = unit(bandpass(white(rng, click_n), 3000.0, 6000.0)) * np.exp(-tc / 0.001)
        start = ms(offset)
        x[start : start + click_n] += click
    return one_shot(x)


def key_jam() -> np.ndarray:
    rng = rng_for("key_jam")
    n = ms(60)
    t = t_of(n)
    body = np.sin(2 * np.pi * 90.0 * t) * np.exp(-t / 0.02)
    body += unit(bandpass(white(rng, n), 1000.0, 3000.0)) * np.exp(-t / 0.01)
    return one_shot(body)


def paper_in() -> np.ndarray:
    return one_shot(paper_burst(rng_for("paper_in"), ms(600)))


def paper_out() -> np.ndarray:
    # Spec says "reversed envelope (fast rise, slow fall)". A Hann window is
    # symmetric, so the envelope here is an explicit fast-rise/slow-fall shape.
    rng = rng_for("paper_out")
    n = ms(600)
    t = t_of(n)
    rise_s = 0.05
    fall = np.cos(np.pi / 2.0 * (t - rise_s) / (0.6 - rise_s)) ** 2
    env = np.where(t < rise_s, t / rise_s, fall)
    noise = unit(bandpass(white(rng, n), 1000.0, 4000.0))
    return one_shot(noise * env * paper_flutter(rng, n))


def paper_shuffle() -> np.ndarray:
    rng = rng_for("paper_shuffle")
    burst_n = ms(180)
    gap_n = ms(30)
    x = np.zeros(ms(600))
    for k in range(3):
        start = k * (burst_n + gap_n)
        x[start : start + burst_n] += paper_burst(rng, burst_n)
    return one_shot(x)


def page_turn() -> np.ndarray:
    rng = rng_for("page_turn")
    n = ms(350)
    noise = unit(bandpass(white(rng, n), 1500.0, 5000.0))
    return one_shot(noise * np.hanning(n))


def stamp_thud() -> np.ndarray:
    rng = rng_for("stamp_thud")
    n = ms(150)
    t = t_of(n)
    body = np.sin(2 * np.pi * 80.0 * t) * np.exp(-t / 0.04)
    body += unit(bandpass(white(rng, n), 200.0, 800.0)) * np.exp(-t / 0.025)
    return one_shot(body)


def marker_stroke() -> np.ndarray:
    # Seamless 400 ms loop: periodic noise, and a sine whose phase returns to
    # its start after exactly 360 cycles. The 20 jitter steps are mean-centred
    # so the loop keeps 900 Hz on average and the phase closes exactly.
    rng = rng_for("marker_stroke")
    n = ms(400)
    noise = unit(circular_bandpass(white(rng, n), 3000.0, 6000.0)) * 10 ** (-6 / 20)
    step_n = ms(20)
    jitter = rng.uniform(-40.0, 40.0, size=n // step_n)
    jitter -= jitter.mean()
    freq = 900.0 + np.repeat(jitter, step_n)
    phase = 2.0 * np.pi * (np.cumsum(freq) - freq) / FS
    return noise + np.sin(phase)


def fluid_brush() -> np.ndarray:
    rng = rng_for("fluid_brush")
    n = ms(300)
    noise = unit(bandpass(white(rng, n), 2000.0, 5000.0))
    return one_shot(noise * np.hanning(n))


def tube_send() -> np.ndarray:
    rng = rng_for("tube_send")
    n = ms(800)
    centre = log_sweep(n, [(0.0, 300.0), (0.5, 1500.0), (1.0, 600.0)])
    noise = unit(swept_bandpass(white(rng, n), centre, q=2.0))
    return one_shot(noise * np.hanning(n))


def tube_arrive_whoosh() -> np.ndarray:
    rng = rng_for("tube_arrive_whoosh")
    n = ms(1000)
    centre = log_sweep(n, [(0.0, 200.0), (1.0, 1200.0)])
    noise = unit(swept_bandpass(white(rng, n), centre, q=2.0))
    return one_shot(noise * np.linspace(0.0, 1.0, n))


def tube_thunk() -> np.ndarray:
    n = ms(400)
    t = t_of(n)
    body = np.sin(2 * np.pi * 60.0 * t) * np.exp(-t / 0.08)
    body += np.sin(2 * np.pi * 180.0 * t) * np.exp(-t / 0.08)
    body += 10 ** (-12 / 20) * np.sin(2 * np.pi * 1100.0 * t) * np.exp(-t / 0.15)
    return one_shot(body)


def door_rattle() -> np.ndarray:
    n = ms(500)
    click_n = ms(150)
    tc = t_of(click_n)
    click = (np.sin(2 * np.pi * 1800.0 * tc) + np.sin(2 * np.pi * 2600.0 * tc)) * np.exp(-tc / 0.03)
    x = np.zeros(n)
    for offset in (0, 70, 160, 230, 360):
        start = ms(offset)
        end = min(n, start + click_n)
        x[start:end] += click[: end - start]
    return one_shot(x)


def footstep(variant: int) -> np.ndarray:
    rng = rng_for(f"footstep_{variant}")
    n = ms(70)
    t = t_of(n)
    body = unit(lowpass(white(rng, n), 900.0)) * np.exp(-t / 0.025)
    body += np.sin(2 * np.pi * 110.0 * t) * np.exp(-t / 0.015)
    return one_shot(body)


def clock_tick() -> np.ndarray:
    rng = rng_for("clock_tick")
    n = ms(10)
    t = t_of(n)
    return one_shot(unit(bandpass(white(rng, n), 2000.0, 4000.0)) * np.exp(-t / 0.002))


def lamp_click() -> np.ndarray:
    rng = rng_for("lamp_click")
    n = ms(15)
    t = t_of(n)
    body = unit(bandpass(white(rng, n), 1000.0, 5000.0)) * np.exp(-t / 0.004)
    body += np.sin(2 * np.pi * 300.0 * t) * np.exp(-t / 0.005)
    return one_shot(body)


def drawer(opening: bool) -> np.ndarray:
    name = "drawer_open" if opening else "drawer_close"
    rng = rng_for(name)
    n = ms(400)
    body_n = ms(350)
    body = unit(lowpass(white(rng, body_n), 500.0)) * np.hanning(body_n)
    click_n = ms(5)
    tc = t_of(click_n)
    click = unit(bandpass(white(rng, click_n), 2000.0, 4000.0)) * np.exp(-tc / 0.001)
    x = np.zeros(n)
    if opening:
        x[:body_n] += body
        x[body_n : body_n + click_n] += click
    else:
        x[:click_n] += click
        x[ms(50) : ms(50) + body_n] += body
    return one_shot(x)


def start_bell() -> np.ndarray:
    n = ms(2000)
    t = t_of(n)
    x = np.zeros(n)
    for chime_start in (0.0, 0.5):
        tc = t - chime_start
        chime = (np.sin(2 * np.pi * 1568.0 * tc) + 0.4 * np.sin(2 * np.pi * 2350.0 * tc)) * attack_decay(tc, 0.15, 0.6)
        x += np.where(tc >= 0.0, chime, 0.0)
    return one_shot(x, attack_ms=0.0)


def fixture_off_body() -> np.ndarray:
    rng = rng_for("fixture_off")
    n = ms(200)
    t = t_of(n)
    body = np.sin(2 * np.pi * 50.0 * t) * attack_decay(t, 0.15, 0.03)
    click_n = ms(4)
    tc = t_of(click_n)
    click = unit(bandpass(white(rng, click_n), 2000.0, 4000.0)) * np.exp(-tc / 0.001)
    start = ms(150)
    body[start : start + click_n] += click
    return body


def fixture_off() -> np.ndarray:
    return one_shot(fixture_off_body(), attack_ms=0.0)


def fixture_on() -> np.ndarray:
    n = ms(500)
    x = np.zeros(n)
    off = fixture_off_body()
    x[: len(off)] = off
    rise_n = n - ms(200)
    rise = np.sin(2 * np.pi * 100.0 * t_of(rise_n)) * np.linspace(0.0, 10 ** (-12 / 20), rise_n)
    x[ms(200) :] += rise
    return one_shot(x, attack_ms=0.0)


def door_unlock() -> np.ndarray:
    rng = rng_for("door_unlock")
    n = ms(300)
    t = t_of(n)
    body = np.sin(2 * np.pi * 140.0 * t) * attack_decay(t, 0.15, 0.06)
    body += unit(bandpass(white(rng, n), 1000.0, 3000.0)) * attack_decay(t, 0.15, 0.02)
    return one_shot(body, attack_ms=0.0)


def door_open() -> np.ndarray:
    rng = rng_for("door_open")
    n = ms(900)
    t = t_of(n)
    centre = log_sweep(n, [(0.0, 250.0), (1.0, 600.0)])
    noise = unit(swept_bandpass(white(rng, n), centre, q=4.0)) * np.hanning(n)
    return one_shot(noise + 10 ** (-18 / 20) * np.sin(2 * np.pi * 180.0 * t))


# --- ambient beds (seamless 10 s and 20 s loops) -----------------------------


def room_tone() -> np.ndarray:
    rng = rng_for("room_tone")
    n = 10 * FS

    def shape(f: np.ndarray) -> np.ndarray:
        # Brown noise (1/f amplitude), 2nd-order low-pass at 400 Hz, no DC.
        out = np.where(f > 0, 1.0 / np.where(f > 0, f, 1.0), 0.0) * butter_mag(f, 400.0, 2, "lp")
        return out

    return periodic_filter(white(rng, n), shape)


def hum() -> np.ndarray:
    rng = rng_for("hum")
    n = 10 * FS
    t = t_of(n)
    tones = np.sin(2 * np.pi * 100.0 * t) + 0.25 * np.sin(2 * np.pi * 200.0 * t) + 0.12 * np.sin(2 * np.pi * 300.0 * t)
    noise = periodic_filter(white(rng, n), lambda f: butter_mag(f, 2000.0, 4, "hp"))
    noise *= np.sqrt(np.mean(tones**2)) * 10 ** (-30 / 20) / np.sqrt(np.mean(noise**2))
    return tones + noise


def vent_shepard() -> np.ndarray:
    # Descending Shepard-Risset glissando. Eight components, one octave apart,
    # from 55 Hz. Each falls one octave per 20 s, so the loop closes after 20 s.
    # Start phases are chosen so the component that moves into each slot has the
    # phase the previous one started with. The two edge components (27.5 Hz and
    # 7040 Hz) have zero amplitude, so the loop has no discontinuity.
    n = 20 * FS
    t = t_of(n)
    period = 20.0
    base = 55.0 * 2.0 ** np.arange(8)
    advance = 2.0 * np.pi * base * period / (2.0 * np.log(2.0))
    phase0 = np.zeros(8)
    for j in range(1, 8):
        phase0[j] = phase0[j - 1] - advance[j]
    x = np.zeros(n)
    for j in range(8):
        glide = 2.0 ** (-t / period)
        theta = phase0[j] + 2.0 * np.pi * base[j] * (period / np.log(2.0)) * (1.0 - 2.0 ** (-t / period))
        log_f = np.log2(base[j] * glide / 440.0)
        gauss = np.exp(-(log_f**2) / (2.0 * 1.2**2))
        edge = np.clip((np.abs(log_f) - 3.5) / 0.5, 0.0, 1.0)
        taper = 0.5 * (1.0 + np.cos(np.pi * edge))
        x += gauss * taper * np.sin(theta)
    return periodic_filter(x, lambda f: butter_mag(f, 2000.0, 2, "lp"))


# --- registry and writer -----------------------------------------------------

# name -> (builder, peak dBFS). Table order follows spec 11.3.
ONE_SHOTS: dict[str, tuple] = {
    "key_clack_1": (lambda: key_clack(1), -10),
    "key_clack_2": (lambda: key_clack(2), -10),
    "key_clack_3": (lambda: key_clack(3), -10),
    "key_clack_4": (lambda: key_clack(4), -10),
    "carriage_return": (carriage_return, -12),
    "bell": (bell, -14),
    "backspace_click": (backspace_click, -16),
    "platen_ratchet": (platen_ratchet, -18),
    "key_jam": (key_jam, -14),
    "paper_in": (paper_in, -20),
    "paper_out": (paper_out, -20),
    "paper_shuffle": (paper_shuffle, -20),
    "page_turn": (page_turn, -22),
    "stamp_thud": (stamp_thud, -10),
    "marker_stroke": (marker_stroke, -24),
    "fluid_brush": (fluid_brush, -24),
    "tube_send": (tube_send, -18),
    "tube_arrive_whoosh": (tube_arrive_whoosh, -26),
    "tube_thunk": (tube_thunk, -20),
    "door_rattle": (door_rattle, -22),
    "footstep_1": (lambda: footstep(1), -28),
    "footstep_2": (lambda: footstep(2), -28),
    "clock_tick": (clock_tick, -38),
    "lamp_click": (lamp_click, -20),
    "drawer_open": (lambda: drawer(True), -20),
    "drawer_close": (lambda: drawer(False), -20),
    "start_bell": (start_bell, -26),
    "fixture_off": (fixture_off, -28),
    "fixture_on": (fixture_on, -28),
    "door_unlock": (door_unlock, -24),
    "door_open": (door_open, -20),
}

# name -> (builder, RMS dBFS). Spec 11.2.
BEDS: dict[str, tuple] = {
    "room_tone": (room_tone, -40),
    "hum": (hum, -38),
    "vent_shepard": (vent_shepard, -32),
}


def write_wav(path: Path, x: np.ndarray) -> None:
    pcm = np.clip(np.rint(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes(pcm.tobytes())


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, (build, peak_db) in ONE_SHOTS.items():
        write_wav(OUT_DIR / f"{name}.wav", finish_peak(build(), peak_db))
    for name, (build, rms_db) in BEDS.items():
        write_wav(OUT_DIR / f"{name}.wav", finish_rms(build(), rms_db))
    total = len(ONE_SHOTS) + len(BEDS)
    print(f"wrote {total} audio files to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

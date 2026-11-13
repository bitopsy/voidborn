#!/usr/bin/env python3
"""Generates every Voidborn sound effect procedurally (no samples, no licensing).

    python3 tools/gen_sounds.py            -> game/sounds/*.wav (+ ambient_void.ogg if ffmpeg/libvorbis exist)

Mono 16-bit 44.1 kHz WAV (the engine positions mono sounds in 3D). Deterministic: fixed random seed.
Edit a recipe below, rerun, rebuild the .sdz.
"""
import os, subprocess, sys, wave
import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "sounds")
rng = np.random.default_rng(1234)


# ------------------------------------------------------------------ building blocks
def t_(dur): return np.arange(int(dur * SR)) / SR
def sine(f, dur, ph=0.0): return np.sin(2 * np.pi * f * t_(dur) + ph)
def noise(dur): return rng.uniform(-1, 1, int(dur * SR))
def env_exp(n, tau): return np.exp(-np.arange(n) / (tau * SR))
def attack(x, a=0.004):
    n = min(len(x), max(1, int(a * SR))); x = x.copy(); x[:n] *= np.linspace(0, 1, n); return x
def release(x, r=0.01):
    n = min(len(x), max(1, int(r * SR))); x = x.copy(); x[-n:] *= np.linspace(1, 0, n); return x
def lp(x, fc, order=2): return signal.lfilter(*signal.butter(order, fc / (SR / 2), "low"), x)
def hp(x, fc, order=2): return signal.lfilter(*signal.butter(order, fc / (SR / 2), "high"), x)
def bp(x, lo, hi, order=2): return signal.lfilter(*signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band"), x)
def sweep(f0, f1, dur, shape="exp"):
    """tone whose frequency glides f0 -> f1"""
    n = int(dur * SR); u = np.linspace(0, 1, n)
    f = f0 * (f1 / f0) ** u if shape == "exp" else f0 + (f1 - f0) * u
    return np.sin(2 * np.pi * np.cumsum(f) / SR)
def fm(fc, fmod, index, dur):
    t = t_(dur); return np.sin(2 * np.pi * fc * t + index * np.sin(2 * np.pi * fmod * t))
def pad(x, n): return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n] if n else x
def mix(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n)
    for p in parts: out[:len(p)] += p
    return out
def at(x, start, total=None):
    """place x `start` seconds into a silent buffer"""
    s = int(start * SR); out = np.zeros(s + len(x)); out[s:] = x
    return out
def echo(x, delay, fb, taps):
    out = np.concatenate([x, np.zeros(int(delay * SR) * taps)]); res = out.copy()
    for k in range(1, taps + 1):
        d = int(delay * SR) * k; res[d:d + len(x)] += x * (fb ** k)
    return res
def norm(x, peak=0.9): m = np.max(np.abs(x)) or 1.0; return x / m * peak
def sat(x, k=2.0): return np.tanh(k * x) / np.tanh(k)


def save(name, x, peak=0.9, stereo=None):
    x = release(attack(norm(x, peak), 0.002), 0.012)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------ UI
def ui():
    d = 0.07; x = sine(1500, d) * env_exp(int(d * SR), 0.02) + 0.3 * noise(d) * env_exp(int(d * SR), 0.004)
    save("ui_click", x, 0.7)
    d = 0.04; save("ui_hover", sine(2600, d) * env_exp(int(d * SR), 0.012), 0.4)
    d = 0.12; x = sweep(700, 1250, d) * env_exp(int(d * SR), 0.05); save("ui_select", mix(x, 0.4 * sweep(1400, 2500, d) * env_exp(int(d * SR), 0.03)), 0.7)
    d = 0.24; x = (sweep(260, 950, d) + 0.4 * sweep(520, 1900, d)) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 0.7; save("ui_open", x, 0.7)
    d = 0.2; x = (sweep(900, 240, d) + 0.4 * sweep(1800, 480, d)) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 0.7; save("ui_close", x, 0.7)
    d = 0.22; x = sat(sweep(150, 105, d) + 0.5 * sine(75, d), 3) * env_exp(int(d * SR), 0.09); save("ui_error", hp(x, 40), 0.8)
    d = 0.16; x = sine(95, d) * env_exp(int(d * SR), 0.05) + 0.6 * sine(880, d) * env_exp(int(d * SR), 0.035); save("ui_place", x, 0.8)


# ------------------------------------------------------------------ alerts / jingles
def bell(f, dur, tau=0.25, idx=2.0, ratio=3.5):
    return fm(f, f * ratio, idx, dur) * env_exp(int(dur * SR), tau)

def alerts():
    # commander under attack: three urgent two-tone pulses
    pulse = lambda f: sat(sine(f, 0.16) + 0.5 * sine(f * 2, 0.16), 2) * np.sin(np.linspace(0, np.pi, int(0.16 * SR))) ** 0.5
    seq = np.concatenate([pad(pulse(540), int(0.2 * SR)), pad(pulse(405), int(0.2 * SR))] * 3)
    save("alarm_commander", seq * (1 + 0.3 * np.sin(2 * np.pi * 9 * t_(len(seq) / SR))), 0.85)
    # unit ready: two ascending bells
    save("unit_ready", mix(bell(660, 0.5, 0.18), at(bell(990, 0.6, 0.22), 0.13)), 0.75)
    # structure complete: low thump + three-note arpeggio
    thump = sine(70, 0.3) * env_exp(int(0.3 * SR), 0.08)
    save("struct_done", mix(thump, at(bell(392, 0.7, 0.22), 0.05), at(bell(523, 0.7, 0.22), 0.17), at(bell(784, 0.9, 0.3), 0.29)), 0.8)
    # construction started: thump + rising grind
    d = 0.4; g = sat(sweep(60, 220, d) + 0.4 * sweep(120, 440, d), 2) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 1.5
    save("build_start", mix(sine(55, 0.3) * env_exp(int(0.3 * SR), 0.1), 0.6 * g, 0.2 * hp(noise(d), 2000) * env_exp(int(d * SR), 0.1)), 0.85)
    # nano zap (builder working, short and loopable-ish)
    d = 0.32; z = sat(sine(180, d) * (1 + 0.8 * sine(34, d)) + 0.5 * bp(noise(d), 1200, 4200), 2.5)
    save("nano_zap", z * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 0.6, 0.55)
    # game start: swelling sweep + bell
    d = 1.6; sw = (sweep(80, 420, d) + 0.5 * sweep(160, 840, d)) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 2
    save("game_start", mix(sw, at(bell(262, 1.6, 0.6, 1.5), 0.6), at(bell(523, 1.4, 0.5, 1.5), 0.75)), 0.8)


# ------------------------------------------------------------------ unit voices
def voices():
    # CHOIR: glassy, many-voiced shimmer
    d = 0.5; n = int(d * SR)
    v = lambda f, vib: fm(f, f * 2.01, 1.2 + vib, d) * (1 + 0.15 * sine(5.5, d))
    sel = (v(520, 0.3) + 0.7 * v(780, 0.2) + 0.5 * v(1040, 0.5)) * env_exp(n, 0.22) * np.minimum(1, np.arange(n) / (0.04 * SR))
    save("select_choir", sel, 0.7)
    d = 0.2; n = int(d * SR); ok = (fm(880, 1771, 1.0, d) + 0.5 * fm(1320, 2650, 0.8, d)) * env_exp(n, 0.07)
    save("ok_choir", ok, 0.6)
    # MAW: wet, clicky, guttural
    def chitter(dur, rate, lo, hi):
        n = int(dur * SR); gate = (np.sin(2 * np.pi * rate * t_(dur)) > 0.2).astype(float); gate = lp(gate, 900)
        return bp(noise(dur), lo, hi) * gate * env_exp(n, dur * 0.5)
    d = 0.42; n = int(d * SR)
    growl = sat(sweep(95, 60, d) + 0.5 * sine(48, d), 3) * (1 + 0.7 * sine(23, d)) * env_exp(n, 0.2)
    save("select_maw", mix(0.8 * growl, 1.2 * chitter(d, 24, 1500, 5200)), 0.75)
    d = 0.22; n = int(d * SR)
    save("ok_maw", mix(1.0 * chitter(d, 34, 1800, 6000), 0.6 * sweep(300, 520, d) * env_exp(n, 0.06)), 0.65)
    # structures
    d = 0.6; n = int(d * SR); swell = np.sin(np.linspace(0, np.pi, n)) ** 1.3
    save("select_struct_choir", (sine(110, d) + 0.5 * sine(220, d) + 0.3 * fm(660, 1320, 1.5, d)) * swell, 0.55)
    d = 0.55; n = int(d * SR)
    save("select_struct_maw", lp(sat(sweep(70, 48, d) + 0.5 * noise(d) * 0.3, 2.5), 700) * np.sin(np.linspace(0, np.pi, n)) ** 0.8 * (1 + 0.6 * sine(11, d)), 0.7)


# ------------------------------------------------------------------ weapons
def laser(f0, f1, dur, tail, body=0.4):
    n = int(dur * SR); z = sweep(f0, f1, dur) + body * sweep(f0 * 2, f1 * 2, dur) * 0.6
    return z * env_exp(n, tail) + 0.25 * bp(noise(dur), 1500, 7000) * env_exp(n, 0.03)

def weapons():
    save("laser_choir_light", laser(3200, 1100, 0.2, 0.06), 0.55)
    save("laser_choir", laser(2400, 520, 0.38, 0.12), 0.7)
    d = 0.8; n = int(d * SR)
    heavy = sat(sweep(1500, 120, d) + 0.7 * sweep(750, 60, d), 2.5) * env_exp(n, 0.28)
    save("laser_choir_heavy", mix(heavy, 0.5 * sine(48, d) * env_exp(n, 0.35), 0.3 * bp(noise(d), 800, 5000) * env_exp(n, 0.08)), 0.9)

    def spit(dur, lo, hi, bubble):
        n = int(dur * SR); h = bp(noise(dur), lo, hi) * env_exp(n, dur * 0.35)
        b = sweep(bubble, bubble * 2.6, dur) * np.clip(sine(38, dur), 0, 1) * env_exp(n, dur * 0.4)
        return h + 0.7 * b
    save("acid_light", spit(0.2, 2500, 7500, 380), 0.55)
    save("acid_spit", spit(0.36, 1500, 6500, 260), 0.7)
    d = 0.7; save("acid_heavy", mix(spit(d, 700, 5000, 150), 0.7 * sat(sweep(110, 50, d), 2) * env_exp(int(d * SR), 0.22)), 0.9)

    d = 0.55; n = int(d * SR)
    save("spore_launch", mix(sine(78, 0.25) * env_exp(int(0.25 * SR), 0.07), 0.8 * bp(noise(d), 300, 2800) * np.sin(np.linspace(0.2, np.pi, n)) ** 1.2 * env_exp(n, 0.25),
                             0.3 * sweep(180, 900, d) * env_exp(n, 0.2)), 0.8)
    d = 0.55; n = int(d * SR)
    save("flame_breath", lp(noise(d), 2600) * (1 + 0.4 * sine(29, d)) * np.sin(np.linspace(0, np.pi, n)) ** 0.7 + 0.3 * bp(noise(d), 200, 700) * env_exp(n, 0.3), 0.6)
    # super weapon: charge -> huge blast
    ch = 0.9; blast = 1.6
    charge = (sweep(60, 700, ch) + 0.5 * sweep(120, 1400, ch)) * (np.linspace(0.1, 1, int(ch * SR)) ** 2)
    nb = int(blast * SR)
    boom = sat(sweep(130, 35, blast) + 0.6 * sine(40, blast), 3) * env_exp(nb, 0.5) + 0.9 * lp(noise(blast), 1400) * env_exp(nb, 0.35)
    save("dgun_blast", mix(charge, at(boom, ch)), 0.95)


# ------------------------------------------------------------------ impacts / explosions
def boom(dur, f0, f1, tau, nz_lp, nz_tau, grit=0.8, sub=0.0):
    n = int(dur * SR)
    low = sat(sweep(f0, f1, dur) + sub * sine(f1 * 0.7, dur), 3) * env_exp(n, tau)
    body = lp(noise(dur), nz_lp, 3) * env_exp(n, nz_tau)
    crack = hp(noise(0.04), 1500) * env_exp(int(0.04 * SR), 0.01)
    return mix(low, grit * body, 0.6 * crack)

def impacts():
    save("boom_small", boom(0.7, 220, 60, 0.12, 2400, 0.14), 0.8)
    save("boom_med", boom(1.1, 170, 45, 0.22, 1800, 0.26, sub=0.5), 0.9)
    save("boom_big", boom(2.4, 120, 28, 0.6, 1100, 0.75, grit=1.0, sub=0.9), 1.0)
    d = 0.16; n = int(d * SR)
    save("hit_laser", mix(bp(noise(d), 2500, 9000) * env_exp(n, 0.025), 0.5 * sweep(1800, 500, d) * env_exp(n, 0.04)), 0.55)
    d = 0.35; n = int(d * SR)
    save("hit_acid", mix(bp(noise(d), 3000, 9000) * np.clip(sine(55, d) + 0.5, 0, 1) * env_exp(n, 0.12), 0.5 * lp(noise(d), 600) * env_exp(n, 0.08)), 0.55)


# ------------------------------------------------------------------ economy / structures
def economy():
    d = 0.7; n = int(d * SR)
    m = sat(sweep(60, 240, d, "lin") + 0.5 * sweep(120, 480, d, "lin"), 2) * (1 + 0.5 * sine(48, d)) * np.sin(np.linspace(0, np.pi, n)) ** 0.5
    save("mex_on", 0.9 * m + 0.2 * bp(noise(d), 800, 3000) * env_exp(n, 0.3), 0.7)
    d = 0.9; n = int(d * SR)
    save("radar_ping", (sine(1480, d) + 0.4 * sine(2960, d)) * env_exp(n, 0.35) * (1 + 0.1 * sine(7, d)) + 0.2 * bp(noise(d), 4000, 9000) * env_exp(n, 0.02), 0.6)
    d = 0.8; n = int(d * SR); sw = np.sin(np.linspace(0, np.pi, n)) ** 1.2
    save("power_on", (sine(120, d) + 0.6 * sine(240, d) + 0.35 * fm(960, 1920, 1.0, d)) * sw * (1 + 0.25 * sine(13, d)), 0.6)
    d = 0.5; n = int(d * SR)
    save("power_off", (sweep(380, 80, d) + 0.4 * sweep(760, 160, d)) * env_exp(n, 0.2), 0.6)


# ------------------------------------------------------------------ ambience (stereo ogg; loops seamlessly)
def ambient():
    dur = 40.0; n = int(dur * SR); t = np.arange(n) / SR
    # slow evolving drone from detuned low sines with very slow amplitude drift + faint filtered noise "wind"
    def chan(seed):
        r = np.random.default_rng(seed)
        out = np.zeros(n)
        for f, a in ((41, 1.0), (55, 0.7), (82.4, 0.5), (110.3, 0.35), (164.8, 0.2)):
            lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (1 / r.uniform(9, 21)) * t + r.uniform(0, 6.28))
            out += a * lfo * np.sin(2 * np.pi * f * (1 + r.uniform(-0.002, 0.002)) * t + r.uniform(0, 6.28))
        wind = lp(r.uniform(-1, 1, n), 380, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 13.0 + r.uniform(0, 6.28)))
        # whole-number cycles per loop keep the ends matching; crossfade anyway
        return out / 3 + 0.35 * wind
    L, R = chan(1), chan(2)
    xf = int(3 * SR); ramp = np.linspace(0, 1, xf)
    def loopify(x):
        y = x[:-xf].copy(); y[:xf] = y[:xf] * ramp + x[-xf:] * (1 - ramp); return y
    L, R = loopify(L), loopify(R); m = max(np.max(np.abs(L)), np.max(np.abs(R))) or 1
    L, R = L / m * 0.8, R / m * 0.8
    pcm = (np.stack([L, R], 1) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, "ambient_void.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    ogg = os.path.join(OUT, "ambient_void.ogg")
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
        os.remove(wav)
    except Exception as e:
        print("ffmpeg/libvorbis unavailable (%s): leaving ambient_void.wav" % e)


if __name__ == "__main__":
    for fn in (ui, alerts, voices, weapons, impacts, economy, ambient):
        fn()
    files = sorted(os.listdir(OUT))
    print("wrote %d files to %s" % (len(files), os.path.abspath(OUT)))
    print(", ".join(files))


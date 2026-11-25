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


# ------------------------------------------------------------------ 0.19: lower, alien weapon sounds
# Every weapon fire / hit sound listed here goes through alienize() on its way to disk: pitched down (and so a little longer), an
# octave-lower body underneath, a slow pitch waver, a low ring-modulation sideband and a detuned double.  No rng is used, so the
# recipes above and every other file stay exactly as they were.
ALIEN = {"laser_choir_light": 0.70, "laser_choir": 0.74, "laser_choir_heavy": 0.80, "beam_choir": 0.80, "hit_beam": 0.82, "hit_laser": 0.80,
         "acid_light": 0.70, "acid_spit": 0.74, "acid_heavy": 0.80, "acid_glob": 0.80, "hit_acid": 0.82, "hit_glob": 0.82, "spore_launch": 0.78,
         "flame_breath": 0.80, "sonic_light": 0.70, "sonic_pulse": 0.74, "sonic_wave": 0.78, "sonic_boom": 0.82, "hit_sonic": 0.82,
         "gas_dart": 0.70, "gas_lob": 0.76, "gas_heavy": 0.80, "gas_hiss": 0.80, "hit_gas": 0.82,
         "touch_light": 0.70, "touch_lash": 0.74, "touch_pound": 0.80, "touch_heavy": 0.82, "hit_touch": 0.82}
SPECIAL = ("arc_zap", "arc_heavy", "sonar_ping", "sonar_deep", "warble_light", "warble_heavy")
NEW_BEAMS = ("beam_thin_light", "beam_thin") + SPECIAL
ONLY = None            # `python3 tools/gen_sounds.py alien` writes only the weapon sounds (see __main__)

def alienize(name, x):
    r = ALIEN[name]; n = len(x)
    y = np.interp(np.linspace(0, n - 1, int(n / r)), np.arange(n), x)                      # lower and longer
    m = len(y); t = np.arange(m) / SR
    idx = np.cumsum(1 + 0.02 * np.sin(2 * np.pi * 6.3 * t)); idx *= (m - 1) / idx[-1]       # slow pitch waver
    y = np.interp(idx, np.arange(m), y)
    body = lp(np.interp(np.linspace(0, n - 1, int(n / (r * 0.5))), np.arange(n), x)[:m], 650)   # an octave lower again, as a body
    body = pad(body, m)
    ring = y * np.sin(2 * np.pi * 47 * t)                                                    # metallic sidebands
    dd = int(0.009 * SR)
    double = np.interp(np.arange(m) * 0.985, np.arange(m), np.concatenate([np.zeros(dd), y[:-dd]]))   # 9 ms late, ~26 cents flat
    z = 0.75 * y + 0.35 * ring + 0.35 * double + 0.55 * body
    z = echo(z, 0.05, 0.32, 3)                                                               # a short, eerie tail
    return sat(lp(z, 6500), 1.3)


def save(name, x, peak=0.9, stereo=None):
    if ONLY is not None and name not in ONLY: return
    if name in ALIEN: x = alienize(name, x)
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
    #save("unit_ready", mix(bell(660, 0.5, 0.18), at(bell(990, 0.6, 0.22), 0.13)), 0.75)
    d = 0.9; g = sat(sweep(60, 220, d) + 0.4 * sweep(120, 440, d), 2) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 1.5
    save("unit_ready", mix(sine(88, 0.3) * env_exp(int(0.3 * SR), 0.1), 0.8 * g, 0.5 * hp(noise(d), 2000) * env_exp(int(d * SR), 0.1)), 0.95)
    # structure complete: low thump + three-note arpeggio
    thump = sine(70, 0.3) * env_exp(int(0.3 * SR), 0.08)
    save("struct_done", mix(thump, at(bell(133, 0.7, 0.22), 0.05), at(bell(324, 0.7, 0.22), 0.17), at(bell(423, 0.9, 0.3), 0.29)), 0.8)
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


def evolve():
    # a unit splitting in two: wet pop + rising double chime
    d = 0.3; n = int(d * SR)
    pop = sweep(180, 900, 0.12) * env_exp(int(0.12 * SR), 0.04) + 0.6 * bp(noise(0.12), 800, 5000) * env_exp(int(0.12 * SR), 0.02)
    save("split_pop", mix(pop, at(bell(880, 0.5, 0.18, 1.5), 0.08), at(bell(1320, 0.55, 0.2, 1.5), 0.17)), 0.8)


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


# ------------------------------------------------------------------ commander weapons (beam, glob, D-gun, Q-gun)
# NB: these draw from the shared rng, so they run AFTER every older recipe (see __main__): that keeps the
# older sounds byte-identical when the whole script is rerun.
def swell(n, p=1.0): return np.sin(np.linspace(0, np.pi, n)) ** p
def rise(n, p=2.0): return np.linspace(0, 1, n) ** p
def gate(dur, rate, duty=0.5, smooth=700): return lp((np.sin(2 * np.pi * rate * t_(dur)) > (1 - 2 * duty)).astype(float), smooth)

def cmd_weapons():
    # --- Hierophant "Gaze": a persistent blue beam. Pulled-in crackle, then a sustained singing hum with vibrato.
    d = 1.1; n = int(d * SR); t = t_(d)
    env = np.minimum(1, t / 0.09) * np.minimum(1, (d - t) / 0.28)
    hum = sat(sine(165, d) + 0.6 * sine(330, d) + 0.3 * fm(660, 1320, 1.2, d), 1.5)
    sing = fm(1560, 6, 2.4, d) * 0.9 + 0.5 * fm(2340, 7, 1.6, d)
    hiss = bp(noise(d), 3500, 9000)
    zap = sweep(3600, 700, 0.12) * env_exp(int(0.12 * SR), 0.04)
    save("beam_choir", mix(env * (1 + 0.15 * sine(19, d)) * (0.8 * hum + 0.32 * sing + 0.12 * hiss), 0.7 * zap), 0.8)
    d = 0.3; n = int(d * SR)
    crackle = hp(noise(d), 3000) * lp((noise(d) > 0.45).astype(float), 3000) * env_exp(n, 0.09)
    save("hit_beam", mix(crackle, 0.5 * sweep(1500, 380, d) * env_exp(n, 0.05), 0.3 * sine(90, d) * env_exp(n, 0.06)), 0.6)

    # --- Matriarch "Acid Spit": a slow heavy glob. Wet thump, rising gurgle, slimy tail; and a splat on impact.
    d = 0.8; n = int(d * SR)
    thump = sat(sweep(150, 52, 0.28), 2) * env_exp(int(0.28 * SR), 0.09)
    gurgle = sweep(170, 560, d) * np.clip(sine(23, d), 0, 1) * env_exp(n, 0.25)
    spit = bp(noise(d), 900, 4500) * env_exp(n, 0.09)
    slime = lp(noise(d), 700) * np.clip(sine(11, d) + 0.4, 0, 1) * env_exp(n, 0.3)
    save("acid_glob", mix(thump, 0.7 * gurgle, 0.6 * spit, 0.35 * slime), 0.85)
    d = 0.75; n = int(d * SR)
    splat = lp(noise(d), 1900) * env_exp(n, 0.07)
    sizzle = bp(noise(d), 2500, 9000) * np.clip(sine(47, d) + 0.5, 0, 1) * env_exp(n, 0.25)
    save("hit_glob", mix(splat, 0.8 * sizzle, 0.8 * sat(sweep(210, 55, 0.3), 2) * env_exp(int(0.3 * SR), 0.1)), 0.8)

    # --- D-gun, Choir ("Cataract Stare"): glassy rising chord, then a deep clean blast with ringing overtones.
    ch, bl = 0.9, 1.4; nc, nb = int(ch * SR), int(bl * SR)
    charge = sum(sweep(f * 0.5, f, ch) * (0.8 + 0.2 * sine(7 + i, ch)) for i, f in enumerate((440, 660, 880, 1320))) * rise(nc, 2.2)
    charge = charge + 0.4 * bp(noise(ch), 3000, 10000) * rise(nc, 3)
    boom = sat(sweep(160, 30, bl) + 0.6 * sine(38, bl), 3) * env_exp(nb, 0.45)
    ring = (bell(1760, bl, 0.55, 1.4, 2.0) + 0.7 * bell(2640, bl, 0.45, 1.2, 2.0) + 0.5 * bell(880, bl, 0.7, 1.2, 2.0)) * 0.5
    air = hp(noise(bl), 2500) * env_exp(nb, 0.12) * 0.4
    save("dgun_choir", mix(charge * 0.7, at(echo(mix(boom, ring, air), 0.09, 0.4, 3), ch)), 0.95)

    # --- D-gun, Maw ("Devour"): wet inhale and gurgle, then a guttural roar with chittering and a crunch.
    ch, bl = 0.9, 1.4; nc, nb = int(ch * SR), int(bl * SR)
    inhale = bp(noise(ch), 400, 2600) * rise(nc, 1.6) * (1 + 0.6 * sine(17, ch))
    gur = sat(sweep(48, 120, ch) * (1 + 0.8 * sine(13, ch)), 2.5) * rise(nc, 1.4)
    roar = sat(sweep(95, 38, bl) + 0.7 * sine(57, bl) * (1 + 0.8 * sine(31, bl)) + 0.4 * sweep(190, 76, bl), 4) * env_exp(nb, 0.5)
    chit = bp(noise(bl), 1500, 6500) * gate(bl, 30, 0.35) * env_exp(nb, 0.35)
    crunch = lp(noise(0.12), 1100) * env_exp(int(0.12 * SR), 0.03)
    save("dgun_maw", mix(0.7 * inhale, 0.9 * gur, at(mix(roar, 0.55 * chit, 0.8 * crunch), ch - 0.02)), 0.95)

    # --- Q-gun (Destabilisation Gun), Choir: a ring-modulated warbling climb, then an expanding shimmering pulse.
    ch, pl = 0.7, 1.0; nc, np_ = int(ch * SR), int(pl * SR)
    climb = sweep(300, 2400, ch) * (0.5 + 0.5 * sine(70, ch)) + 0.4 * sweep(150, 1200, ch)
    pulse = sweep(1800, 200, pl) * env_exp(np_, 0.35) + 0.6 * sum(sine(f, pl) for f in (1000, 1013, 987)) / 3 * env_exp(np_, 0.4)
    pulse = pulse + 0.3 * bp(noise(pl), 1500, 7000) * env_exp(np_, 0.15)
    save("qgun_choir", mix(climb * rise(nc, 1.8) * 0.8, at(echo(pulse, 0.11, 0.45, 3), ch)), 0.9)
    # --- Q-gun, Maw: same idea, but lower, wetter and sicker (tremolo + bubbling).
    ch, pl = 0.7, 1.0; nc, np_ = int(ch * SR), int(pl * SR)
    climb = sat(sweep(110, 900, ch), 2.5) * (0.5 + 0.5 * sine(22, ch)) + 0.5 * lp(noise(ch), 900) * np.clip(sine(14, ch) + 0.3, 0, 1)
    pulse = sat(sweep(700, 90, pl), 3) * (0.6 + 0.4 * sine(40, pl)) * env_exp(np_, 0.35) + 0.5 * lp(noise(pl), 1200) * env_exp(np_, 0.2)
    save("qgun_maw", mix(climb * rise(nc, 1.6) * 0.8, at(echo(pulse, 0.12, 0.4, 3), ch)), 0.9)
    # --- stun wave impact: electric crackle over a falling detuned buzz
    d = 1.3; n = int(d * SR)
    crack = hp(noise(d), 2500) * lp((noise(d) > 0.55).astype(float), 2500) * env_exp(n, 0.5)
    buzz = sat(sweep(900, 80, d), 8) * (0.6 + 0.4 * sine(50, d)) * env_exp(n, 0.3)
    save("stun_wave", mix(0.9 * crack, 0.5 * buzz, 0.7 * sat(sweep(120, 40, 0.3), 2) * env_exp(int(0.3 * SR), 0.1)), 0.85)
    # --- gun ready (a long-reload gun is loaded again) / gun denied (reloading, no energy, out of range)
    save("gun_ready", mix(bell(1175, 0.35, 0.12, 1.5), at(bell(1760, 0.45, 0.16, 1.5), 0.09), 0.3 * hp(noise(0.02), 3000)), 0.7)
    d = 0.22; n = int(d * SR)
    two = np.concatenate([pad(sat(np.sign(sine(110, 0.08)) * 0.6 + sine(110, 0.08), 2), int(0.11 * SR)), sat(np.sign(sine(95, 0.09)) * 0.6 + sine(95, 0.09), 2)])
    save("gun_denied", lp(two, 900), 0.6)


# ------------------------------------------------------------------ announcements (jingles; no voice samples, no licensing)
def brass(f, dur, tau=0.4):
    n = int(dur * SR)
    return sat(fm(f, f, 1.6, dur) + 0.5 * fm(f * 2, f * 2, 1.0, dur), 2) * env_exp(n, tau) * np.minimum(1, np.arange(n) / (0.03 * SR))

def announcements():
    # cloak on: a shimmer that falls away and fades out; cloak off: it snaps back, brightening, with a pop
    d = 0.9; n = int(d * SR)
    save("cloak_on", mix((sweep(1900, 220, d) + 0.5 * fm(900, 1800, 1.5, d)) * env_exp(n, 0.28) * (1 + 0.4 * sine(11, d)), 0.25 * bp(noise(d), 1000, 6000) * env_exp(n, 0.25)), 0.7)
    d = 0.5; n = int(d * SR)
    pop = (noise(0.05) * 0.7 + sine(900, 0.05)) * env_exp(int(0.05 * SR), 0.015)
    save("cloak_off", mix(sweep(200, 1700, 0.4) * swell(int(0.4 * SR), 0.8), at(pop, 0.36)), 0.7)
    # own commander lost: three slow tolling bells falling, a sub drop, a dark pad
    d = 3.2; n = int(d * SR)
    tolls = mix(bell(220, 2.6, 0.9, 2.5, 2.76), at(bell(196, 2.4, 0.9, 2.5, 2.76), 0.85), at(bell(164.8, 2.4, 1.0, 2.5, 2.76), 1.7))
    save("commander_lost", mix(tolls, 0.8 * sat(sweep(70, 26, d), 2) * env_exp(n, 1.1), 0.25 * lp(noise(d), 300) * swell(n, 0.8)), 0.9)
    # enemy commander destroyed: a short rising fanfare ending on a boom
    d = 2.0
    fan = mix(brass(392, 0.5, 0.25), at(brass(523, 0.5, 0.25), 0.18), at(brass(659, 0.5, 0.25), 0.36), at(brass(784, 1.3, 0.55), 0.54), at(brass(1047, 1.2, 0.5), 0.54))
    save("enemy_commander_down", mix(fan, at(boom(1.0, 170, 45, 0.22, 1800, 0.26, sub=0.5), 0.54)), 0.9)
    # victory: a bright four-note climb into a full, ringing chord
    chord = lambda dur: mix(*[brass(f, dur, 0.9) for f in (262, 330, 392, 523)], *[0.5 * bell(f, dur, 0.8, 1.5) for f in (523, 784, 1047)])
    notes = mix(brass(262, 0.3, 0.2), at(brass(330, 0.3, 0.2), 0.22), at(brass(392, 0.3, 0.2), 0.44), at(brass(523, 0.5, 0.3), 0.66))
    save("victory", mix(notes, at(chord(2.2), 0.95)), 0.9)
    # defeat: three slow falling minor notes over a sub fall
    low = lambda f, dur: lp(sat(fm(f, f, 1.2, dur) + 0.4 * sine(f / 2, dur), 2), 1800) * env_exp(int(dur * SR), 0.7)
    save("defeat", mix(low(196, 1.2), at(low(155.6, 1.2), 0.9), at(low(130.8, 2.0), 1.8), at(0.8 * sat(sweep(80, 28, 1.6), 2) * env_exp(int(1.6 * SR), 0.7), 1.8)), 0.85)
    # energy low: two falling urgent beeps then a power-down slide; metal low: two metallic clanks
    beep = lambda f0, f1: sat(sweep(f0, f1, 0.18), 3) * swell(int(0.18 * SR), 0.5)
    d = 0.5
    save("energy_low", mix(beep(560, 430), at(beep(560, 430), 0.26), at((sweep(600, 90, d) + 0.4 * sweep(1200, 180, d)) * env_exp(int(d * SR), 0.2) * 0.8, 0.56)), 0.8)
    clank = lambda f, dur: fm(f, f * 1.41, 4.0, dur) * env_exp(int(dur * SR), 0.1) + 0.4 * bp(noise(dur), 2500, 8000) * env_exp(int(dur * SR), 0.012)
    save("metal_low", mix(clank(310, 0.5), at(clank(250, 0.6), 0.3)), 0.8)
    # tier 2 online: a swelling chord, a rising bell arpeggio, one long final bell and a sub thump
    d = 2.6; n = int(d * SR)
    pad_ = mix(*[0.6 * fm(f, f * 2.01, 0.8, d) for f in (131, 196, 262, 330)]) * swell(n, 1.2)
    arp = mix(*[at(bell(f, 1.4, 0.4, 1.8), 0.1 + 0.11 * i) for i, f in enumerate((523, 659, 784, 1047, 1319))])
    save("tier2_ready", mix(0.6 * pad_, arp, at(bell(1568, 1.6, 0.6, 1.4), 0.7), 0.7 * sine(60, 0.35) * env_exp(int(0.35 * SR), 0.1)), 0.9)


# ------------------------------------------------------------------ 0.16: Tympan Conclave (the Ear) and Miasma Bloom (the Nose)
# Drawn from the shared rng AFTER every older recipe (see __main__), so the older files stay byte-identical on a rerun.
def new_factions():
    # ---- voices.  TYMPAN: bells, beating pairs of tones, a distant gong.  MIASMA: sniffs, snorts, wet hiss.
    d = 0.6; n = int(d * SR)
    beat = (sine(880, d) + sine(886, d) + 0.5 * sine(1320, d) + 0.5 * sine(1327, d)) * env_exp(n, 0.28) * np.minimum(1, np.arange(n) / (0.02 * SR))
    save("select_tympan", mix(beat, 0.3 * bell(1760, d, 0.2, 1.2, 2.0)), 0.7)
    d = 0.22; n = int(d * SR); save("ok_tympan", mix(bell(1568, d, 0.08, 1.2, 2.0), 0.5 * bell(2352, d, 0.06, 1.0, 2.0)), 0.6)
    d = 0.9; n = int(d * SR)
    save("select_struct_tympan", mix(bell(110, d, 0.3, 2.5, 2.4), 0.5 * bell(165, d, 0.25, 2.0, 2.4), 0.15 * lp(noise(d), 500) * env_exp(n, 0.1)), 0.65)
    def sniff(dur, lo, hi, k=1.0):
        n = int(dur * SR); return bp(noise(dur), lo, hi) * np.sin(np.linspace(0.1, np.pi, n)) ** k * (1 + 0.5 * sine(31, dur))
    d = 0.55
    save("select_miasma", mix(sniff(0.2, 500, 3200), at(sniff(0.24, 700, 4200), 0.22), 0.6 * sat(sweep(120, 70, d), 2) * env_exp(int(d * SR), 0.18)), 0.75)
    d = 0.2; save("ok_miasma", mix(sniff(d, 1000, 5200, 0.8), 0.5 * sweep(260, 420, d) * env_exp(int(d * SR), 0.07)), 0.6)
    d = 0.9; n = int(d * SR)
    save("select_struct_miasma", lp(sat(sweep(62, 44, d) + 0.5 * noise(d) * 0.25, 2.5), 600) * swell(n, 0.8) * (1 + 0.5 * sine(9, d)) + 0.3 * bp(noise(d), 300, 1400) * swell(n, 1.5), 0.7)

    # ---- sonic weapons: a ping, a pulse, a pressure wave, a boom; the hit is a muted bronze dong
    d = 0.2; n = int(d * SR); save("sonic_light", mix(sweep(2600, 1900, d) * env_exp(n, 0.05), 0.4 * bell(3100, d, 0.05, 1.0, 2.0)), 0.55)
    d = 0.36; n = int(d * SR); save("sonic_pulse", mix(fm(1100, 550, 2.0, d) * env_exp(n, 0.11), 0.5 * sweep(1800, 600, d) * env_exp(n, 0.08)), 0.7)
    d = 0.7; n = int(d * SR)
    save("sonic_wave", mix(sat(sweep(260, 70, d) + 0.4 * sine(55, d), 2) * env_exp(n, 0.2), 0.5 * fm(420, 7, 3.0, d) * env_exp(n, 0.22), 0.25 * bp(noise(d), 300, 2000) * env_exp(n, 0.07)), 0.85)
    d = 1.3; n = int(d * SR)
    save("sonic_boom", mix(sat(sweep(150, 34, d) + 0.7 * sine(40, d), 3) * env_exp(n, 0.4), 0.5 * fm(220, 5, 4.0, d) * env_exp(n, 0.3), 0.4 * bp(noise(d), 200, 1800) * env_exp(n, 0.12), 0.3 * bell(330, d, 0.4, 2.0, 2.4)), 0.95)
    d = 0.5; n = int(d * SR); save("hit_sonic", mix(bell(196, d, 0.16, 2.0, 2.2), 0.4 * hp(noise(d), 1500) * env_exp(n, 0.03), 0.5 * sat(sweep(160, 50, 0.25), 2) * env_exp(int(0.25 * SR), 0.08)), 0.7)

    # ---- gas weapons: a pfft, a heavy lob, a hissing jet, a soft burst
    d = 0.2; n = int(d * SR); save("gas_dart", mix(bp(noise(d), 2200, 7800) * env_exp(n, 0.05), 0.4 * sweep(900, 400, d) * env_exp(n, 0.04)), 0.55)
    d = 0.8; n = int(d * SR)
    save("gas_lob", mix(sat(sweep(130, 50, 0.3), 2) * env_exp(int(0.3 * SR), 0.1), 0.8 * lp(noise(d), 1400) * np.sin(np.linspace(0.3, np.pi, n)) ** 1.1 * env_exp(n, 0.35), 0.3 * bp(noise(d), 2200, 6000) * env_exp(n, 0.12)), 0.85)
    d = 1.1; n = int(d * SR)
    save("gas_heavy", mix(sat(sweep(100, 38, 0.5), 3) * env_exp(int(0.5 * SR), 0.16), 0.9 * lp(noise(d), 1000) * np.sin(np.linspace(0.2, np.pi, n)) ** 1.0 * env_exp(n, 0.5), 0.35 * bp(noise(d), 1500, 5000) * env_exp(n, 0.2)), 0.95)
    d = 0.45; n = int(d * SR); save("gas_hiss", mix(lp(noise(d), 4200) * (1 + 0.4 * sine(23, d)) * swell(n, 0.7), 0.3 * bp(noise(d), 200, 700) * env_exp(n, 0.3)), 0.6)
    d = 0.7; n = int(d * SR)
    save("hit_gas", mix(lp(noise(d), 1300) * env_exp(n, 0.16), 0.5 * bp(noise(d), 2500, 8000) * np.clip(sine(41, d) + 0.5, 0, 1) * env_exp(n, 0.25), 0.6 * sat(sweep(150, 48, 0.3), 2) * env_exp(int(0.3 * SR), 0.1)), 0.75)

    # ---- commander guns.  D-gun: a charge, then the blast.  Q-gun: a climbing tone, then the pulse.
    ch, bl = 0.9, 1.4; nc, nb = int(ch * SR), int(bl * SR)
    charge = sum(sweep(f * 0.6, f, ch) * (1 + 0.5 * sine(5 + i * 2, ch)) for i, f in enumerate((330, 332, 495, 498))) * rise(nc, 2.0) + 0.3 * bp(noise(ch), 1500, 7000) * rise(nc, 3)
    gong = bell(98, bl, 0.7, 2.6, 2.4) + 0.6 * bell(147, bl, 0.6, 2.2, 2.4)
    boom = sat(sweep(150, 28, bl) + 0.7 * sine(36, bl), 3) * env_exp(nb, 0.4)
    save("dgun_tympan", mix(0.7 * charge, at(echo(mix(boom, 0.6 * gong, 0.3 * hp(noise(bl), 2000) * env_exp(nb, 0.1)), 0.12, 0.4, 3), ch)), 0.95)
    inhale = lp(noise(ch), 2600) * rise(nc, 1.5) * (1 + 0.5 * sine(11, ch))
    gur = sat(sweep(60, 150, ch) * (1 + 0.7 * sine(9, ch)), 2.5) * rise(nc, 1.4)
    exhale = lp(noise(bl), 1500) * env_exp(nb, 0.5) * (1 + 0.5 * sine(7, bl))
    roar = sat(sweep(110, 36, bl) + 0.6 * sine(48, bl) * (1 + 0.7 * sine(19, bl)), 4) * env_exp(nb, 0.5)
    save("dgun_miasma", mix(0.6 * inhale, 0.8 * gur, at(mix(roar, 0.9 * exhale, 0.4 * bp(noise(bl), 2500, 7000) * env_exp(nb, 0.2)), ch - 0.02)), 0.95)
    cq, pq = 1.6, 1.0; nq, npq = int(cq * SR), int(pq * SR)
    climb = (sweep(110, 1400, cq, "exp") + 0.5 * sweep(222, 2800, cq, "exp")) * rise(nq, 1.8)
    pulse_t = mix(sat(sweep(180, 40, pq), 3) * env_exp(npq, 0.3), 0.5 * bell(440, pq, 0.4, 2.0, 2.0))
    save("qgun_tympan", mix(climb * 0.8, at(echo(pulse_t, 0.11, 0.45, 3), cq)), 0.9)
    climb = (sweep(70, 520, cq, "exp") + 0.6 * lp(noise(cq), 1800) * (1 + sine(15, cq))) * rise(nq, 1.6)
    pulse_m = mix(sat(sweep(130, 36, pq), 3) * env_exp(npq, 0.3), 0.6 * lp(noise(pq), 1200) * env_exp(npq, 0.25))
    save("qgun_miasma", mix(climb * 0.8, at(echo(pulse_m, 0.12, 0.4, 3), cq)), 0.9)


# ------------------------------------------------------------------ 0.18: Tier 3 announcements
# No rng: nothing here changes any older file when the script is rerun.
def tier3():
    # tier 3 online (a lab was upgraded): tier 2's swelling chord, but lower and longer, a seven-bell rising arpeggio, two long final bells,
    # then a falling-and-rising sub sweep under a heavy thump
    d = 3.6; n = int(d * SR)
    pad_ = mix(*[0.6 * fm(f, f * 2.01, 0.9, d) for f in (98, 147, 196, 247, 330)]) * swell(n, 1.1)
    arp = mix(*[at(bell(f, 1.6, 0.45, 1.8), 0.1 + 0.12 * i) for i, f in enumerate((392, 523, 659, 784, 1047, 1319, 1568))])
    low = 0.8 * sat(sweep(120, 38, 1.0), 2) * env_exp(int(1.0 * SR), 0.3)
    save("tier3_ready", mix(0.65 * pad_, arp, at(bell(2093, 2.2, 0.8, 1.4), 0.95), at(bell(1568, 2.2, 0.8, 1.4), 1.1),
                            0.8 * sine(50, 0.5) * env_exp(int(0.5 * SR), 0.15), at(low, 0.9)), 0.9)
    # a tier 3 heavy is ready: a deep gong, a two-note brass-like rise on a fifth, and a sub hit
    d = 2.0; n = int(d * SR)
    gong = mix(bell(98, d, 0.7, 2.2, 2.4), 0.6 * bell(147, d, 0.6, 2.0, 2.4), 0.4 * bell(233, d, 0.5, 1.8, 2.7))
    horn = lambda f, dur: lp(sat(fm(f, f, 1.0, dur) + 0.5 * sine(f * 2, dur), 2), 2400) * np.minimum(1, t_(dur) / 0.05) * env_exp(int(dur * SR), 0.5)
    save("t3_unit_ready", mix(gong, at(horn(196, 0.8), 0.15), at(horn(294, 1.2), 0.5), 0.9 * sat(sweep(90, 34, 0.5), 2) * env_exp(int(0.5 * SR), 0.18)), 0.9)


# ------------------------------------------------------------------ 0.19: thin continuous beams
def thin_beams():
    """A beam weapon restarts its sound every reload cycle, so each file is ~1 s with soft ends: overlapping starts read as one
    unbroken hum.  Low sub drone, a detuned pair a little above it, and a thin 'singing' formant that drifts and trembles (the alien
    part); the lighter beam is higher and faster."""
    for name, base, sing, trem in (("beam_thin_light", 96, 1250, 9.0), ("beam_thin", 68, 880, 6.0)):
        d = 1.0; n = int(d * SR); t = t_(d)
        env = np.minimum(1, t / 0.07) * np.minimum(1, (d - t) / 0.2)
        drone = sat(sine(base / 2, d) * 0.9 + sine(base, d) + 0.55 * sine(base * 2.012, d) + 0.35 * sine(base * 3.0, d), 1.6)
        drift = sing * (1 + 0.04 * np.sin(2 * np.pi * 1.7 * t))
        voice = np.sin(2 * np.pi * np.cumsum(drift) / SR + 2.6 * np.sin(2 * np.pi * 3.7 * t)) * 0.30
        voice += 0.18 * np.sin(2 * np.pi * np.cumsum(drift * 1.505) / SR + 1.9 * np.sin(2 * np.pi * 5.1 * t))
        shimmer = bp(noise(d), 1800, 5200) * 0.07 * (1 + np.sin(2 * np.pi * 23 * t))
        x = env * (1 + 0.28 * np.sin(2 * np.pi * trem * t)) * (drone + voice + shimmer)
        save(name, lp(x, 5200), 0.7)


# ------------------------------------------------------------------ 0.19: the three special weapons (low and alien from the start)
def special_weapons():
    def ring(x, f, depth=0.4):                      # low ring modulation: the metallic, not-of-this-world sideband
        return (1 - depth) * x + depth * x * np.sin(2 * np.pi * f * t_(len(x) / SR))
    # --- HAPTIC branching arc: a low thump, a falling zap and short branching crackles
    for name, d, f0, f1, thump, crk in (("arc_zap", 0.55, 900, 140, 62, 0.8), ("arc_heavy", 0.95, 620, 70, 42, 1.0)):
        n = int(d * SR); body = sweep(f0, f1, d) * env_exp(n, d * 0.28)
        gate_ = lp((noise(d) > 0.55).astype(float), 1800)
        zap = lp(bp(noise(d), 300, 3800) * gate_, 2600) * env_exp(n, d * 0.3)
        branches = mix(*[at(0.7 ** i * lp(bp(noise(0.12), 400, 3000), 2400) * env_exp(int(0.12 * SR), 0.04), 0.07 * (i + 1)) for i in range(1, 4)])
        sub = sat(sine(thump, d), 1.8) * env_exp(n, d * 0.3)
        save(name, lp(ring(mix(0.8 * body, crk * zap, pad(branches, n), 0.9 * sub), 53, 0.35), 5200), 0.85)
    # --- TYMPAN sonar: an inharmonic ping that glides down a little, with one soft echo
    for name, d, f0, tau in (("sonar_ping", 0.8, 360, 0.22), ("sonar_deep", 1.2, 170, 0.34)):
        n = int(d * SR); t = t_(d); gl = f0 * (1 - 0.06 * (1 - np.exp(-t / 0.15)))
        ph = 2 * np.pi * np.cumsum(gl) / SR
        ping = sum(a * np.sin(ph * r + 0.4 * np.sin(2 * np.pi * 3.1 * t)) for r, a in ((1, 1.0), (2.41, 0.45), (3.87, 0.22), (0.5, 0.7)))
        x = lp(ping * env_exp(n, tau) * np.minimum(1, t / 0.006), 3200)
        save(name, lp(echo(ring(x, 29, 0.25), 0.16, 0.38, 2), 3600), 0.85)
    # --- MIASMA sine wave: a gooey, wobbling tone that slides down, with bubbling
    for name, d, f0, f1, vib in (("warble_light", 0.75, 240, 130, 7.0), ("warble_heavy", 1.15, 120, 62, 5.0)):
        n = int(d * SR); t = t_(d)
        f = (f0 * (f1 / f0) ** (t / d)) * (1 + 0.28 * np.sin(2 * np.pi * vib * t))
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR + 1.1) + 0.3 * sat(np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR), 2)
        bub = bp(noise(d), 150, 900) * np.clip(np.sin(2 * np.pi * 21 * t), 0, 1) * 0.5
        env = np.minimum(1, t / 0.05) * env_exp(n, d * 0.45)
        save(name, lp((tone + bub) * env, 2600), 0.8)


def from_sources():
    """sounds that are not made by a recipe in this file (the Haptic touch set) keep their original in tools/sound_src/ and are
    alienized from there, so rerunning never alienizes a file twice"""
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sound_src")
    for name in sorted(ALIEN):
        p = os.path.join(src, name + ".wav")
        if os.path.isfile(p):
            with wave.open(p) as w:
                x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
            save(name, x, 0.8)


if __name__ == "__main__":
    fns = [ui, alerts, voices, weapons, impacts, economy, evolve, ambient, cmd_weapons, announcements, new_factions, tier3, thin_beams, special_weapons, from_sources]
    if "alien" in sys.argv[1:]:        # only the weapon sounds (alienized) + the new beams; nothing else on disk is touched
        ONLY = set(ALIEN) | set(NEW_BEAMS)
        fns = [weapons, impacts, cmd_weapons, new_factions, thin_beams, special_weapons, from_sources]
    for fn in fns:
        fn()
    files = sorted(os.listdir(OUT))
    print("wrote %d files to %s" % (len(files), os.path.abspath(OUT)))
    print(", ".join(files))
